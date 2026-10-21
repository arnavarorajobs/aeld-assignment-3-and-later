#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u
set -o pipefail

OUTDIR=/tmp/aeld
KERNEL_VERSION=v5.15.163
KERNEL_TARBALL_URL="https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION#v}.tar.xz"
BUSYBOX_VERSION=1.33.1
FINDER_APP_DIR=$(realpath "$(dirname "$0")")
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ "$#" -eq 0 ]; then
	echo "Using default directory ${OUTDIR} for output"
elif [ "$#" -eq 1 ]; then
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
else
    echo "Usage: $0 [outdir]" >&2
    exit 1
fi

if ! mkdir -p "$OUTDIR"; then
    echo "Error: could not create output dir: $OUTDIR" >&2
    exit 1
fi
OUTDIR=$(realpath "$OUTDIR")

KERNEL_SRC="$OUTDIR/linux-stable"
KERNEL_TARBALL="$OUTDIR/linux-${KERNEL_VERSION#v}.tar.xz"

if [ ! -f "$KERNEL_TARBALL" ] || ! tar -tJf "$KERNEL_TARBALL" >/dev/null 2>&1; then
    echo "Downloading kernel source tarball for $KERNEL_VERSION"
    wget --tries=5 --timeout=30 \
        -O "$KERNEL_TARBALL.tmp" "$KERNEL_TARBALL_URL"
    tar -tJf "$KERNEL_TARBALL.tmp" >/dev/null
    mv "$KERNEL_TARBALL.tmp" "$KERNEL_TARBALL"
fi

if [ ! -f "$KERNEL_SRC/Makefile" ]; then
    rm -rf "$KERNEL_SRC"
    mkdir -p "$KERNEL_SRC"
    tar -xJf "$KERNEL_TARBALL" --strip-components=1 \
        -C "$KERNEL_SRC"
fi

if [ ! -e "$KERNEL_SRC/arch/$ARCH/boot/Image" ]; then
    cd "$KERNEL_SRC"
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig
    make -j"$(nproc)" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" Image
fi

cp "$KERNEL_SRC/arch/$ARCH/boot/Image" "$OUTDIR/Image"

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

ROOTFS="$OUTDIR/rootfs"

mkdir -p \
    "$ROOTFS/bin" \
    "$ROOTFS/dev" \
    "$ROOTFS/etc" \
    "$ROOTFS/home" \
    "$ROOTFS/lib" \
    "$ROOTFS/proc" \
    "$ROOTFS/root" \
    "$ROOTFS/sbin" \
    "$ROOTFS/sys" \
    "$ROOTFS/tmp" \
    "$ROOTFS/usr/bin" \
    "$ROOTFS/usr/sbin" \
    "$ROOTFS/var"

cd "$OUTDIR"

BUSYBOX_TARBALL="$OUTDIR/busybox-$BUSYBOX_VERSION.tar.bz2"

if [ ! -f "$BUSYBOX_TARBALL" ]; then
    wget -O "$BUSYBOX_TARBALL" \
        "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2"
fi

if [ ! -f "$OUTDIR/busybox/Makefile" ]; then
    rm -rf "$OUTDIR/busybox"
    mkdir -p "$OUTDIR/busybox"
    tar -xjf "$BUSYBOX_TARBALL" --strip-components=1 \
        -C "$OUTDIR/busybox"
fi

cd "$OUTDIR/busybox"


if [ ! -f .config ]; then  
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig
fi

make -j"$(nproc)" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE"
make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CONFIG_PREFIX="$ROOTFS" install

cd "$ROOTFS"

echo "Library dependencies"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

# TODO: Add library dependencies to rootfs
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)

INTERPRETER=$(${CROSS_COMPILE}readelf -l bin/busybox |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')

if [ -z "$INTERPRETER" ]; then
    echo "Error: could not find BusyBox's program interpreter" >&2
    exit 1
fi

mkdir -p "$ROOTFS$(dirname "$INTERPRETER")"
cp -L "$SYSROOT$INTERPRETER" "$ROOTFS$INTERPRETER"

for library in $(${CROSS_COMPILE}readelf -d bin/busybox |
    sed -n 's/.*Shared library: \[\(.*\)\].*/\1/p'); do

    library_source=$(find "$SYSROOT" -name "$library" -print -quit)

    if [ -z "$library_source" ]; then
        echo "Error: could not find $library in $SYSROOT" >&2
        exit 1
    fi

    # Preserve the library's path relative to the toolchain sysroot.
    library_relative=${library_source#"$SYSROOT"/}
    library_destination="$ROOTFS/$library_relative"

    mkdir -p "$(dirname "$library_destination")"
    cp -L "$library_source" "$library_destination"
done

# TODO: Make device nodes
sudo mknod -m 600 "$ROOTFS/dev/console" c 5 1
sudo mknod -m 666 "$ROOTFS/dev/null" c 1 3

# TODO: Clean and build the writer utility
echo "Cross-compiling writer for ARM"
make -C "$FINDER_APP_DIR" clean
make -C "$FINDER_APP_DIR" CROSS_COMPILE="$CROSS_COMPILE"
cp -p "$FINDER_APP_DIR/writer" "$ROOTFS/home/writer"

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
REPO_DIR=$(realpath "$FINDER_APP_DIR/..")
HOME_DIR="$ROOTFS/home"

mkdir -p "$HOME_DIR/conf"

# BusyBox rootfs has /bin/sh, so stage finder.sh with that interpreter.
sed '1s|^#!/bin/bash$|#!/bin/sh|' \
    "$FINDER_APP_DIR/finder.sh" > "$HOME_DIR/finder.sh"

cp "$REPO_DIR/conf/username.txt" "$HOME_DIR/conf/username.txt"
cp "$REPO_DIR/conf/assignment.txt" "$HOME_DIR/conf/assignment.txt"

# In the rootfs, conf/ is beside finder-test.sh, not above it.
sed 's|../conf/assignment.txt|conf/assignment.txt|g' \
    "$FINDER_APP_DIR/finder-test.sh" > "$HOME_DIR/finder-test.sh"

cp "$FINDER_APP_DIR/autorun-qemu.sh" "$HOME_DIR/autorun-qemu.sh"

chmod +x "$HOME_DIR/finder.sh" \
         "$HOME_DIR/finder-test.sh" \
         "$HOME_DIR/autorun-qemu.sh"

# TODO: Chown the root directory
sudo chown -R root:root "$ROOTFS"

# TODO: Create initramfs.cpio.gz
echo "Creating initramfs"
(
    cd "$ROOTFS"
    sudo find . -print0 | sudo cpio --null -o -H newc | gzip -9 \
        > "$OUTDIR/initramfs.cpio.gz"
)
