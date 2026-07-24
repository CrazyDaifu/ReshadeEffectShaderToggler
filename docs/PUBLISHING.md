# Publishing this fork

The repository is designed to be published as a real GitHub fork of
`4lex4nder/ReshadeEffectShaderToggler`.

## One-click candidate upload

Double-click `publish-to-github.cmd`. The script:

1. verifies Git and GitHub CLI authentication;
2. rebuilds the x86 Release add-on from vendored sources;
3. verifies PE32 architecture and `NAME`/`DESCRIPTION` exports;
4. updates `build/` and the matching `releases/<VERSION>/` archive;
5. commits current changes;
6. creates or connects the authenticated user's true GitHub fork;
7. configures `upstream` and pushes the current branch.

The default operation never creates a final release tag.

## Formal release

The current `VERSION` contains a hyphen and is therefore protected as a candidate.
After completing the regression checklist, choose a numeric final version, update the
version documents, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\publish-github.ps1 `
  -PublishRelease `
  -ReleaseTag v1.3.23.673
```

The requested tag must exactly equal `v<VERSION>`. A `VERSION` containing `-` is
rejected for formal publication.

The upstream GitHub Actions workflows are retained unchanged so the normal `repo`
OAuth scope can update this fork without requiring a separate `workflow` authorization.
The one-click script performs the authoritative x86 build and binary verification locally
before every push. Upstream tag handling remains available for formal releases.
