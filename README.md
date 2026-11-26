# proton-cachyos-armv8

[Proton-CachyOS](https://github.com/CachyOS/proton-cachyos)'s arm64 build for arm64 CPUs **without LSE
atomics** (ARMv8.0: Cortex-A53/A57/A72/A73, e.g. Snapdragon 662 / SM6115).

CachyOS builds its arm64 Proton with `-march=armv8.2-a -mtune=cortex-x3`, so on these CPUs its Wine, DXVK and
FEX components fault on the first atomic instruction, or run only through slow kernel emulation. These builds
are CachyOS's own arm64 build (its `release.yml`: `configure.sh --target-arch=arm64 --without-nvidia-libs`,
`make redist`) with the arm64 targets at `-march=armv8-a` (C) and `-Ctarget-cpu=generic` (Rust), and FEX
tuned for a generic CPU, plus the patches below. Everything else is CachyOS's: DXVK-Sarek
(`PROTON_DXVK_SAREK=1`), umu and umu-protonfixes, so it also runs games without the Steam client
(`UMU_ID`), as umu-run does.

## Patches

`patches/<folder>/*.patch` go into that folder of CachyOS's checkout (a submodule) as commits, in name
order, before the build. One that no longer applies stops the build.

- `extras/dxvk-sarek/0001`: DXVK-Sarek's DXGI makes swap chains for vkd3d-proton. Sarek's DXGI took only
  devices offering Wine's `IWineDXGISwapChainFactory`, which vkd3d-proton dropped in 2.8 for DXVK 2.x's
  `IDXGIVkSwapChainFactory`, so with Sarek on (the Adreno 610/613, whose missing multiViewport rules out
  upstream DXVK) every D3D12 game failed creating its swap chain with `DXGI_ERROR_UNSUPPORTED`. D3D10/11
  swap chains take the same path as before.
- `extras/dxvk-sarek/0002`: typeless RGBA8 and RGB10A2 textures get only their UNORM (and sRGB) view formats,
  so Turnip keeps them UBWC-compressed on the Adreno 6xx, whose UBWC cannot be read through UINT, SINT or
  SNORM views (Hollow Knight on the A610: 51.3 -> 47.4 ms GPU per frame). A view outside that list before
  the texture's first use rebuilds it with the whole family; a later one logs a warning, and
  `DXVK_CONFIG="d3d11.narrowTypelessFormats = False"` turns it off for a game.

## Releases

CI (`.github/workflows/sync.yml`, daily) builds Proton-CachyOS's newest `cachyos-<version>-<date>-slr`
release on GitHub's arm64 runners and publishes it with `proton-<tag>-armv8.tar.zst` and its `.sha256` and
`.sha512`, as `<tag>-armv8`, or `<tag>-armv8-r<n>` from the recipe's revision 2 on (`revision`,
`scripts/release-tag.sh`). Raising `revision` after a change to `patches/` or `scripts/build.sh` releases
the newest tag again; installers that take the newest release by Proton version and then date pick it up.

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
make, curl, zstd, python3 and llvm-objdump.

Proton's speech synthesis (piper) needs onnxruntime 1.14.1, which piper-phonemize downloaded from
`microsoft/onnxruntime` on GitHub until that repository went away (2026-11). `build.sh` now takes the same
build from Microsoft's NuGet package (`Microsoft.ML.OnnxRuntime`, SHA-256 checked) and puts it where
piper-phonemize looks before downloading.

## Credits

Proton-CachyOS is © CachyOS and Valve, and Proton's component authors, under their own licenses. The ARMv8.0
approach and `scripts/scan-lse.py` come from
[sunshineinabox/proton-armv8](https://github.com/sunshineinabox/proton-armv8), after
[Azkali/proton-arm64-a57](https://github.com/Azkali/proton-arm64-a57). Built for
[RetroForge](https://github.com/retroforge-linux).
