# Contributing

Read `_项目移交.md` before changing the implementation.

Keep the runtime patch narrowly scoped and preserve upstream behavior on non-D3D9
APIs. Build with `scripts/build-release.ps1`, verify with
`scripts/verify-binary.ps1`, and document target-game runtime results in
`docs/TESTING.md`.

Dependency updates must include a fixed commit in `SOURCES.md` and the corresponding
license. Do not reintroduce floating Git submodules or build-time downloads.
