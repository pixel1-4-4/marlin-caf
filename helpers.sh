# Shared interactive kernel build helpers

# Root of the kernel repository for use in helpers
kroot="$(pwd)/$(dirname "$0")"

# Go to the root of the kernel repository
croot() {
    cd "$kroot"
}

# Determine the prefix of a cross-compiling toolchain (@nathanchance)
get_gcc_prefix() {
    local gcc_path="${1}gcc"

    # If the prefix is not already provided
    if [ ! -f "$gcc_path" ]; then
        gcc_path="$(find "$1" \( -type f -o -type l \) -name '*-gcc')"
    fi

    echo "$gcc_path" | head -n1 | sed 's@.*/@@' | sed 's/gcc//'
}

# Get the version of Clang in a user-friendly form
get_clang_version() {
    "$1" --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//'
}

# Get the version of GCC in a user-friendly form
get_gcc_version() {
    "$1" --version|head -n1|cut -d'(' -f2|tr -d ')'|sed -e 's/[[:space:]]*$//'
}

# Define the flags given to make to compile the kernel
MAKEFLAGS=(
    -j$jobs
    ARCH=arm64

    KBUILD_BUILD_USER=kingbri
    KBUILD_BUILD_HOST=kingbri1
)

# Make wrapper for kernel compilation
kmake() {
    make "${MAKEFLAGS[@]}" "$@"
}

# Move kernel image to AnyKernel dir
moveimg() {
    rm -rf AnyKernel/Image.lz4-dtb
    cp out/arch/arm64/boot/Image.lz4-dtb AnyKernel/Image.lz4-dtb
    echo "Copied image file"
}

# Move kernel image to AnyKernel dir
movevbox() {
    rm -rf $HOME/VBOX/Image.lz4-dtb
    echo "Removed old image"
    cp out/arch/arm64/boot/Image.lz4-dtb $HOME/VBOX/Image.lz4-dtb
    echo "Copied new image file, boot from windows"
}

_RELEASE=0

# Create a flashable zip of the current kernel image
mkzip() {
    [ $_RELEASE -eq 0 ] && vprefix=test
    [ $_RELEASE -eq 1 ] && vprefix=v

    cp "$kroot/out/arch/arm64/boot/Image.lz4-dtb" "$kroot/flasher/"

    [ $_RELEASE -eq 0 ] && echo "  • Installing test build $(cat "$kroot/out/.version")" >| "$kroot/flasher/version"
    [ $_RELEASE -eq 1 ] && echo "  • Installing version v$(cat "$kroot/out/.version")" >| "$kroot/flasher/version"
    echo "  • Built on $(date "+%a %b %d, %Y")" >> "$kroot/flasher/version"

    fn="${1:-proton_kernel.zip}"
    rm -f "$fn"
    echo "  ZIP     $fn"
    oldpwd="$(pwd)"
    pushd -q "$kroot/flasher"
    zip -qr9 "$oldpwd/$fn" . -x .gitignore
    popd -q
}

# Produce an incremental kernel build and package it for release
rel() {
    _RELEASE=1

    # Swap out version files
    [ ! -f "$kroot/out/.relversion" ] && echo 0 > "$kroot/out/.relversion"
    mv "$kroot/out/.version" "$kroot/out/.devversion" && \
    mv "$kroot/out/.relversion" "$kroot/out/.version"

    # Compile kernel
    kmake oldconfig # solve a "cached" config
    kmake "$@"

    # Pack zip
    mkzip "builds/ProtonKernel-pixel3-v$(cat "$kroot/out/.version").zip"

    # Revert version
    mv "$kroot/out/.version" "$kroot/out/.relversion" && \
    mv "$kroot/out/.devversion" "$kroot/out/.version"

    _RELEASE=0
}

# Produce a clean kernel build and package it for release
crel() {
    kmake clean && rel "$@"
}

# Reset the version (compile number)
zerover() {
    echo 0 >| "$kroot/out/.version"
}

# Make a clean build of the kernel and package it as a flashable zip
cleanbuild() {
    kmake clean && kmake "$@" && mkzip
}

# Incrementally build the kernel and package it as a flashable zip
incbuild() {
    kmake "$@" && mkzip
}

# Incrementally build the kernel and package it as a flashable test release zip
dbuild() {
    kmake "$@" && dzip
}

# Incrementally build the kernel, package it as a flashable test release zip, then upload it to transfer.sh
tbuild() {
    kmake "$@" && tzip
}

# Create a flashable test release zip
dzip() {
    mkzip "builds/ProtonKernel-pixel3-test$(cat "$kroot/out/.version").zip"
}

# Create a flashable test release zip, then upload it to transfer.sh
tzip() {
    dzip && transfer "builds/ProtonKernel-pixel3-test$(cat "$kroot/out/.version").zip"
}

# Flash the latest kernel zip on the connected device via ADB
ktest() {
    adb wait-for-any && \

    fn="${1:-proton_kernel.zip}"
    is_android=false
    adb shell pgrep gatekeeperd > /dev/null && is_android=true
    if $is_android; then
        adb push "$fn" /data/local/tmp/kernel.zip && \
        adb shell "su -c 'export PATH=/sbin/.core/busybox:$PATH; unzip -p /data/local/tmp/kernel.zip META-INF/com/google/android/update-binary | /system/bin/sh /proc/self/fd/0 unused 1 /data/local/tmp/kernel.zip && /system/bin/svc power reboot'"
            else
        adb push "$fn" /tmp/kernel.zip && \
        adb shell "twrp install /tmp/kernel.zip && /system/bin/svc power reboot"
    fi
}

# Flash the latest kernel zip on the device via SSH over LAN
sktest() {
    fn="proton_kernel.zip"
    [ "x$1" != "x" ] && fn="$1"

    scp "$fn" phone:tmp/kernel.zip && \
    ssh phone "/sbin/su -c 'am broadcast -a net.dinglisch.android.tasker.ACTION_TASK --es task_name \"Kernel Flash Warning\"; export PATH=/sbin/.core/busybox:$PATH; sleep 4; unzip -p /data/data/com.termux/files/home/tmp/kernel.zip META-INF/com/google/android/update-binary | /system/bin/sh /proc/self/fd/0 unused 1 /data/data/com.termux/files/home/tmp/kernel.zip && /system/bin/svc power reboot'"
}

# Flash the latest kernel zip on the device via SSH over VPN
vsktest() {
    fn="proton_kernel.zip"
    [ "x$1" != "x" ] && fn="$1"

    scp "$fn" vphone:tmp/kernel.zip && \
    ssh phone "/sbin/su -c 'am broadcast -a net.dinglisch.android.tasker.ACTION_TASK --es task_name \"Kernel Flash Warning\"; export PATH=/sbin/.core/busybox:$PATH; sleep 4; unzip -p /data/data/com.termux/files/home/tmp/kernel.zip META-INF/com/google/android/update-binary | /system/bin/sh /proc/self/fd/0 unused 1 /data/data/com.termux/files/home/tmp/kernel.zip && /system/bin/svc power reboot'"
}

# Incremementally build the kernel, then flash it on the connected device via ADB
inc() {
    incbuild "$@" && ktest
}

# Incremementally build the kernel, then flash it on the device via SSH over LAN
sinc() {
    incbuild "$@" && sktest
}

# Incremementally build the kernel, then flash it on the device via SSH over VPN
vsinc() {
    incbuild "$@" && vsktest
}

# Incremementally build the kernel, push the ZIP, and flash it on the device via SSH over LAN
psinc() {
    dbuild "$@" && fn="builds/ProtonKernel-pixel3-test$(cat "$kroot/out/.version").zip" && scp "$fn" phone:/sdcard && sktest "$fn"
}

# Incremementally build the kernel, push the ZIP, and flash it on the device via SSH over VPN
pvsinc() {
    dbuild "$@" && fn="builds/ProtonKernel-pixel3-test$(cat "$kroot/out/.version").zip" && scp "$fn" vphone:/sdcard && vsktest "$fn"
}

# Show differences between the committed defconfig and current config
dc() {
    diff arch/arm64/configs/marlin_defconfig "$kroot/out/.config"
}

# Update the defconfig in the git tree
cpc() {
    # Don't use savedefconfig for readability and diffability
    cp "$kroot/out/.config" arch/arm64/configs/b1c1_defconfig
}

# Reset the current config to the committed defconfig
mc() {
    kmake marlin_defconfig
}

# Open an interactive config editor
cf() {
    kmake nconfig
}

# Edit the raw text config
ec() {
    ${EDITOR:-vim} "$kroot/out/.config"
}

# Get a sorted list of the side of various objects in the kernel
osize() {
    find "$kroot/out" -type f -name '*.o' ! -name 'built-in.o' ! -name 'vmlinux.o' \
    	-exec du -h --apparent-size {} + | sort -r -h | head -n "${1:-75}" | \
	perl -pe 's/([\d.]+[A-Z]?).+\/out\/(.+)\.o/$1\t$2.c/g'
}

# Update the subtrees in the kernel repo
utree() {
    git subtree pull --prefix techpack/audio msm-extra $1 # Techpack ASoC audio drivers
    git subtree pull --prefix drivers/staging/qcacld-3.0 qcacld-3.0 $1 # QCA CLD 3.0 Wi-Fi drivers
    git subtree pull --prefix drivers/staging/qca-wifi-host-cmn qca-wfi-host-cmn $1 # QCA Wi-Fi common files
    git subtree pull --prefix drivers/staging/fw-api wlan-fw-api $1 # QCA Wi-Fi firmware API
}

# Create a link to a commit on GitHub
glink() {
    echo "https://github.com/kdrag0n/proton_bluecross/commit/$1"
}

# Retrieve the kernel version from a flashable zip package
zver()
{
    unzip -p "$1" Image.lz4-dtb | lz4 -dc | strings | grep "Linux version 4"
}
