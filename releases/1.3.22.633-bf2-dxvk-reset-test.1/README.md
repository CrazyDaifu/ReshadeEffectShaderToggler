# BF2 DXVK Reset fix 1

This is a verified x86 candidate for Battlefield 2 with the chain:

```text
ReShade 6.7.3 d3d9.dll -> DXVK d3d9_dxvk.dll -> Vulkan
```

It preserves the confirmed native D3D9 windowed-surface fix and changes only REST
resource lifetime handling around D3D9 device resets:

- release REST device resources before the native D3D9 Reset;
- release preview render targets that were previously skipped;
- destroy resource views before their resources;
- invalidate group resource caches so they are recreated after a successful Reset.

Local smoke status: passed with ReShade 6.7.3 x86 and DXVK 2.5.3. A synthetic D3D9
application created a device, presented frames, changed the back-buffer size, reset the
device, and presented again. Reset returned `D3D_OK`; the runtime was recreated and the
log contained no `Reset failed` entry.

Runtime status: passed on a previously failing Battlefield 2 installation with ReShade
6.7.3 x86. Its startup Reset changed the back buffer from 800x600 to 1920x1080. REST
logged `Released REST D3D9 resources before runtime reset`, ReShade recreated the
runtime, WeaponDepthMerge selected a new 1920x1080 INTZ depth buffer, and the complete
log contained no `Reset failed` entry.

An A/B smoke test on the same machine, executable, ReShade and DXVK installation also
confirmed the fix. The previous REST binary returned `D3DERR_INVALIDCALL`, with DXVK
reporting two remaining losable resources. This binary returned `D3D_OK`.

The shutdown-only `was not unregistered` and final D3D9 reference-count warnings also
occur with the previous binary, so they are not regressions from this fix.
