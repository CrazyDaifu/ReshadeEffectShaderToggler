# Bug history

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
