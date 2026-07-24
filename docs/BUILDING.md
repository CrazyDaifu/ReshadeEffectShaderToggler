# Building

The repository vendors all source dependencies under `deps/`; no network download or
submodule initialization is required.

## Supported targets

- Primary verified target: Release / x86 (`ReshadeEffectShaderToggler.addon32`)
- Local verified toolchain: Visual Studio Community 2026, MSVC 14.51 / `v145`
- Local verified SDK: Windows SDK `10.0.19041.0`
- GitHub Actions: the upstream workflows are retained unchanged

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-release.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-binary.ps1
```

The build script discovers Visual Studio with `vswhere.exe`, chooses the matching
toolset, rebuilds the upstream solution, and copies the result to
`build/ReshadeEffectShaderToggler.addon32`.

Optional overrides:

```powershell
.\scripts\build-release.ps1 `
  -MsBuildPath 'C:\path\to\MSBuild.exe' `
  -PlatformToolset v145 `
  -WindowsSdkVersion 10.0.19041.0
```

The Windows file version remains the numeric upstream base `1.3.22.633`; the fork
candidate suffix is tracked by `VERSION`, Git, the release archive, and checksums.
