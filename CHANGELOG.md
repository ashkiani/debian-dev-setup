# Changelog

All notable changes to this project are documented in this file.

## 2.0.1

### Added

- Resumable offline-first setup in `vm-setup-v2.sh`.
- Safe hostname changes with automatic backups.
- New-user creation, sudo-group configuration, and post-login sudo validation.
- Ed25519, ECDSA P-521, and RSA 4096 SSH key options.
- Service, running-unit, and listening-socket reports.
- Explicit confirmation before disabling or stopping services.
- Desktop-aware lock and sleep configuration.
- NetworkManager disable and re-enable support with a manual hypervisor-adapter path.
- Apt simulations and package-removal confirmation before `full-upgrade` and `autoremove`.
- Modular package profiles and external configuration support.
- VS Code installation through Microsoft's apt repository or official x64 `.deb` redirect.
- Optional UFW, persistent journald, auditd, ClamAV, SSH audit, and AppArmor reporting.
- Read-only system baseline reports.
- Automated syntax, behavior, and compatibility checks.

### Changed

- Updated public documentation for the full offline-first workflow.
- Corrected the original README reference to the developer-tool script filename.
- Moved maintainer test details to `TESTING.md`.
- Renamed implementation constants to describe their current purpose rather than repository history.

### Compatibility

- `bootstrap-system.sh` retains its original contents and behavior.
- `debian-dev-setup.sh` retains its original contents and behavior.
