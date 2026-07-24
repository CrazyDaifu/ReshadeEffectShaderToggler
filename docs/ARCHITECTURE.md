# Architecture of the fix

REST renders selected techniques during the game's frame, then renders any remaining
enabled techniques to the ReShade back buffer before Present. `GlobalResourceView`
creates and caches the resource views used by both paths.

On D3D10 and newer APIs, swap-chain back buffers are represented as `texture_2d`.
ReShade's D3D9 backend represents an `IDirect3DSurface9` back buffer as
`resource_type::surface`. The upstream REST filter rejected that type before calling
`device::create_resource_view`, leaving both cached RTV handles at zero.

The fork changes only the resource-type predicate:

```cpp
desc.type == resource_type::texture_2d ||
desc.type == resource_type::surface
```

The existing usage checks still require a render target or shader resource. View
creation, AddRef/Release behavior, cache eviction, technique ordering, and all
non-D3D9 paths remain unchanged.

## Why the symptom was a fully unprocessed frame

REST calls ReShade's effect API while scheduling techniques. ReShade therefore marks
the frame as handled and does not repeat the normal full effect pass at Present. When
REST later failed to obtain an RTV for the D3D9 surface, it could not render remaining
techniques either, so the game back buffer was presented without ReShade effects.

## Scope

The `surface` resource type is intended for resources that are implicitly both a
resource and view, notably D3D9 surfaces. Other graphics APIs do not normally emit this
type, so the compatibility expansion is isolated without an explicit API branch.
