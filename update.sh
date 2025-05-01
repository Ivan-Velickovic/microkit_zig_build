#!/bin/bash

# This is just a small little script for me to easily update the build.zig.zon
# file without having to manually edit it for every new Microkit SDK release.

set -e

VERSION="$1"
[[ -z $VERSION ]] && echo "usage: update.sh <MICROKIT SDK VERSION>" && exit 1

URL="https://github.com/seL4/microkit/releases/download"

zig fetch --save=microkit_linux_x86_64 "$URL/$VERSION/microkit-sdk-$VERSION-linux-x86-64.tar.gz"
zig fetch --save=microkit_linux_aarch64 "$URL/$VERSION/microkit-sdk-$VERSION-linux-aarch64.tar.gz"
zig fetch --save=microkit_macos_x86_64 "$URL/$VERSION/microkit-sdk-$VERSION-macos-x86-64.tar.gz"
zig fetch --save=microkit_macos_aarch64 "$URL/$VERSION/microkit-sdk-$VERSION-macos-aarch64.tar.gz"
