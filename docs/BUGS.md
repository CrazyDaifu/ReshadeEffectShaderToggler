# Bug history

## REST-BF2-002: DXVK startup Reset fails with D3DERR_INVALIDCALL

- Upstream baseline: `1.3.22.633`
- Fixed candidate: `1.3.22.633-bf2-dxvk-reset-test.1`
- Environment: Battlefield 2, ReShade 6.7.3 x86, D3D9 proxy to DXVK
- Runtime confirmation: passed on a previously failing installation

### Symptom

With REST installed, BF2 created its initial 800x600 D3D9 device but could not complete
the startup Reset to the configured resolution. ReShade repeatedly logged
`D3DERR_INVALIDCALL`. Removing REST allowed the game and WeaponDepthMerge to start.

### Evidence

ReShade invokes `destroy_effect_runtime`, `destroy_swapchain` and `destroy_device`
before the native D3D9 Reset. REST retained reset-sensitive resources too long and also
skipped preview cleanup because `OnDestroyDevice` called `DisposePreview(nullptr)`.

An automated A/B test used the same x86 D3D9 application, ReShade 6.7.3 and DXVK
2.5.3. The previous REST binary failed Reset, and DXVK reported:

```text
Device reset failed because device still has alive losable resources.
Remaining resources: 2
```

The fixed binary returned `D3D_OK`. A previously failing BF2 installation then
successfully reset from 800x600 to 1920x1080, recreated the ReShade runtime and selected
a new WeaponDepthMerge INTZ buffer without any `Reset failed` entry.

### Final fix

- Release REST-owned D3D9 resources from the last runtime before native Reset.
- Release preview targets from `OnDestroyDevice` using the valid device.
- Destroy resource views before their backing resources.
- Drop cached group views and mark owned group resources for recreation.
- Keep the native D3D9 `resource_type::surface` compatibility fix unchanged.

### Residual observations

ReShade may log addon-unregistration and D3D9 reference-count warnings during final
process shutdown. The same warnings reproduce with the previous REST binary, after its
Reset failure, so they are tracked as an existing shutdown-order issue rather than a
regression in this fix.

## REST-BF2-001: All effects disappear in native D3D9 windowed gameplay

- Upstream baseline: `1.3.22.633`
- Fixed candidate: `1.3.22.633-bf2-windowed.1`
- Environment: Battlefield 2 (2005), ReShade 6.3.7, x86 D3D9
- Runtime confirmation: passed by the project owner

### Symptom

REST and ReShade worked in the main menu and in fullscreen gameplay. In windowed mode,
entering a map while an active REST group was configured removed all ReShade effects
and showed only the original game image. Disabling REST or unchecking the configured
REST effects restored normal ReShade output. The shader hunting list was empty in the
map. Screenshots matched the visible output.

### Evidence

The diagnostic build logged:

```text
REST D3D9 fallback could not create a view for the presented back buffer
```

ReShade's D3D9 backend returns the swap-chain back buffer as a
`resource_type::surface`. Upstream `GlobalResourceView` accepted only
`resource_type::texture_2d`, so it never attempted RTV creation for that back buffer.

### Final fix

Accept `resource_type::surface` in the existing resource-view eligibility predicate.
No render scheduling, pipeline observation, or Reset handling changes are required.

### Rejected candidates

- Passing the presented swapchain explicitly to `RenderRemainingEffects`.
- Rendering all enabled techniques at Present when no shader bind was observed.
- Recreating invalid cached views immediately after Reset.
- Calling `render_effects` with zero RTV handles as an automatic-target fallback.
- Using dgVoodoo2 D3D11 translation as the production workaround; it introduced
  rendering bugs and unacceptable memory pressure in a 32-bit game.

### Residual risk

Other D3D9 render-target surfaces can now use the same cache path. This is consistent
with the ReShade API contract. The existing usage checks and cache cleanup still apply.
