
.PHONY: all clean distclean
.PHONY: meshtastic meshcore loader merged
.PHONY: flash-meshtastic flash-meshcore flash-loader flash-merged flash-meshtastic-fs

# Default variant (can be overridden with VARIANT=heltec_v3 make ...)
VARIANT ?= heltec_v4

# Load variant-specific configuration
VARIANT_FILE = variants/$(VARIANT).mk
ifeq ($(wildcard $(VARIANT_FILE)),)
$(error Variant '$(VARIANT)' not found. Available variants: $(patsubst variants/%.mk,%,$(wildcard variants/*.mk)))
endif
include $(VARIANT_FILE)

# Validate that variant specified a partition layout
ifndef PARTITION_LAYOUT
$(error Variant '$(VARIANT)' must specify PARTITION_LAYOUT)
endif

# Validate partition layout exists
PARTITION_LAYOUT_DIR = partitions/$(PARTITION_LAYOUT)
ifeq ($(wildcard $(PARTITION_LAYOUT_DIR)),)
$(error Partition layout '$(PARTITION_LAYOUT)' not found. Available layouts: $(patsubst partitions/%,%,$(wildcard partitions/*)))
endif

# Load partition layout addresses
PARTITION_ADDRESSES_FILE = $(PARTITION_LAYOUT_DIR)/addresses.mk
ifeq ($(wildcard $(PARTITION_ADDRESSES_FILE)),)
$(error Partition layout '$(PARTITION_LAYOUT)' is missing addresses.mk file)
endif
include $(PARTITION_ADDRESSES_FILE)

# ESP32 Tools (from PlatformIO packages)
ESP32_FRAMEWORK_TOOLS = .platformio/packages/framework-arduinoespressif32/tools
GEN_ESP32PART = python3 $(ESP32_FRAMEWORK_TOOLS)/gen_esp32part.py
ESPTOOL = python3 .platformio/packages/tool-esptoolpy/esptool.py

# Directory structure
SRC_DIR = modules
BUILD_DIR = build
PATCH_DIR = patches
PARTITION_DIR = partitions/$(PARTITION_LAYOUT)
PARTITION_FILE = $(PARTITION_DIR)/partitions.csv          # Real flash layout (for merged binary)
PARTITION_MESHCORE = $(PARTITION_DIR)/partitions-meshcore.csv     # Build-time partition table for Meshcore
PARTITION_MESHTASTIC = $(PARTITION_DIR)/partitions-meshtastic.csv # Build-time partition table for Meshtastic

# Source directories
MESHTASTIC_SRC = $(SRC_DIR)/meshtastic
MESHCORE_SRC = $(SRC_DIR)/meshcore
LOADER_SRC = loader

# Build directories
MESHTASTIC_BUILD = $(BUILD_DIR)/meshtastic
MESHCORE_BUILD = $(BUILD_DIR)/meshcore

# Patch files (common + variant-specific only)
MESHTASTIC_PATCHES = $(PATCH_DIR)/meshtastic/common.patch $(PATCH_DIR)/meshtastic/$(VARIANT).patch

MESHCORE_PATCHES = $(PATCH_DIR)/meshcore/common.patch $(PATCH_DIR)/meshcore/$(VARIANT).patch

# Marker files to track build stages
MESHTASTIC_PATCH_MARKER = $(MESHTASTIC_BUILD)/.patched
MESHCORE_PATCH_MARKER = $(MESHCORE_BUILD)/.patched

# Firmware outputs
MESHTASTIC_FW_DIR = $(MESHTASTIC_BUILD)/.pio/build/$(MESHTASTIC_ENV)
MESHTASTIC_FW = $(MESHTASTIC_FW_DIR)/firmware.bin
MESHTASTIC_FS = $(MESHTASTIC_FW_DIR)/littlefs.bin
MESHCORE_FW = $(MESHCORE_BUILD)/.pio/build/$(MESHCORE_ENV)/firmware.bin
LOADER_FW = $(LOADER_SRC)/.pio/build/$(LOADER_ENV)/firmware.bin

MESHTASTIC_BOOTLOADER = $(MESHTASTIC_BUILD)/.pio/build/$(MESHTASTIC_ENV)/bootloader.bin
PARTITION_BIN = $(BUILD_DIR)/partitions.bin

MERGED_FW = $(BUILD_DIR)/firmware-merged-$(VARIANT).bin

all: meshtastic meshcore loader merged

# Copy and patch meshtastic source
$(MESHTASTIC_PATCH_MARKER): $(MESHTASTIC_PATCHES) $(PARTITION_MESHTASTIC) | $(BUILD_DIR)
	@echo "==> Copying Meshtastic source to build directory..."
	@rm -rf $(MESHTASTIC_BUILD)
	@rsync -a --exclude='.git' --exclude='.pio' $(MESHTASTIC_SRC)/ $(MESHTASTIC_BUILD)/
	@echo "==> Applying Meshtastic patches..."
	@cd $(MESHTASTIC_BUILD) && \
		for patch in $(abspath $(MESHTASTIC_PATCHES)); do \
			echo "    Applying $$(basename $$patch)..."; \
			patch -p1 < $$patch; \
		done
	@cp $(PARTITION_MESHTASTIC) $(MESHTASTIC_BUILD)/partitions.csv
	@touch $@
	@echo "    Meshtastic patches applied (build-time partitions: $(PARTITION_MESHTASTIC))"

# Build meshtastic firmware
$(MESHTASTIC_FW) $(MESHTASTIC_FS): $(MESHTASTIC_PATCH_MARKER)
	@echo "==> Building Meshtastic firmware..."
	@cd $(MESHTASTIC_BUILD) && pio run -e $(MESHTASTIC_ENV)
	@MESHTASTIC_FW_SRC=$$(find $(MESHTASTIC_FW_DIR) -maxdepth 1 -name 'firmware-*.bin' ! -name '*.factory.bin' ! -name 'littlefs-*.bin' 2>/dev/null | head -1); \
	if [ -n "$$MESHTASTIC_FW_SRC" ]; then \
		echo "    Meshtastic firmware built: $$MESHTASTIC_FW_SRC"; \
		cp "$$MESHTASTIC_FW_SRC" "$(MESHTASTIC_FW)"; \
		MESHTASTIC_FS_SRC=$$(find $(MESHTASTIC_FW_DIR) -maxdepth 1 -name 'littlefs-*.bin' 2>/dev/null | head -1); \
		if [ -n "$$MESHTASTIC_FS_SRC" ]; then \
			echo "    Meshtastic filesystem found: $$MESHTASTIC_FS_SRC"; \
			cp "$$MESHTASTIC_FS_SRC" "$(MESHTASTIC_FS)"; \
		else \
			echo "    ERROR: Meshtastic filesystem not found"; \
			exit 1; \
		fi; \
	else \
		echo "    ERROR: Meshtastic firmware not found"; \
		exit 1; \
	fi

meshtastic: $(MESHTASTIC_FW) $(MESHTASTIC_FS)
	@echo "Meshtastic build complete"

# Copy and patch meshcore source
$(MESHCORE_PATCH_MARKER): $(MESHCORE_PATCHES) $(PARTITION_MESHCORE) | $(BUILD_DIR)
	@echo "==> Copying Meshcore source to build directory..."
	@rm -rf $(MESHCORE_BUILD)
	@rsync -a --exclude='.git' --exclude='.pio' $(MESHCORE_SRC)/ $(MESHCORE_BUILD)/
	@echo "==> Applying Meshcore patches..."
	@cd $(MESHCORE_BUILD) && \
		for patch in $(abspath $(MESHCORE_PATCHES)); do \
			echo "    Applying $$(basename $$patch)..."; \
			patch -p1 < $$patch; \
		done
	@cp $(PARTITION_MESHCORE) $(MESHCORE_BUILD)/partitions.csv
	@touch $@
	@echo "    Meshcore patches applied (build-time partitions: $(PARTITION_MESHCORE))"

# Build meshcore firmware
$(MESHCORE_FW): $(MESHCORE_PATCH_MARKER)
	@echo "==> Building Meshcore firmware..."
	@cd $(MESHCORE_BUILD) && pio run -e $(MESHCORE_ENV)
	@echo "    Meshcore firmware built: $(MESHCORE_FW)"

meshcore: $(MESHCORE_FW)
	@echo "Meshcore build complete"

$(LOADER_FW): $(LOADER_SRC)/src/main.cpp
	@echo "==> Building Loader firmware..."
	@cd $(LOADER_SRC) && pio run -e $(LOADER_ENV)
	@echo "    Loader firmware built: $(LOADER_FW)"

loader: $(LOADER_FW)
	@echo "Loader build complete"

# Convert partitions CSV to binary format
$(PARTITION_BIN): $(PARTITION_FILE) | $(BUILD_DIR)
	@echo "==> Converting partition table to binary..."
	$(GEN_ESP32PART) $(PARTITION_FILE) $(PARTITION_BIN)
	@echo "    Partition table binary created: $(PARTITION_BIN)"

$(MERGED_FW): $(MESHTASTIC_FW) $(MESHTASTIC_FS) $(MESHCORE_FW) $(LOADER_FW) $(PARTITION_BIN)
	@echo "==> Building merged firmware binary..."
	@if [ ! -f "$(MESHTASTIC_BOOTLOADER)" ]; then \
		echo "ERROR: Bootloader not found at $(MESHTASTIC_BOOTLOADER)"; \
		exit 1; \
	fi
	$(ESPTOOL) --chip $(CHIP_TYPE) merge_bin \
		--output $(MERGED_FW) \
		$(BOOTLOADER_ADDR) $(MESHTASTIC_BOOTLOADER) \
		$(PARTITION_ADDR) $(PARTITION_BIN) \
		$(FACTORY_ADDR) $(LOADER_FW) \
		$(MESHCORE_ADDR) $(MESHCORE_FW) \
		$(MESHTASTIC_ADDR) "$(MESHTASTIC_FW)" \
		$(MESHTASTIC_FS_ADDR) "$(MESHTASTIC_FS)"
	@echo ""
	@echo "Merged firmware created: $(MERGED_FW)"
	@echo "  Size: $$(du -h $(MERGED_FW) | cut -f1)"

merged: $(MERGED_FW)
	@echo "Merged firmware build complete"
	@echo ""
	@echo "To flash the complete merged firmware:"
	@echo "  make flash-merged"

flash-meshtastic: $(MESHTASTIC_FW)
	@echo "==> Flashing Meshtastic to OTA_1 partition at $(MESHTASTIC_ADDR)..."
	$(ESPTOOL) $(MESHTASTIC_ADDR) "$(MESHTASTIC_FW)"
	@echo "Meshtastic flashed"

flash-meshcore: $(MESHCORE_FW)
	@echo "==> Flashing Meshcore to OTA_0 partition at $(MESHCORE_ADDR)..."
	$(ESPTOOL) write_flash $(MESHCORE_ADDR) $(MESHCORE_FW)
	@echo "Meshcore flashed"

flash-loader: $(LOADER_FW)
	@echo "==> Flashing Loader to factory partition at $(FACTORY_ADDR)..."
	$(ESPTOOL) write_flash $(FACTORY_ADDR) $(LOADER_FW)
	@echo "Loader flashed"

flash-meshtastic-fs: $(MESHTASTIC_FS)
	@echo "==> Flashing Meshtastic filesystem to $(MESHTASTIC_FS_ADDR)..."
	$(ESPTOOL) $(MESHTASTIC_FS_ADDR) "$(MESHTASTIC_FS)"
	@echo "Meshtastic filesystem flashed"

flash-merged: $(MERGED_FW)
	@echo "==> Flashing merged firmware (complete image)..."
	@echo ""
	$(ESPTOOL) write_flash 0x0000 $(MERGED_FW)
	@echo ""
	@echo "Merged firmware flashed successfully!"

clean:
	@echo "==> Cleaning build artifacts..."
	@if [ -d "$(MESHTASTIC_BUILD)" ]; then \
		echo "    Cleaning Meshtastic build artifacts..."; \
		cd $(MESHTASTIC_BUILD) && pio run -e $(MESHTASTIC_ENV) --target clean 2>/dev/null || true; \
	fi
	@if [ -d "$(MESHCORE_BUILD)" ]; then \
		echo "    Cleaning Meshcore build artifacts..."; \
		cd $(MESHCORE_BUILD) && pio run -e $(MESHCORE_ENV) --target clean 2>/dev/null || true; \
	fi
	@echo "    Removing marker files..."
	@rm -f $(MESHTASTIC_PATCH_MARKER) $(MESHCORE_PATCH_MARKER)
	@rm -f $(PARTITION_BIN) $(MERGED_FW)
	@echo "    Build artifacts cleaned (libraries preserved)"
	@echo ""
	@echo "Note: To completely remove build directory including libraries, use 'make distclean'"

distclean:
	@echo "==> Removing entire build directory (including library cache)..."
	@rm -rf $(BUILD_DIR)
	@echo "    Build directory removed"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
