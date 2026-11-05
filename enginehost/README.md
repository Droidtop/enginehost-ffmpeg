# Enginehost's FFmpeg

This repository is FFmpeg with Enginehost's build on top (Droidtop/tracker#906). The
branch `upstream-sync` is FFmpeg's own history, untouched. Enginehost's work lives on a
branch based on an FFmpeg release tag and is brought up to each security release by
merging the next tag, so nothing is ever rewritten.

Droidtop builds its own copy from the same branch for Wine games.

## What is here

| file | what it does |
|---|---|
| `components.txt` | the allow-list: the only decoders, demuxers, parsers and bitstream filters compiled in |
| `configure.sh` | runs FFmpeg's configure for the host or one Android ABI: LGPL only, `--disable-everything` plus the allow-list, no protocols, network, devices, filters, encoders, muxers or programs, and the hardening flags |
| `check.sh` | fails the build if the configuration or the built libraries break any of that |
| `../.github/workflows/enginehost.yml` | builds and checks the host, arm64-v8a and x86_64 |

## Decisions

- **LGPL only.** No `--enable-gpl`, `--enable-nonfree` or `--enable-version3`. `check.sh` refuses a build that has them.
- **Allow-list.** Everything starts off. A component is on only when `components.txt` names it, and `check.sh` refuses a build whose enabled decoders, demuxers, parsers or bitstream filters differ from the list in either direction. Components configure turns on as dependencies of listed ones (h263 for msmpeg4 and wmv, vp3 for theora) are listed too, so the list says what ships.
- **H.264, HEVC and AAC are in.** The owner, 2026-11-05: "include everything".
- **No protocols at all**, not even `file`: the service reads input through its own `AVIOContext` over a descriptor the host hands it. No network, devices or filters.
- **Hardening:** `-fstack-protector-strong`, `-D_FORTIFY_SOURCE=2`, PIC, full RELRO with `-z now`, no executable stack, no text relocations. `check.sh libs` asserts each of these on every built library.
- **Toolchain:** NDK r27c (27.2.12479018), API 28, arm64-v8a and x86_64.

## Not here yet

- AV1 in software through libdav1d (BSD), built as a dependency.
- The MediaCodec hardware path.
- The sandboxed service and its plugin-api glue.
- Fuzzing with FFmpeg's own targets against this same configuration.
