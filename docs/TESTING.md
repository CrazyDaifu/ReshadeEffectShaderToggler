# Testing

## Confirmed configuration

- Battlefield 2 (2005)
- ReShade 6.3.7 with full add-on support
- Native Direct3D 9, 32-bit `d3d9.dll`
- 1600x900 windowed test shown in the diagnostic log
- REST group and ReShade effects enabled

## Confirmed results

| Case | Result |
| --- | --- |
| Fullscreen menu and gameplay | Pass; upstream behavior remains normal |
| Windowed main menu | Pass; ReShade effects visible |
| Windowed map load and gameplay | Pass; effects remain visible with REST enabled |
| REST disabled | Pass; ordinary ReShade path remains normal |
| Screenshot versus visible output | Pass; both show the same processed image |
| dgVoodoo2 D3D11 translation | Not a supported workaround; rendering and memory issues |

## Release regression checklist

Before promoting the candidate to a final tag, test:

- cold start into menu, map load, spawn, death, and respawn;
- repeated server/map changes;
- windowed to fullscreen and fullscreen to windowed transitions;
- resolution changes that force D3D9 Reset;
- at least three Alt+Tab cycles in menu and in gameplay;
- ReShade performance mode enabled and disabled;
- REST group toggling and effect reassignment;
- screenshots in menu and gameplay;
- optional DXVK and dgVoodoo2 startup only as compatibility information, not as the
  native D3D9 acceptance path.

For failures, preserve `ReShade.log`, the add-on SHA-256, ReShade version, resolution,
window mode, GPU driver, and exact transition sequence.
