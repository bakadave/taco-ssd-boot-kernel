
# Radxa Taco PCIe Boot Helper

A minimal boot environment that boots from NVMe SSD on Raspberry Pi CM4-equipped Radxa Taco board.

## Overview

According to the official Raxa Taco [wiki page](https://wiki.radxa.com/Taco): 

> Booting from M.2 NVMe SSD is not supported since there is no driver for the PCIe switch on the Taco in the Raspberry Pi bootloader.

**The solution**: 
- Boot a minimal kernel from SD card
- Load PCIe switch drivers
- Use kexec to jump to the full OS on the NVMe drive

While it still is impossible to boot without an SD card inserted, should the card fail, you can just load the kernel to a new card and not lose precious data on the more roboust, and faster drive.

## How It Works

1. **SD Card Bootstrap**: The Raspberry Pi CM4 first boots from the SD card using a minimal kernel and initramfs
2. **PCIe Driver Loading**: The init script mounts the boot partition of the M.2 NVMe SSD
3. **Custom settings are applied (optional)**: you can specify a user and add an SSH key
4. **kexec Transfer**: Using kexec, the system transfers control to the kernel on the NVMe SSD
5. **Regular Operation**: After kexec, the system runs entirely from the NVMe drive

## Key Features

- **Minimal SD Card Use**: The SD card is only used for a few seconds during early boot, significantly extending its lifespan
- **Simple Maintenance**: Updates to the OS can be performed on the NVMe without touching the SD card boot environment
- **High Performance**: Takes full advantage of NVMe speed for system operation
- **User Setup**: Adds SSH keys and user configuration during first boot
- **Reliability**: Includes emergency shell access if boot fails

## Limitations
- **Won't work without an SD card**: SD card is still needed for boot, it just quickly loads over to the SSD and the SD card is not used afterwards
- **Images customized by Raspberry Pi Imager don't work**: For some reason Rasbian images that are customized by the Raspberry Pi Imager don't seem to work. I am working on that.

## Requirements

- Radxa Taco board with Raspberry Pi CM4
- NVMe SSD installed in the M.2 slot
- microSD card (even a small one is sufficient)
- Raspbian or other Linux distribution installed on the NVMe SSD

## Build Instructions

### Install dependencies
```bash
# Install cross-compilation tools
sudo apt update
sudo apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
sudo apt install -y binutils-aarch64-linux-gnu
sudo apt install -y crossbuild-essential-arm64

# Install dependencies for host
sudo apt install -y zlib1g-dev libelf-dev autoconf libtool pkg-config make
```

### Build Linux kernel
```bash
git clone --depth=1 https://github.com/raspberrypi/linux
cd linux
KERNEL=kernel8
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2711_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
```

In menuconfig, enable:
- Power management options -> Suspend to RAM and standby (y) (needed for file based kexec)
- General setup -> Kexec and crash features-> Enable kexcec system call (y)
- General setup -> Kexec and crash features-> Enable kexcec file based system call (y)
- General setup -> Initial RAM filesystem and RAM disk (initramfs/initrd) support (y)
- General setup -> Initramfs source files (leave empty to include initramfs.cpio.xz otherwise specify global path here)
- General setup -> Local version (set Kernel local version name here)
- Platform selection -> Broadcom SoC Support (y)
- Platform selection -> Broadcom BCM2835 family (y)
- Device Drivers - > Mailbox Hardware Support -> BCM2835 Mailbox (y)
- Device Drivers -> Firmware Drivers -> Raspberry Pi Firmware Driver (y)
- PCI support -> PCI Express Port Bus support (y)
- PCI support -> Message Signaled Interrupts (MSI and MSI-X) (y)

```bash
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image modules dtbs

# Copy kernel files to staging dir
mkdir -p ../staging/overlays
cp arch/arm64/boot/Image ../staging/kernel8.img
cp arch/arm64/boot/dts/broadcom/bcm2711-rpi-cm4.dtb ../staging/
cp arch/arm64/boot/dts/broadcom/bcm2711-rpi-4-b.dtb ../staging/
cp arch/arm64/boot/dts/overlays/*.dtbo ../staging/overlays/
cd ..
```

### Download firmware repo
```bash
git clone --depth=1 https://github.com/raspberrypi/firmware
# Copy essential firmware files
cp firmware/boot/bootcode.bin staging/
cp firmware/boot/fixup*.dat staging/
cp firmware/boot/start*.elf staging/
```

### Create config.txt in staging dir
```
kernel=kernel8.img
arm_64bit=1
initramfs initramfs.cpio.gz followkernel
enable_uart=1
dtoverlay=vc4-kms-v3d
```

### Create cmdline.txt in staging dir
```bash
echo console=serial0,115200 console=tty1 nr_cpus=1 rootwait init=/init >> staging/cmdline.txt
```

### Create initramfs
```bash
mkdir -p initramfs/{bin,sbin,proc,sys,dev,etc,lib,mnt/ssd,usr/bin,usr/sbin}

# Make sure init script has executable permissions
chmod +x initramfs/init

# Add essential utilities (busybox)
wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2
tar -xf busybox-1.36.1.tar.bz2
cd busybox-1.36.1

# Configure for static build (all in one binary)
make defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Optional: Disable network utilities to save space
sed -i 's/CONFIG_IFCONFIG=y/# CONFIG_IFCONFIG is not set/' .config
sed -i 's/CONFIG_FEATURE_IFCONFIG_STATUS=y/# CONFIG_FEATURE_IFCONFIG_STATUS is not set/' .config
# Add more network utilities to disable as needed

# Build and install to initramfs
make -j$(nproc)
make CONFIG_PREFIX=../initramfs install
cd ..

# Copy kexec binary to initramfs - NOTE if you want to build your own kexec binary, instructions are in kexec/README.md
cp path/to/kexec-binary/kexec initramfs/sbin/

# Optional: create in initramfs/user_configs/userconfig.txt to create a custom user on first boot. Otherwise pi user is created
mkdir -p initramfs/user_configs
echo my_user:<passwordhash> >> initramfs/user_congfigs/userconf.txt

# Optional: add SSH public key to user above
mkdir -p initramfs/user_configs/ssh_keys
cp your/ssh/key/id_rsa.pub initramfs/ssh_keys/

# Package initramfs
cd initramfs
find . | cpio -H newc -o | gzip > ../staging/initramfs.cpio.gz
cd ..
```

### Preparing the SD Card

```bash
# Format SD card (adjust sdX to your device)
sudo parted /dev/sdX mklabel msdos
sudo parted /dev/sdX mkpart primary fat32 1MiB 100%
sudo mkfs.vfat -F 32 /dev/sdX1

# Mount and copy files
sudo mount /dev/sdX1 /mnt
sudo cp -r staging/* /mnt/
sudo umount /mnt
```

### Testing Your Boot SD Card

1. Insert the SD card into your Raspberry Pi CM4
2. Connect a display if available
3. Power on and observe the boot process
4. If successful, the system will kexec to the kernel on your SSD
5. If unsuccessful, the emergency shell will be available for debugging

## Important Notes

- **Always Required**: The SD card is **essential** for booting, as the CM4 cannot boot directly from the NVMe due to bootloader limitation
- **Read-Only Operation**: After initial boot, the SD card remains untouched, minimizing wear
- **One-Time Setup**: Once configured, the boot environment rarely needs to be updated

## Troubleshooting

If the system fails to boot from NVMe:
- Check display output for errors
- The system will drop to an emergency shell if kexec fails - although afaik it is impossible to connect a keyboard to the Taco
- Verify that PCIe drivers are loading correctly
- Ensure the NVMe drive has a valid bootable OS

---

*Project created by David Baka
*Special thanks to Claude AI for technical assistance with the kexec boot implementation*
