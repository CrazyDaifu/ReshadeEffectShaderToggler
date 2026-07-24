# Source provenance

All dependencies used by the build are vendored under `deps/`. The repository does
not download dependencies during local or GitHub Actions builds.

| Component | Source | Revision | Purpose |
| --- | --- | --- | --- |
| ReshadeEffectShaderToggler | https://github.com/4lex4nder/ReshadeEffectShaderToggler | `6d63c9d1dfd3ab47d7ab1512ecb8111d2aa461a6` | Upstream fork baseline |
| ReShade | https://github.com/crosire/reshade | `9e3869585db44fda639225243f10dac299e92824` | ReShade add-on API 14 headers, source reference, ImGui 1.90.4 |
| MinHook | https://github.com/TsudaKageyu/minhook | `d94c64d32ea37bc4f5ee47d580709f70c6fb6080` | Runtime hook implementation |
| robin-map | https://github.com/Tessil/robin-map | `91362aab8f2c63ef90bf7c21fb2c3283ded5ae48` | Header-only containers |
| sigmatch | https://github.com/SpriteOvO/sigmatch | `91571520dda49903f2b7de7a1a44e2daaa27e607` | Signature matching |

The original project used Git submodules. This fork vendors the resolved working trees
so an offline checkout builds the same inputs locally and in GitHub Actions. Toolchain
components such as MSBuild, MSVC, FXC, and the Windows SDK are supplied by Visual Studio.

`rest-src.zip` outside the repository is a local upstream snapshot and is not part of
the published project.
