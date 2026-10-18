#!/bin/sh
# Run the production capture traversal against native Core Animation fixtures.
# No app or simulator is launched. The Swift harness documents its UIKit stubs.
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$test_dir/../.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tab-bar-layer-capture.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Keep the implementation exact; substitute only UIKit's module import because
# the native harness supplies its minimal UIView/UIWindow/trait definitions.
awk '{ if ($0 == "import UIKit") { print "import Foundation"; print "import CoreGraphics" } else print }' \
    "$repo_dir/XStyle_TabBar/TabBar/TabBarLayerRegionRenderer.swift" > "$temp_dir/TabBarLayerRegionRenderer.swift"
xcrun -sdk macosx swiftc -O -parse-as-library \
    "$repo_dir/XStyle_TabBar/TabBar/TabBarPreparedImageCache.swift" \
    "$temp_dir/TabBarLayerRegionRenderer.swift" "$test_dir/TabBarLayerCaptureChecks.swift" \
    -o "$temp_dir/checks"
xcrun -sdk macosx swiftc -O -parse-as-library \
    "$repo_dir/XStyle_TabBar/TabBar/TabBarPreparedImageCache.swift" \
    "$test_dir/TabBarPreparedImageCacheChecks.swift" -o "$temp_dir/cache-checks"
"$temp_dir/cache-checks"
"$temp_dir/checks"
