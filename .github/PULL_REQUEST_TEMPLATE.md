## What & why

<!-- Describe the change and the motivation. -->

## Checklist

- [ ] Core suite / relevant tests pass locally (`pwsh tests/run_all.ps1` or a targeted run)
- [ ] `pwsh tests/check_core_boundary.ps1` passes (no `MVCFramework.*` in `sources/`)
- [ ] `pwsh scripts/check_spdx.ps1` passes (SPDX header on new production sources)
- [ ] No stdout pollution (logging goes to `bin/logs/`)
- [ ] Docs updated (README / CLAUDE.md / docs) if behavior changed
- [ ] Conventional Commit messages
