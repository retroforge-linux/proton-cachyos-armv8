# proton-cachyos-armv8

[Proton-CachyOS](https://github.com/CachyOS/proton-cachyos)'s arm64 build for arm64 CPUs **without LSE
atomics** (ARMv8.0: Cortex-A53/A57/A72/A73, e.g. Snapdragon 662 / SM6115).

CachyOS builds its arm64 Proton with `-march=armv8.2-a -mtune=cortex-x3`, so on these CPUs its Wine, DXVK and
FEX components fault on the first atomic instruction, or run only through slow kernel emulation. These builds
are CachyOS's own arm64 build (its `release.yml`: `configure.sh --target-arch=arm64 --without-nvidia-libs`,
`make redist`) with the arm64 targets at `-march=armv8-a` (C) and `-Ctarget-cpu=generic` (Rust), and FEX
tuned for a generic CPU. Everything else is CachyOS's: DXVK-Sarek (`PROTON_DXVK_SAREK=1`), umu and
umu-protonfixes, so it also runs games without the Steam client (`UMU_ID`), as umu-run does.

## Releases

CI (`.github/workflows/sync.yml`, daily) builds Proton-CachyOS's newest `cachyos-<version>-<date>-slr`
release on GitHub's arm64 runners and publishes it as `<tag>-armv8`, with `proton-<tag>-armv8.tar.zst` and
its `.sha256` and `.sha512`.

A release is published only when every native arm64 binary passes `scripts/scan-lse.py`: no LSE/RCpc
instruction outside the compiler's runtime-checked outline-atomics helpers. Exceptions go in
`scan-allow.txt`. When CachyOS changes the Makefile lines the build edits, `scripts/build.sh` stops and the
workflow opens an issue, rather than building something that still has LSE.

## Install

```sh
mkdir -p ~/.steam/root/compatibilitytools.d
tar -C ~/.steam/root/compatibilitytools.d --zstd -xf proton-<tag>-armv8.tar.zst
```

Restart Steam and pick "Proton-CachyOS … (ARMv8.0)" per game or as the default.

## Build locally

`scripts/build.sh <tag> <workdir>` on an arm64 Linux host with docker (or `CONTAINER_ENGINE=podman`), git,
make, zstd, python3 and llvm-objdump.

## Credits

Proton-CachyOS is © CachyOS and Valve, and Proton's component authors, under their own licenses. The ARMv8.0
approach and `scripts/scan-lse.py` come from
[sunshineinabox/proton-armv8](https://github.com/sunshineinabox/proton-armv8), after
[Azkali/proton-arm64-a57](https://github.com/Azkali/proton-arm64-a57). Built for
[RetroForge](https://github.com/retroforge-linux).
