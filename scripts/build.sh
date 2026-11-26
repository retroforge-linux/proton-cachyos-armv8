#!/bin/bash
# Build Proton-CachyOS's arm64 Proton for arm64 CPUs without LSE atomics (ARMv8.0).
#
#   build.sh <tag> <workdir>    a Proton-CachyOS release tag, e.g. cachyos-11.0-20261015-slr
#
# Produces <workdir>/proton-<tag>-armv8.tar.zst with .sha256 and .sha512 next to it.
# Needs git, make, curl, zstd, python3, llvm-objdump and a container engine (CONTAINER_ENGINE, default docker).
#
# The build is CachyOS's own arm64 one (its release.yml: configure.sh --target-arch=arm64
# --without-nvidia-libs, then make redist), except that Makefile.in's arm64 targets drop from
# -march=armv8.2-a to -march=armv8-a (C and Rust) and FEX is tuned for a generic CPU. Each of those
# edits must hit exactly the lines expected: when CachyOS changes them, the build stops here instead
# of shipping a build that still has LSE. The LSE scan at the end is the release gate either way.
# patches/ holds the few fixes this build adds to CachyOS's sources (README.md, Patches).
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
    # patches/<folder>/*.patch go into that folder of the checkout (a submodule) as commits, so its
    # version says it is patched. One that does not apply stops the build.
    for p in $(cd "$HERE/patches" && find . -name '*.patch' | sort); do
        p=${p#./}
        if ! GIT_COMMITTER_NAME=build.sh GIT_COMMITTER_EMAIL=build.sh@invalid \
                git -C "proton/$(dirname "$p")" am --keep-non-patch -q "$HERE/patches/$p"; then
            echo "build.sh: patches/$p does not apply to proton/$(dirname "$p"): refresh it for $TAG" >&2
            exit 1
        fi
    done
fi
shopt -s nullglob
if grep -n 'armv8\.[1-9]\|cortex-x' proton/Makefile.in proton/extras/*.mk; then
    echo "build.sh: Makefile rules above still target ARMv8.1+: refresh build.sh for $TAG" >&2
    exit 1
fi

mkdir -p build
cd build
USE_LTO=0 ../proton/configure.sh --build-name="$NAME" --target-arch=arm64 --without-nvidia-libs \
    --container-engine="${CONTAINER_ENGINE:-docker}" --enable-ccache
# piper (speech synthesis) builds piper-phonemize, which downloads onnxruntime 1.14.1 from
# github.com/microsoft/onnxruntime: gone from GitHub since 2026-11. Microsoft's NuGet package has the same
# build (its arm64 library is the one shipped on 2026-11-01, down to strip's section table); laid out as
# that release's tarball where piper-phonemize looks before downloading.
ORT=1.14.1 ORT_DL=obj-piper-aarch64/p/src/piper_phonemize_external-build/download
if [ ! -f "$ORT_DL/onnxruntime-linux-aarch64-$ORT.tgz" ]; then
    curl -fsSL --retry 3 -o onnxruntime.nupkg \
        "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/$ORT/microsoft.ml.onnxruntime.$ORT.nupkg"
    python3 - onnxruntime.nupkg "$ORT" "$ORT_DL" <<'EOF'
import hashlib, io, os, sys, tarfile, zipfile
path, version, folder = sys.argv[1:]
if hashlib.sha256(open(path, "rb").read()).hexdigest() != \
        "3a277421efce94b5f91f4a5dc8efc1add99b4c01f547279d81098ffb4fafbb6d":
    sys.exit(f"build.sh: {path} is not Microsoft.ML.OnnxRuntime {version} as checked in")
nupkg, name = zipfile.ZipFile(path), f"onnxruntime-linux-aarch64-{version}"
os.makedirs(folder, exist_ok=True)
out = os.path.join(folder, name + ".tgz")
with tarfile.open(out + ".part", "w:gz") as tar:
    def add(member, blob=None, link=None):
        info = tarfile.TarInfo(f"{name}/{member}")
        if link:
            info.type, info.linkname = tarfile.SYMTYPE, link
        else:
            info.size, info.mode = len(blob), 0o644
        tar.addfile(info, io.BytesIO(blob) if blob is not None else None)
    for f in nupkg.namelist():
        if f.startswith("build/native/include/") and f.endswith(".h"):
            add("include/" + os.path.basename(f), nupkg.read(f))
    add(f"lib/libonnxruntime.so.{version}", nupkg.read("runtimes/linux-arm64/native/libonnxruntime.so"))
    add("lib/libonnxruntime.so", link=f"libonnxruntime.so.{version}")
os.replace(out + ".part", out)
EOF
    rm onnxruntime.nupkg
fi
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
