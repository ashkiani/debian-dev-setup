# debian-dev-setup

Interactive setup scripts for Debian-derived virtual machines.

The repository includes a resumable workflow for full VM setup, plus the original lightweight bootstrap and developer-tool scripts.

## Scripts

| File | Purpose |
|---|---|
| `vm-setup-v2.sh` | Full VM setup with hostname, account, SSH, service, package, and optional security configuration |
| `bootstrap-system.sh` | Original online system bootstrap and optional user creation |
| `debian-dev-setup.sh` | Original online installer for VS Code, Git, Node.js, and npm |

## Requirements

The full workflow expects:

- a Debian-derived distribution using systemd, such as Kali Linux, Debian, Ubuntu, or Linux Mint;
- a normal login account with sudo access;
- Bash;
- local console access for account and network changes.

Do not run `vm-setup-v2.sh` directly as root or prefix it with `sudo`. The script requests elevated privileges only for operations that require them.

## Full VM setup

The setup is divided into two phases:

- `start` performs the offline system and account configuration;
- `continue` resumes after login with the new administrative account and performs online maintenance and optional software installation.

### Option A: download the script before disconnecting networking

Download the complete file before starting. Do not stream it directly into Bash because the workflow may disable networking during execution.

```bash
curl -fsSLo ~/vm-setup-v2.sh \
  https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/vm-setup-v2.sh
chmod +x ~/vm-setup-v2.sh
~/vm-setup-v2.sh start
```

The script installs a local copy at:

```text
/usr/local/lib/debian-dev-setup/v2/vm-setup-v2.sh
```

After the offline phase completes:

1. Log out of the original account.
2. Log in with the new account created during setup.
3. Run:

```bash
/usr/local/lib/debian-dev-setup/v2/vm-setup-v2.sh continue
```

### Option B: copy the script into a VM that has never been connected

Open the raw `vm-setup-v2.sh` file on another computer and copy its complete contents. In the disconnected VM, run:

```bash
cat > ~/vm-setup-v2.sh
```

Paste the script, press **Ctrl+D**, and then run:

```bash
chmod +x ~/vm-setup-v2.sh
~/vm-setup-v2.sh start
```

The continuation phase assists with reconnecting networking before any package operation is performed.

## Setup sequence

The full workflow provides the following steps:

1. Verify that networking is disconnected, temporarily disable NetworkManager networking, or pause for manual hypervisor adapter changes.
2. Back up `/etc/hosts` and `/etc/hostname`, then change the hostname without interrupting local hostname resolution.
3. Create or configure a new user.
4. Add the new user to the `sudo` group and defer changes to the original account until the new account passes sudo validation.
5. Optionally generate an SSH key pair.
6. Save a service and listening-socket inventory and optionally disable selected services.
7. Configure or open desktop lock and sleep settings.
8. Restore networking or pause for manual reconnection.
9. Run system maintenance and optionally install development tools.

Workflow state is stored under:

```text
/var/lib/debian-dev-setup/v2/
```

Reports are stored under:

```text
/var/log/debian-dev-setup/
```

## Commands

```text
vm-setup-v2.sh start       Begin the offline-first setup
vm-setup-v2.sh continue    Resume after login with the new account
vm-setup-v2.sh dev         Run online maintenance and developer-tool setup
vm-setup-v2.sh services    Inventory services and optionally disable selected services
vm-setup-v2.sh security    Configure optional firewall, logging, audit, and antivirus features
vm-setup-v2.sh baseline    Save a read-only system inventory
vm-setup-v2.sh status      Display workflow and system status
vm-setup-v2.sh help        Display command help
```

Use `--dry-run` to print privileged or destructive commands without executing them:

```bash
./vm-setup-v2.sh --dry-run start
```

Use `--config` to load an alternate package and service configuration:

```bash
./vm-setup-v2.sh --config /path/to/config-v2.sh dev
```

## Hostname changes

The hostname operation:

1. creates timestamped backups of `/etc/hosts` and `/etc/hostname`;
2. temporarily keeps both the old and new hostnames locally resolvable;
3. applies the new hostname with `hostnamectl`;
4. removes the old hostname token from the final local mapping; and
5. validates the resulting hostname and sudo access.

## User account handling

The original login account is not modified during the `start` phase.

During `continue`, the script verifies that:

- the current login matches the saved new account;
- the account belongs to the `sudo` group; and
- `sudo -v` succeeds.

It then offers three choices for the original account:

- leave the account unchanged;
- lock password authentication; or
- disable the account by expiring it, locking its password, and assigning a `nologin` shell.

The original home directory is retained, and recovery commands are displayed after an account change.

## SSH keys

The script supports:

- Ed25519;
- ECDSA P-521;
- RSA 4096; or
- no key generation.

Keys are created under the selected user's account. Existing key files are not overwritten.

## Services and listening ports

The service command records:

- enabled service units;
- running services; and
- listening TCP and UDP sockets.

No service is disabled automatically. Each service change requires explicit confirmation. Core system, display, and networking services are excluded from the default review list.

## Desktop lock and sleep settings

Desktop settings are applied per user:

- **GNOME:** idle lock and AC suspend settings can be configured with `gsettings`.
- **Xfce:** the supported power and screensaver settings panels are opened.
- **KDE Plasma:** System Settings is opened.
- **Other or headless sessions:** the script leaves the settings unchanged and prints a notice.

## Packages and profiles

Built-in package profiles include:

- command-line utilities;
- C/C++ build and debugging tools;
- Python development tools;
- Node.js and npm;
- the default Java Development Kit; and
- Podman and Buildah.

Additional apt package names can be entered interactively.

To customize the profiles without editing the main script:

```bash
mkdir -p ~/.config/debian-dev-setup
cp config-v2.example.sh \
  ~/.config/debian-dev-setup/config-v2.sh
nano ~/.config/debian-dev-setup/config-v2.sh
```

The configuration file is sourced as Bash code and must come from a trusted source.

## System maintenance

Before applying a full upgrade, the script runs an apt simulation and displays any packages scheduled for removal. Package removals require separate confirmation.

The maintenance sequence is:

```text
apt update
apt full-upgrade
apt autoremove
apt autoclean
```

## Visual Studio Code

Two installation methods are available:

1. Microsoft's apt repository, which integrates future VS Code updates with apt.
2. Microsoft's official x64 `.deb` redirect:

```text
https://go.microsoft.com/fwlink/?LinkID=760868
```

The apt-repository method verifies the Microsoft signing-key fingerprint before adding the repository. The direct `.deb` option is limited to `amd64` systems.

## Optional security and logging features

The `security` command can configure:

- UFW with an SSH-session lockout safeguard;
- persistent, compressed, size-limited systemd journal storage;
- `auditd` without adding custom audit rules;
- ClamAV;
- a read-only OpenSSH server configuration audit; and
- AppArmor status reporting.

These features are optional because firewalls and antivirus software may interfere with development, security testing, packet analysis, or malware-analysis environments.

## System baseline reports

The `baseline` command records:

- operating-system, kernel, architecture, and virtualization information;
- local users and groups;
- network interfaces and routes;
- listening ports;
- enabled and running services;
- firewall, AppArmor, audit, and journal status;
- checksums of selected configuration files; and
- installed package versions.

Baseline reports contain local system details and should be protected accordingly.

## Repository tests

The repository includes syntax, behavior, and compatibility checks. See [TESTING.md](TESTING.md) for the purpose of each test file and instructions for running the test suite.

## Original scripts

The original entry points remain available:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/bootstrap-system.sh)"
```

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/debian-dev-setup.sh)
```

These scripts retain their original online-only behavior.

## Repository layout

| File | Purpose |
|---|---|
| `vm-setup-v2.sh` | Full resumable setup workflow |
| `config-v2.example.sh` | Example package-profile and service configuration |
| `bootstrap-system.sh` | Original system bootstrap |
| `debian-dev-setup.sh` | Original developer-tool installer |
| `TESTING.md` | Test-suite documentation and system test procedure |
| `REFERENCES.md` | Upstream documentation used by the implementation |
| `CHANGELOG.md` | Release history |
| `tests/run-tests.sh` | Test-suite entry point |
| `tests/test-vm-setup-v2.sh` | Non-destructive behavior tests for reusable script functions |
| `tests/test-legacy-checksums.sh` | Compatibility check for the original scripts |

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).

## Author

Created by [Siavash Ashkiani](https://github.com/ashkiani).
