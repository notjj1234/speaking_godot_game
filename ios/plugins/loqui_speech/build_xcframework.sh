#!/bin/bash
# Build LoquiSpeechIOS debug and release xcframeworks against Godot 4.7.1 headers.
# Headers come from a local Godot source tree. SCons is started only long enough
# to generate them; the engine itself is not compiled.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
GODOT_SRC="${GODOT_SRC:-$HOME/Library/Caches/loqui-godot/godot-4.7.1-stable}"
TAG="4.7.1-stable"
JOBS="$(sysctl -n hw.ncpu)"

if [[ ! -f "$GODOT_SRC/SConstruct" ]]; then
	mkdir -p "$(dirname "$GODOT_SRC")"
	archive="$(dirname "$GODOT_SRC")/godot-${TAG}.tar.gz"
	echo "Downloading Godot ${TAG} source..."
	curl -L --fail "https://github.com/godotengine/godot/archive/refs/tags/${TAG}.tar.gz" -o "$archive"
	tar -xzf "$archive" -C "$(dirname "$GODOT_SRC")"
fi

export PATH="$HOME/Library/Python/3.13/bin:$HOME/Library/Python/3.12/bin:$PATH"
if ! command -v scons >/dev/null 2>&1; then
	python3 -m pip install --user "scons>=4.0"
fi

generate_headers() {
	if [[ -f "$GODOT_SRC/core/version_generated.gen.h" ]]; then
		return
	fi
	echo "Generating Godot headers..."
	local log="$GODOT_SRC/header_gen.log"
	(
		cd "$GODOT_SRC"
		scons platform=ios arch=arm64 target=template_debug simulator=no -j"$JOBS"
	) >"$log" 2>&1 &
	local spid=$!
	local i
	for i in $(seq 1 240); do
		if grep -q "Compiling" "$log" 2>/dev/null && [[ -f "$GODOT_SRC/core/version_generated.gen.h" ]]; then
			sleep 15
			kill "$spid" 2>/dev/null || true
			wait "$spid" 2>/dev/null || true
			return
		fi
		if ! kill -0 "$spid" 2>/dev/null; then
			wait "$spid" 2>/dev/null || true
			return
		fi
		sleep 2
	done
	kill "$spid" 2>/dev/null || true
	echo "Header generation timed out. See $log" >&2
	exit 1
}

compile_one() {
	local sdk="$1"
	local min_flag="$2"
	local extra_defs="$3"
	local out="$4"
	local sdk_path
	sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
	local obj="${out}.o"
	rm -f "$obj" "$out"
	xcrun --sdk "$sdk" clang++ -std=gnu++17 -fno-exceptions -fno-rtti -fobjc-arc \
		-arch arm64 "$min_flag" -isysroot "$sdk_path" \
		-fvisibility=hidden -O2 -fPIC \
		-I"$GODOT_SRC" -I"$GODOT_SRC/platform/ios" \
		$extra_defs \
		-c "$SRC/loqui_speech.mm" -o "$obj"
	xcrun --sdk "$sdk" ar rcs "$out" "$obj"
	rm -f "$obj"
}

generate_headers

BUILD="$ROOT/build"
rm -rf "$BUILD"
mkdir -p "$BUILD"

COMMON="-DIOS_ENABLED -DAPPLE_EMBEDDED_ENABLED -DUNIX_ENABLED -DCOREAUDIO_ENABLED"
DEVICE="$COMMON -DMETAL_ENABLED -DRD_ENABLED"
SIM="$COMMON -DIOS_SIMULATOR"

compile_one iphoneos -miphoneos-version-min=14.0 "$DEVICE -DDEBUG_ENABLED" "$BUILD/device-debug.a"
compile_one iphonesimulator -mios-simulator-version-min=14.0 "$SIM -DDEBUG_ENABLED" "$BUILD/sim-debug.a"
compile_one iphoneos -miphoneos-version-min=14.0 "$DEVICE -DNDEBUG" "$BUILD/device-release.a"
compile_one iphonesimulator -mios-simulator-version-min=14.0 "$SIM -DNDEBUG" "$BUILD/sim-release.a"

rm -rf "$ROOT/LoquiSpeechIOS.debug.xcframework" "$ROOT/LoquiSpeechIOS.release.xcframework"
xcodebuild -create-xcframework \
	-library "$BUILD/device-debug.a" \
	-library "$BUILD/sim-debug.a" \
	-output "$ROOT/LoquiSpeechIOS.debug.xcframework"
xcodebuild -create-xcframework \
	-library "$BUILD/device-release.a" \
	-library "$BUILD/sim-release.a" \
	-output "$ROOT/LoquiSpeechIOS.release.xcframework"

echo "Built $ROOT/LoquiSpeechIOS.debug.xcframework"
echo "Built $ROOT/LoquiSpeechIOS.release.xcframework"
