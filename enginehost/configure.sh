#!/bin/sh
# Configures FFmpeg for Enginehost (Droidtop/tracker#906): LGPL only, nothing on but
# components.txt, no protocols, no network, no devices, no filters, no encoders or
# muxers, no programs, built hardened. dav1d (the submodule enginehost/dav1d, BSD) is
# built first, static and with the same flags, into ./dav1d-prefix, and linked into
# libavcodec for AV1. Needs meson and ninja. Run from an empty build directory:
#
#   ../enginehost/configure.sh host                 # this machine, for the checks
#   ../enginehost/configure.sh android arm64-v8a    # needs ANDROID_NDK_HOME
#   ../enginehost/configure.sh android x86_64
#
# Extra arguments after the target go to FFmpeg's configure as they are.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/.." && pwd)
target=${1:?usage: configure.sh host|android ABI [configure options...]}
shift

enable=""
while read -r kind name; do
	case "$kind" in ''|'#'*) continue ;; esac
	enable="$enable --enable-$kind=$name"
done < "$here/components.txt"

# Hardening (#906): stack protector, fortified libc calls, full RELRO with immediate
# binding, no executable stacks. PIC everywhere, since the libraries are shared.
hard_cflags="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIC"
hard_ldflags="-Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack"

cross=""
dav1d_cross=""
case "$target" in
	host)
		;;
	android)
		abi=${1:?usage: configure.sh android arm64-v8a|x86_64}
		shift
		api=${ANDROID_API:-28}
		ndk=${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point at an NDK}
		bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
		case "$abi" in
			arm64-v8a) arch=aarch64; triple=aarch64-linux-android ;;
			x86_64)    arch=x86_64;  triple=x86_64-linux-android ;;
			*) echo "configure.sh: unknown ABI $abi (arm64-v8a or x86_64)" >&2; exit 2 ;;
		esac
		# meson's cross file for dav1d: the same compiler and tools.
		cat > dav1d-cross.ini <<CROSS
[binaries]
c = '$bin/$triple$api-clang'
ar = '$bin/llvm-ar'
strip = '$bin/llvm-strip'
[host_machine]
system = 'android'
cpu_family = '$arch'
cpu = '$arch'
endian = 'little'
CROSS
		dav1d_cross="--cross-file=dav1d-cross.ini"
		cross="--enable-cross-compile --target-os=android --arch=$arch
		       --cc=$bin/$triple$api-clang --cxx=$bin/$triple$api-clang++
		       --ar=$bin/llvm-ar --nm=$bin/llvm-nm --ranlib=$bin/llvm-ranlib
		       --strip=$bin/llvm-strip"
		;;
	*)
		echo "configure.sh: unknown target $target (host or android)" >&2
		exit 2
		;;
esac

# dav1d: static, PIC, no tools or tests, the hardening flags; installed into
# ./dav1d-prefix, where FFmpeg's configure finds it through pkg-config.
[ -f "$here/dav1d/meson.build" ] || { echo "configure.sh: enginehost/dav1d is empty; run git submodule update --init" >&2; exit 2; }
prefix=$(pwd)/dav1d-prefix
# shellcheck disable=SC2086
meson setup dav1d-build "$here/dav1d" $dav1d_cross \
	--prefix="$prefix" --libdir=lib --buildtype=release \
	-Ddefault_library=static -Db_staticpic=true \
	-Denable_tools=false -Denable_tests=false -Denable_docs=false \
	-Dc_args="$hard_cflags" -Dc_link_args="$hard_ldflags"
ninja -C dav1d-build install
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"

# shellcheck disable=SC2086
exec "$src/configure" \
	--disable-everything \
	--disable-autodetect \
	--disable-programs --disable-doc \
	--disable-network --disable-protocols --disable-devices --disable-indevs --disable-outdevs \
	--disable-avdevice --disable-avfilter --disable-filters \
	--disable-encoders --disable-muxers --disable-hwaccels \
	--disable-debug \
	--enable-shared --disable-static --enable-pic \
	--extra-cflags="$hard_cflags" --extra-ldflags="$hard_ldflags" \
	--enable-libdav1d --pkg-config=pkg-config --pkg-config-flags=--static \
	$cross $enable "$@"
