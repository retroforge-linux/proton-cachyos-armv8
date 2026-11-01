#!/bin/bash
# Build Proton-CachyOS's arm64 Proton for arm64 CPUs without LSE atomics (ARMv8.0).
#
#   build.sh <tag> <workdir>    a Proton-CachyOS release tag, e.g. cachyos-11.0-20261015-slr
#
# Produces <workdir>/proton-<tag>-armv8.tar.zst with .sha256 and .sha512 next to it.
# Needs git, make, zstd, python3, llvm-objdump and a container engine (CONTAINER_ENGINE, default docker).
#
# The build is CachyOS's own arm64 one (its release.yml: configure.sh --target-arch=arm64
# --without-nvidia-libs, then make redist), except that Makefile.in's arm64 targets drop from
# -march=armv8.2-a to -march=armv8-a (C and Rust) and FEX is tuned for a generic CPU. Each of those
# edits must hit exactly the lines expected: when CachyOS changes them, the build stops here instead
# of shipping a build that still has LSE. The LSE scan at the end is the release gate either way.
set -euo pipefail

TAG=${1:?usage: build.sh <tag> <workdir>}
WORK=${2:?usage: build.sh <tag> <workdir>}
HERE=$(cd "$(dirname "$0")/.." && pwd)
REPO=https://github.com/CachyOS/proton-cachyos.git
NAME=proton-$TAG-armv8
DISPLAY="Proton-CachyOS ${TAG#cachyos-} (ARMv8.0)"

edit() {  # edit <file> <expected count> <sed expression>: the expression must change that many lines
    local file=$1 want=$2 expr=$3 before
    before=$(cat "$file")
    sed -i "$expr" "$file"
    local got
    got=$(diff <(printf '%s\n' "$before") "$file" | grep -c '^>' || true)
    if [ "$got" != "$want" ]; then
        echo "build.sh: '$expr' changed $got line(s) of $file, expected $want: refresh build.sh for $TAG" >&2
        exit 1
    fi
}

mkdir -p "$WORK"
cd "$WORK"

if [ ! -d proton ]; then
    git clone --branch "$TAG" --filter=tree:0 "$REPO" proton
    git -C proton submodule update --init --recursive --filter=tree:0 --jobs 8
    edit proton/Makefile.in 2 's/^\(aarch64\|arm64ec\)_CFLAGS \(:\?=\) -O2 -march=armv8\.2-a -mtune=cortex-x3$/\1_CFLAGS \2 -O2 -march=armv8-a/'
    edit proton/Makefile.in 2 's/^\(aarch64\|arm64ec\)_RUSTFLAGS \(:\?=\) \(.*\)-Ctarget-cpu=armv8\.2-a$/\1_RUSTFLAGS \2 \3-Ctarget-cpu=generic/'
    edit proton/Makefile.in 1 's/-DTUNE_CPU=none /-DTUNE_CPU=generic /'
fi
if grep -n 'armv8\.[1-9]\|cortex-x' proton/Makefile.in proton/extras/*.mk; then
    echo "build.sh: Makefile rules above still target ARMv8.1+: refresh build.sh for $TAG" >&2
    exit 1
fi

mkdir -p build
cd build
USE_LTO=0 ../proton/configure.sh --build-name="$NAME" --target-arch=arm64 --without-nvidia-libs \
    --container-engine="${CONTAINER_ENGINE:-docker}" --enable-ccache
make redist
# CachyOS's redist renames redist/ to the build's name and tars it as .tar.xz: ours is .tar.zst.
rm -f "$NAME.tar.xz" "$NAME.sha512sum"
sed -i "s|\"display_name\" \"$NAME\"|\"display_name\" \"$DISPLAY\"|" "$NAME/compatibilitytool.vdf"

python3 "$HERE/scripts/scan-lse.py" --objdump "${OBJDUMP:-llvm-objdump}" --allow "$HERE/scan-allow.txt" \
    "$NAME/files" "$NAME/protonfixes"

cd "$WORK"
tar -C "build/$NAME" --transform "s|^\./|$NAME/|" -cf - . | zstd -19 -T0 -o "$NAME.tar.zst"
sha256sum "$NAME.tar.zst" > "$NAME.tar.zst.sha256"
sha512sum "$NAME.tar.zst" > "$NAME.tar.zst.sha512"
echo "built $WORK/$NAME.tar.zst"
