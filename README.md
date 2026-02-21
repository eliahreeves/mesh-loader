# Mesh Loader
"Dual Boot" firmware for running Meshcore and Meshtastic on a single Ep32 based device without re-flashing. Currently, only works for Heltec v4, but should be very simple to contribute patches for other variants so long as they have sufficient flash (6MB+).

## What Does it Do?

This project pulls Meshtastic and Meshcore source code and patches it to be able to coexist. It then writes them along with needed file systems and a loader to swap between at boot. Each time the Esp32 boots it will first boot to the loader program. If there is no interaction for 2 seconds the loader will boot the last booted firmware if the button is pressed the other firmware will boot.

## Flashing

1. Clone the repo recursively to get submodules.
```bash
git clone --recursive <URL>
```

2. Install needed dependencies automatically with nix or manually.
```bash
nix develop
```
3. Set your variant:
```bash
export VARIANT=heltec_v4
```
4. Run targets form the [Makefile](./Makefile).
To build a merged binary:
```bash
make merged
```
To flash the merged binary:
```bash
make flash-merged
```
Note that precompiled releases may be available in the releases section. These can be flashed with esptool or similar.

## Adding a Patch for Your Device
### Adding Loader Variant
You need to add a new loader variant to [loader/variants](loader/variants). I recommend copying the platformio config for your variant from meshcore and then removing parts that are not needed.
### Adding mk Config
Create a new `.mk` file based on [variants/heltec_v4.mk](variants/heltec_v4.mk). This file needs to have the same name as the `.patch` file which must be the same as the variant name.

### Adding Partition Config (Optional)
if a size/layout that will work for your flash does not exist you may create one in [partitions](./partitions/).

### Adding the Patch (Optional)
This step should be avoided unless necessary. It should be possible to only use already present patches.
1. Make your device-specific modifications to the module directly to the meshtastic/meshcore source code.
2. Generate the patch file:.
```bash
cd modules/<module name> && git add . && git diff --cached > ../../patches/<module_name>/<variant_name>.patch
```
3. Confirm the patch was successfully generated, then restore the module:
```bash
cd modules/<module name> && git reset --hard HEAD
```
### Test
Test with:
```bash
VARIANT=<variant name> make flash-merged
```
Then make a PR others can benefit.
## Partition Structure
This directory (`partitions/`) contains partition table configurations crucial for defining how the ESP32's flash memory is divided among different firmware components.

### Structure
Each subdirectory within `partitions/` (e.g., `16mb_default/`) represents a specific partition layout configuration.

### Required Files in Each Layout
Each layout directory must contain these four files:
1.  `addresses.mk`: Defines memory addresses for each partition, loaded by the main Makefile.
2.  `partitions.csv`: Specifies the real flash layout used when combining all firmware into a single merged binary.
3.  `partitions-meshcore.csv`: The build-time partition table specifically for Meshcore.
4.  `partitions-meshtastic.csv`: The build-time partition table specifically for Meshtastic.

## How Does it Work?
This works by using Over-the-Air partitions meant for uploading firmware in deployment. The Esp32 chooses a partition to boot into, but the firmware in each partition never mark themselves as valid forcing a rollback to the loader partition on boot.

There are three patches:
1. Loader patches to make the esp32 not mark partitions as valid.
2. File system patches to make the firmwares not conflict.
3. Bluetooth patch to offset the Meshcore MAC address for easier connecting.

## Drawbacks
- Much less flash for a file system.
- Does not work with OTA updates.
- ~2 seconds slower boot.

## Alternatives
- [Launcher](https://github.com/bmorcelli/Launcher): An option for devices with an SD card. May be possible to make it work from flash like `Mesh Loader` does, but I am not sure.
