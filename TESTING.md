# Testing

The repository includes automated checks for script syntax, reusable behavior, and compatibility with the original entry points.

## Run the complete test suite

From the repository root:

```bash
./tests/run-tests.sh
```

The automated tests do not modify system accounts, networking, services, apt configuration, or installed packages.

## Test files

### `tests/run-tests.sh`

This is the test-suite entry point. It performs Bash syntax validation and then runs the behavior and compatibility test scripts.

### `tests/test-vm-setup-v2.sh`

This script sources `vm-setup-v2.sh` without executing its command dispatcher and tests reusable functions with temporary files and controlled input.

It currently checks:

- hostname validation;
- username validation;
- apt package-name validation;
- systemd service-unit validation;
- transitional and final `/etc/hosts` rewriting;
- preservation of comments and unrelated aliases;
- protection of localhost aliases;
- case-insensitive removal of the previous hostname;
- interactive menu selection; and
- package-array de-duplication.

### `tests/test-legacy-checksums.sh`

This script verifies the SHA-256 checksums of `bootstrap-system.sh` and `debian-dev-setup.sh`. Its purpose is to prevent an unrelated update to the new workflow from silently changing the behavior of the existing public entry points.

Update the expected checksums only when a deliberate change is made to one of those scripts.

## Manual system test procedure

System-level operations require a disposable VM or a VM snapshot because they cannot be validated safely by the non-destructive test suite.

Test the following scenarios on each supported distribution and desktop environment used by the project:

1. Start with the hypervisor network adapter disconnected.
2. Start while connected and allow the script to disable NetworkManager networking.
3. Change the hostname and confirm that sudo continues to work.
4. Create a new account, log out, log in with the new account, and run `continue`.
5. Exercise each original-account option: unchanged, password-locked, and fully disabled.
6. Confirm the printed recovery commands restore the original account from another sudo account or root console.
7. Generate each supported SSH key type and confirm that existing keys are not overwritten.
8. Save a service report and confirm that only explicitly approved services are disabled.
9. Verify the desktop lock and sleep path for GNOME, Xfce, KDE Plasma, or a headless session.
10. Reconnect networking and confirm HTTPS connectivity before apt operations begin.
11. Review the `full-upgrade` and `autoremove` simulations and confirm that removal prompts behave correctly.
12. Install each package profile independently.
13. Install VS Code through the apt repository and, on `amd64`, through the direct `.deb` option.
14. Exercise UFW from both a local console and an SSH session.
15. Generate a baseline report and inspect its permissions and contents.
16. Run `start`, `continue`, and optional commands a second time to check repeatability.

Restore the VM snapshot between scenarios that modify accounts, networking, firewall rules, or package state.
