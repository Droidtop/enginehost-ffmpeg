#!/bin/sh
# Asserts what configure.sh promises (Droidtop/tracker#906). Run from the build
# directory after configure (the "config" checks) and again after make (the "libs"
# checks):
#
#   ../enginehost/check.sh config
#   ../enginehost/check.sh libs [readelf]
#
# Any failure prints its reason and exits 1.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
what=${1:?usage: check.sh config|libs [readelf]}
fail=0
bad() { echo "check.sh: FAIL: $*"; fail=1; }

case "$what" in
config)
	mak=ffbuild/config.mak
	hdr=config_components.h
	[ -f "$mak" ] && [ -f "$hdr" ] || { echo "check.sh: run configure first"; exit 1; }
	# LGPL only: no GPL, no nonfree, no (L)GPL version 3 upgrade.
	for flag in GPL NONFREE VERSION3; do
		grep -q "^CONFIG_$flag=yes" "$mak" && bad "CONFIG_$flag is on"
	done
	# Nothing of these kinds at all.
	for kind in PROTOCOL MUXER ENCODER FILTER INDEV OUTDEV HWACCEL; do
		n=$(grep -c "^#define CONFIG_[A-Z0-9_]*_$kind 1" "$hdr" || true)
		[ "$n" -eq 0 ] || bad "$n ${kind}s enabled: $(grep "^#define CONFIG_[A-Z0-9_]*_$kind 1" "$hdr" | head -5 | tr '\n' ' ')"
	done
	grep -q "^CONFIG_NETWORK=yes" "$mak" && bad "network support is on"
	# Exactly the allow-list for decoders, demuxers, parsers and bitstream filters.
	for kind in decoder demuxer parser bsf; do
		upper=$(echo "$kind" | tr a-z A-Z)
		want=$(awk -v k="$kind" '$1 == k { print toupper($2) }' "$here/components.txt" | sort)
		have=$(sed -n "s/^#define CONFIG_\([A-Z0-9_]*\)_$upper 1\$/\1/p" "$hdr" | sort)
		extra=$(comm -13 "/dev/fd/3" "/dev/fd/4" 3<<W 4<<H
$want
W
$have
H
)
		missing=$(comm -23 "/dev/fd/3" "/dev/fd/4" 3<<W 4<<H
$want
W
$have
H
)
		[ -z "$extra" ] || bad "${kind}s on that are not in components.txt: $(echo $extra)"
		[ -z "$missing" ] || bad "${kind}s in components.txt that configure left off: $(echo $missing)"
	done
	;;
libs)
	readelf=${2:-readelf}
	found=0
	for so in $(find . -name 'lib*.so.*' -type f); do
		found=1
		ph=$("$readelf" -lW "$so")
		dyn=$("$readelf" -dW "$so")
		echo "$ph" | grep -q GNU_RELRO || bad "$so: no RELRO segment"
		echo "$dyn" | grep -Eq 'BIND_NOW|FLAGS_1.*NOW' || bad "$so: not bound now (-z now)"
		echo "$dyn" | grep -q TEXTREL && bad "$so: has text relocations"
		echo "$ph" | grep GNU_STACK | grep -q 'RWE' && bad "$so: executable stack"
		syms=$("$readelf" -sW --dyn-syms "$so")
		echo "$syms" | grep -q '__stack_chk_fail' || bad "$so: no stack protector (__stack_chk_fail not referenced)"
		echo "$syms" | grep -q '__[a-z0-9_]*_chk' || echo "check.sh: note: $so references no fortified (_chk) call"
		echo "check.sh: $so checked"
	done
	[ "$found" -eq 1 ] || bad "no shared libraries found under $(pwd)"
	;;
*)
	echo "check.sh: unknown check $what (config or libs)"; exit 2 ;;
esac

[ "$fail" -eq 0 ] && echo "check.sh: $what OK"
exit "$fail"
