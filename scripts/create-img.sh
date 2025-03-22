#!/bin/bash
# Create bootable boot partition image from staging directory

# Configuration
OUTPUT_IMAGE="radxa-taco-boot.img"
BOOT_SIZE_MB=50  # Size of boot partition in MB
STAGING_DIR="./staging" # Your boot files directory

echo "Creating image of size ${BOOT_SIZE_MB}MB..."
# Create empty image file for boot partition
dd if=/dev/zero of=$OUTPUT_IMAGE bs=1M count=$BOOT_SIZE_MB

echo "Formatting as FAT32..."
# Format as FAT32 (using sudo to ensure permissions)
sudo mkfs.vfat -F 32 -n BOOT $OUTPUT_IMAGE

echo "Mounting image..."
# Create mount point if it doesn't exist
mkdir -p mnt
# Mount the image with sudo to ensure permissions
sudo mount -o loop $OUTPUT_IMAGE mnt

echo "Copying boot files..."
# Copy files to boot partition
sudo cp -r $STAGING_DIR/* mnt/ || echo "Warning: copying boot files returned non-zero exit code"

# Copy initramfs if exists
if [ -f "initramfs.cpio.gz" ]; then
    echo "Copying initramfs..."
    sudo cp initramfs.cpio.gz mnt/
fi

# Ensure cmdline.txt has nr_cpus=1
if [ -f "mnt/cmdline.txt" ]; then
    echo "Updating cmdline.txt..."
    if ! grep -q "nr_cpus=1" mnt/cmdline.txt; then
        sudo sed -i 's/$/ nr_cpus=1/' mnt/cmdline.txt
    fi
else
    echo "Creating cmdline.txt..."
    echo "console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootwait nr_cpus=1" | sudo tee mnt/cmdline.txt
fi

# Make sure config.txt references the initramfs
if [ -f "mnt/config.txt" ]; then
    echo "Updating config.txt..."
    if ! grep -q "initramfs" mnt/config.txt; then
        echo "initramfs initramfs.cpio.gz followkernel" | sudo tee -a mnt/config.txt
    fi
else
    echo "Creating config.txt..."
    sudo bash -c 'cat > mnt/config.txt << EOL
# Boot configuration
kernel=kernel8.img
arm_64bit=1
dtoverlay=vc4-kms-v3d
initramfs initramfs.cpio.gz followkernel
EOL'
fi

# Sync and unmount
echo "Syncing and unmounting..."
sudo sync
sudo umount mnt || echo "Warning: unmount may have failed"

echo "Boot image created: $OUTPUT_IMAGE"
echo "You can write it to SD card with: sudo dd if=$OUTPUT_IMAGE of=/dev/sdX bs=4M status=progress"

