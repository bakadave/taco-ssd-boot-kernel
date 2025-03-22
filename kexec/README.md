### Build on target system (another RPi4)

# Install build packages
sudo apt update
sudo apt install -y build-essential git autoconf libtool pkg-config make
sudo apt install -y zlib1g-dev libelf-dev

# Get source
wget https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git/snapshot/kexec-tools-2.0.25.tar.gz
tar -xzvf kexec-tools-2.0.25.tar.gz
cd kexec-tools-2.0.25/

# Bootstrap the build system
./bootstrap

# Configure for static linking and no debug info
CFLAGS="-Os -s -DNDEBUG" LDFLAGS="-static -s" ./configure

# Build
make -j$(nproc)

# Optional: strip the binary
strip --strip-all build/sbin/kexec

# Verify the binary is ARM64 and statically linked
file build/sbin/kexec
aarch64-linux-gnu-readelf -h build/sbin/kexec | grep Machine
ldd build/sbin/kexec  # Should say "not a dynamic executable"

# The resulting binary is at build/sbin/kexec


### Cross-compile
# Install cross-compilation tools
sudo apt update
sudo apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
sudo apt install -y binutils-aarch64-linux-gnu
sudo apt install -y crossbuild-essential-arm64

# Install dependencies for host
sudo apt install -y zlib1g-dev libelf-dev autoconf libtool pkg-config make

# Get kexec-tools source
wget https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git/snapshot/kexec-tools-2.0.25.tar.gz
tar -xzvf kexec-tools-2.0.25.tar.gz
cd kexec-tools-2.0.25/

# Bootstrap the build system
./bootstrap

# Configure for cross-compilation with static linking
CC=aarch64-linux-gnu-gcc \
CFLAGS="-Os" \
LDFLAGS="-static" \
./configure --host=aarch64-linux-gnu \
            --build=$(gcc -dumpmachine) \
            --target=aarch64-linux-gnu

# Build
make -j$(nproc)

# Optional: strip the binary
aarch64-linux-gnu-strip --strip-all build/sbin/kexec

# Verify the binary is ARM64 and statically linked
file build/sbin/kexec
aarch64-linux-gnu-readelf -h build/sbin/kexec | grep Machine
ldd build/sbin/kexec  # Should say "not a dynamic executable"

# The resulting binary is at build/sbin/kexec

### Troubleshooting

## If you encounter "Failed to load kdump kernel" during kexec:
# This is normal when not using kexec for crash dumps - you can ignore this message.

## If kexec seems to work but system freezes:
# Try passing additional options like:
#   kexec --load /path/to/kernel --initrd=/path/to/initrd --command-line="..." --reuse-cmdline