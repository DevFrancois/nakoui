#!/bin/sh
# Compile the production shader for iOS and run GPU correctness checks on macOS.
# This launches neither the app nor a simulator, and does not measure UI FPS.
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$test_dir/../.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tab-bar-optics.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

xcrun -sdk iphoneos metal -c "$repo_dir/XStyle_TabBar/TabBar/TabBarOptics.metal" -o "$temp_dir/TabBarOptics-iOS.air"
xcrun -sdk macosx metal -c "$repo_dir/XStyle_TabBar/TabBar/TabBarOptics.metal" -o "$temp_dir/TabBarOptics-macOS.air"
xcrun -sdk macosx metallib "$temp_dir/TabBarOptics-macOS.air" -o "$temp_dir/TabBarOptics-macOS.metallib"
cp "$test_dir/TabBarOpticsGPUChecks.swift" "$temp_dir/main.swift"
xcrun -sdk macosx swiftc -O "$repo_dir/XStyle_TabBar/TabBar/TabBarReflectionSettings.swift" "$temp_dir/main.swift" -o "$temp_dir/checks"
"$temp_dir/checks" "$temp_dir/TabBarOptics-macOS.metallib"
