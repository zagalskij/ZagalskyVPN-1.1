#!/bin/bash
set -euo pipefail

if [[ "${ACTION:-build}" == clean ]]; then
    exit 0
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$project_dir/Vendor/AmneziaWG/Sources/WireGuardKitGo"
build_dir="${CONFIGURATION_TEMP_DIR:?Run this script from the Xcode build}/AmneziaBridge"
output_dir="${BUILT_PRODUCTS_DIR:?Run this script from the Xcode build}"
platform="${PLATFORM_NAME:?An iOS SDK is required}"
minimum_ios_version="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"

case "$platform" in
    iphoneos) deployment_flag="-miphoneos-version-min=$minimum_ios_version" ;;
    iphonesimulator) deployment_flag="-mios-simulator-version-min=$minimum_ios_version" ;;
    *) printf 'error: Unsupported AmneziaWG build platform %s\n' "$platform" >&2; exit 1 ;;
esac

export PATH="/opt/homebrew/opt/go@1.26/bin:/usr/local/opt/go@1.26/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
export GOTOOLCHAIN=local
go_binary="${ZAGALSKY_GO_BINARY:-$(command -v go || true)}"
if [[ -z "$go_binary" ]]; then
    printf 'error: Install Go 1.26.x to build the AmneziaWG bridge. See README.md.\n' >&2
    exit 1
fi

go_version="$(env -u GOROOT "$go_binary" env GOVERSION)"
if [[ "$go_version" != go1.26 && "$go_version" != go1.26.* ]]; then
    printf 'error: The AmneziaWG bridge requires Go 1.26.x. Found %s.\n' "$go_version" >&2
    exit 1
fi

clang="$(xcrun --sdk "$platform" --find clang)"
sdk_path="$(xcrun --sdk "$platform" --show-sdk-path)"
original_goroot="$(env -u GOROOT "$go_binary" env GOROOT)"
runtime_patch="$source_dir/goruntime-boottime-over-monotonic.diff"
patch_checksum="$(shasum -a 256 "$runtime_patch" | cut -d ' ' -f 1)"
export GOROOT="$build_dir/$go_version-$patch_checksum"
mkdir -p "$build_dir" "$output_dir"
temporary_dir="$(mktemp -d "$build_dir/work.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT

if [[ ! -e "$GOROOT/.amnezia-patched" ]]; then
    rsync -a --exclude=pkg/obj/go-build "$original_goroot/" "$temporary_dir/goroot/"
    patch -p1 -f -d "$temporary_dir/goroot" < "$runtime_patch"
    touch "$temporary_dir/goroot/.amnezia-patched"
    mv "$temporary_dir/goroot" "$GOROOT"
fi

read -r -a architectures <<< "${ARCHS:?No architecture selected in Xcode}"
archives=()
cd "$source_dir"
for architecture in "${architectures[@]}"; do
    case "$architecture" in
        arm64) go_architecture=arm64 ;;
        x86_64) go_architecture=amd64 ;;
        *) printf 'error: Unsupported AmneziaWG architecture %s\n' "$architecture" >&2; exit 1 ;;
    esac

    archive="$temporary_dir/libwg-go-$architecture.a"
    flags="-isysroot \"$sdk_path\" $deployment_flag -arch $architecture"
    CC="\"$clang\"" CGO_CFLAGS="$flags" CGO_LDFLAGS="$flags" CGO_ENABLED=1 \
        GOOS=ios GOARCH="$go_architecture" \
        "$go_binary" build -mod=readonly -trimpath -ldflags=-w -buildmode=c-archive -o "$archive" api-apple.go
    archives+=("$archive")
done

xcrun --sdk "$platform" lipo -create "${archives[@]}" -output "$temporary_dir/libwg-go.a"
mv -f "$temporary_dir/libwg-go.a" "$output_dir/libwg-go.a"
