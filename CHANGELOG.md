# Changelog

## 1.3.22.633-bf2-windowed.1 - 2026-07-24

- Added support for ReShade API `resource_type::surface` in `GlobalResourceView`.
- Fixed REST suppressing all ReShade effects after Battlefield 2 entered a map in
  native D3D9 windowed mode.
- Preserved the original REST rendering path; discarded experimental Present fallback,
  shader-binding observation, and cache-recreation changes.
- Vendored the exact dependencies used by the verified x86 build.
- Added deterministic local build, binary verification, release packaging, GitHub
  Actions, and true-fork publishing scripts.

Runtime status: confirmed working by the project owner in Battlefield 2 with ReShade
6.3.7, native 32-bit D3D9, fullscreen and windowed gameplay.

## Upstream baseline

- Upstream REST version: `1.3.22.633`
- Upstream commit: `6d63c9d1dfd3ab47d7ab1512ecb8111d2aa461a6`
