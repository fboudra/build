################################################################################
# Following variables defines how the NS_USER (Non Secure User - Client
# Application), NS_KERNEL (Non Secure Kernel), S_KERNEL (Secure Kernel) and
# S_USER (Secure User - TA) are compiled
################################################################################
override COMPILE_NS_USER   := 64
override COMPILE_NS_KERNEL := 64
override COMPILE_S_USER    := 64
override COMPILE_S_KERNEL  := 64

################################################################################
# Board specific
# Toradex Verdin iMX8M Plus board is based on NXP i.MX8M Plus SoC
# Variants from 1 to 8 GB LPDDR4s (1/2/4/8Gb)
################################################################################
TFA_PLATFORM      ?= imx8mp
OPTEE_OS_PLATFORM ?= imx-mx8mpevk
U_BOOT_DEFCONFIG  ?= verdin-imx8mp_defconfig
U_BOOT_DT         ?= imx8mp-verdin-wifi-dev.dtb
LINUX_DT          ?= imx8mp-verdin-wifi-dev.dtb
MKIMAGE_DT        ?= fsl-imx8mp-evk.dtb
MKIMAGE_SOC       ?= iMX8MP
ATF_LOAD_ADDR     ?= 0x00970000
TEE_LOAD_ADDR     ?= 0xfe000000
UART_BASE         ?= 0x30880000
DDR_SIZE          ?= 0x100000000

BR2_TARGET_GENERIC_GETTY_PORT ?= ttymxc2

################################################################################
# Includes
################################################################################
include common.mk

################################################################################
# Paths to git projects and various binaries
################################################################################
FIRMWARE_VERSION	?= firmware-imx-8.22
FIRMWARE_URL		?= https://www.nxp.com/lgfiles/NMG/MAD/YOCTO/$(FIRMWARE_VERSION).bin

FIRMWARE_PATH		?= $(ROOT)/out-firmware
FIRMWARE_DDR_PATH	?= $(FIRMWARE_PATH)/$(FIRMWARE_VERSION)/firmware/ddr/synopsys
FIRMWARE_HDMI_PATH	?= $(FIRMWARE_PATH)/$(FIRMWARE_VERSION)/firmware/hdmi/cadence
MKIMAGE_PATH		?= $(ROOT)/imx-mkimage
MKIMAGE_SOC_PATH	?= $(MKIMAGE_PATH)/iMX8M
OUT_PATH		?= $(ROOT)/out
TF_A_PATH		?= $(ROOT)/trusted-firmware-a

DEBUG			 = 0

################################################################################
# Targets
################################################################################
.PHONY: all
all: mkimage linux buildroot prepare-images | toolchains

.PHONY: clean
clean: ddr-firmware-clean optee-os-clean tfa-clean u-boot-clean mkimage-clean linux-clean buildroot-clean

################################################################################
# Toolchain
################################################################################
include toolchain.mk

################################################################################
# U-Boot
################################################################################
U-BOOT_EXPORTS = CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"

.PHONY: u-boot-config
u-boot-config:
ifeq ($(wildcard $(UBOOT_PATH)/.config),)
	$(U-BOOT_EXPORTS) $(MAKE) -C $(UBOOT_PATH) $(U_BOOT_DEFCONFIG)
endif

.PHONY: u-boot-menuconfig
u-boot-menuconfig: u-boot-config
	$(U-BOOT_EXPORTS) $(MAKE) -C $(UBOOT_PATH) menuconfig

.PHONY: u-boot
u-boot: u-boot-config ddr-firmware tfa
	# Copy DDR4 firmware
	cp $(FIRMWARE_PATH)/$(FIRMWARE_VERSION)/firmware/ddr/synopsys/lpddr4*.bin $(UBOOT_PATH)
	# Copy BL31 binary from TF-A
	cp $(TF_A_PATH)/build/$(TFA_PLATFORM)/*/bl31.bin $(UBOOT_PATH)
	# Build U-Boot
	$(U-BOOT_EXPORTS) $(MAKE) -C $(UBOOT_PATH)

.PHONY: u-boot-clean
u-boot-clean:
	cd $(UBOOT_PATH) && git clean -xdf

.PHONY: u-boot-cscope
u-boot-cscope:
	$(U-BOOT_EXPORTS) $(MAKE) -C $(UBOOT_PATH) cscope

################################################################################
# DDR4 Firmware
################################################################################
.PHONY: ddr-firmware
ddr-firmware:
	# DDR is only exported to $PWD, cd to $(FIRMWARE_PATH) before unpacking
	if [ ! -d "$(FIRMWARE_PATH)" ]; then \
		mkdir -p $(FIRMWARE_PATH); \
		wget $(FIRMWARE_URL) -O $(FIRMWARE_PATH)/firmware.bin; \
		chmod +x $(FIRMWARE_PATH)/firmware.bin; \
		(cd $(FIRMWARE_PATH) && ./firmware.bin --auto-accept); \
	fi

.PHONY: ddr-firmware-clean
ddr-firmware-clean:
	rm -rf $(FIRMWARE_PATH)

################################################################################
# ARM Trusted Firmware
################################################################################
TF_A_EXPORTS = CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"

TF_A_FLAGS += BL32=$(OPTEE_OS_PATH)/out/arm/core/tee-raw.bin
TF_A_FLAGS += BL32_BASE=$(TEE_LOAD_ADDR)
TF_A_FLAGS += DEBUG=$(DEBUG)
TF_A_FLAGS += DEBUG_CONSOLE=0
TF_A_FLAGS += ERRATA_A53_1530924=1
TF_A_FLAGS += IMX_BOOT_UART_BASE=$(UART_BASE)
TF_A_FLAGS += LOG_LEVEL=0
TF_A_FLAGS += PLAT=$(TFA_PLATFORM)
TF_A_FLAGS += SPD=opteed
#TF_A_FLAGS += V=1

.PHONY: tfa
tfa: optee-os
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) bl31

.PHONY: tfa-clean
tfa-clean:
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) clean
	cd $(TF_A_PATH) && git clean -xdf

################################################################################
# OP-TEE
################################################################################
CFG_TEE_CORE_LOG_LEVEL = 0

OPTEE_OS_COMMON_FLAGS += CFG_DDR_SIZE=$(DDR_SIZE)
OPTEE_OS_COMMON_FLAGS += CFG_TZDRAM_START=${TEE_LOAD_ADDR}
OPTEE_OS_COMMON_FLAGS += CFG_UART_BASE=$(UART_BASE)
OPTEE_OS_COMMON_FLAGS += CFG_TZC380=y

.PHONY: optee-os
optee-os: optee-os-common

.PHONY: optee-os-clean
optee-os-clean: optee-os-clean-common

################################################################################
# imx-mkimage
################################################################################
#MKIMAGE_TARGET = DCD_BOARD=imx8mp_evk flash_evk_emmc_fastboot
#MKIMAGE_TARGET = flash_hdmi_spl_uboot
MKIMAGE_TARGET = flash_spl_uboot

mkimage: u-boot
	cp $(FIRMWARE_DDR_PATH)/lpddr4_pmu_train_*.bin $(MKIMAGE_SOC_PATH)/
	cp $(FIRMWARE_HDMI_PATH)//signed_hdmi_*.bin $(MKIMAGE_SOC_PATH)/
	cp $(OPTEE_OS_PATH)/out/arm/core/tee-raw.bin $(MKIMAGE_SOC_PATH)/tee.bin
	cp $(TF_A_PATH)/build/$(TFA_PLATFORM)/*/bl31.bin $(MKIMAGE_SOC_PATH)/
	cp $(UBOOT_PATH)/spl/u-boot-spl.bin $(MKIMAGE_SOC_PATH)/
	cp $(UBOOT_PATH)/u-boot-nodtb.bin $(MKIMAGE_SOC_PATH)/
	cp $(UBOOT_PATH)/arch/arm/dts/$(U_BOOT_DT) $(MKIMAGE_SOC_PATH)/$(MKIMAGE_DT)
	cp $(UBOOT_PATH)/tools/mkimage $(MKIMAGE_SOC_PATH)/mkimage_uboot
	# imx8mp: allow to override TEE_LOAD_ADDR
	# https://github.com/nxp-imx/imx-mkimage/pull/3
	sed -i 's/TEE_LOAD_ADDR =  /TEE_LOAD_ADDR ?= /' $(MKIMAGE_SOC_PATH)/soc.mak
	(cd $(MKIMAGE_PATH) && TEE_LOAD_ADDR=$(TEE_LOAD_ADDR) \
		$(MAKE) SOC=$(MKIMAGE_SOC) $(MKIMAGE_TARGET))
mkimage-clean:
	cd $(MKIMAGE_PATH) && git clean -xdf
	rm -f $(BUILD_PATH)/mkimage_imx8

################################################################################
# Linux
################################################################################
LINUX_DEFCONFIG_COMMON_ARCH := arm64
LINUX_DEFCONFIG_COMMON_FILES := $(LINUX_PATH)/arch/arm64/configs/defconfig

linux-defconfig: $(LINUX_PATH)/.config

LINUX_COMMON_FLAGS += ARCH=arm64

linux: linux-common
	$(MAKE) -C $(LINUX_PATH) $(LINUX_COMMON_FLAGS) freescale/$(LINUX_DT)
	$(MAKE) -C $(LINUX_PATH) $(LINUX_COMMON_FLAGS) INSTALL_MOD_STRIP=1 \
		INSTALL_MOD_PATH=$(ROOT)/module_output modules_install

linux-defconfig-clean: linux-defconfig-clean-common

LINUX_CLEAN_COMMON_FLAGS += ARCH=arm64

linux-clean: linux-clean-common

LINUX_CLEANER_COMMON_FLAGS += ARCH=arm64

linux-cleaner: linux-cleaner-common

.PHONY: prepare-images
prepare-images: linux u-boot buildroot
	@mkdir -p $(OUT_PATH)
	@cp $(MKIMAGE_SOC_PATH)/flash.bin $(OUT_PATH)
	@cp $(LINUX_PATH)/arch/arm64/boot/Image $(OUT_PATH)
	@cp $(LINUX_PATH)/arch/arm64/boot/dts/freescale/$(LINUX_DT) $(OUT_PATH)
	@cp $(ROOT)/out-br/images/rootfs.tar $(OUT_PATH)

################################################################################
# Buildroot/RootFS
################################################################################
.PHONY: update_rootfs
update_rootfs: u-boot linux
	@cd $(ROOT)/module_output && find . | cpio -pudm $(BUILDROOT_TARGET_ROOT)
	@cd $(ROOT)/build

.PHONY: buildroot
buildroot: update_rootfs
