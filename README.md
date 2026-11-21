# debian-dev-setup

Interactive setup and hardening scripts for Debian-derived systems and virtual machines.

The repository includes a resumable workflow for full VM setup, plus the original lightweight bootstrap and developer-tool scripts.

## Scripts

| File | Purpose |
|---|---|
| `vm-setup-v2.sh` | Full VM setup with hostname, account, SSH, service, package, and optional security configuration |
| `ai-sandbox-setup.sh` | Prepare and run a restricted AI-agent environment in a disposable VM |
| `pi-hardening.sh` | Guided Raspberry Pi and optional general server hardening |
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

## Optional follow-up scripts

Run these **after** the base setup on a suitable machine. Each is a complete,
standalone file. Both scripts ask for approval before changing the system and use sudo only when needed.

### Disposable AI-agent VM

Use a fresh VM or snapshot, not your daily workstation. Complete the base setup,
then disable hypervisor shared folders, clipboard, drag/drop, USB passthrough
and access to the host/LAN. NAT by itself is not sufficient. Use a bounded virtual
disk and host-enforced isolation. For an offline guest, disconnect its adapter.

```bash
curl -fsSLo ~/ai-sandbox-setup.sh \
  https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/ai-sandbox-setup.sh
chmod +x ~/ai-sandbox-setup.sh
~/ai-sandbox-setup.sh start
```

The guided setup lets you choose:

- Offline (default) or public IPv4 TCP/443 plus DNS to a chosen public resolver.
  HTTPS mode requires nftables and permits arbitrary public IPv4 TCP/443, **not**
  only approved domains or verified TLS. DNS is ordinary port 53, not encrypted.
- Session time, memory, CPU and process limits (defaults: 120 minutes, 4096 MiB,
  200% CPU, 256 tasks). These are session limits, not a disk quota or VM lifetime.
- Whether to relax namespace/mount restrictions for the agent's own sandbox.
  Some agent versions need this; never disable agent-native protection merely to
  make a test pass.
- In HTTPS mode, optional Codex and Claude Code installation via npm, executed
  as the restricted account. Choose a reviewed exact version where possible.
  The distro Node/npm versions must satisfy the selected CLI's requirements.

The dedicated `dds-ai-agent` account is locked, has no login shell or sudo, and
runs under a transient systemd service with a private writable workspace,
read-only system directories, hidden home directories, restricted devices and
capabilities, and a bounded lifetime. Network policy is applied before launch.
The script performs an active local verification before optional agent installation.
Use a supported Debian-derived VM with systemd 248 or newer (e.g. Debian 12+).

Once configured, run the **same file** to start a shell, Codex or Claude Code:

```bash
~/ai-sandbox-setup.sh run
```

Other optional commands: `verify` (when idle), `stop` (ends the session process
group), `install codex`, `install claude`, `start --dry-run`, and `--help`.
`start` can be rerun to change settings when no agent processes are running.

The workspace is `/var/lib/debian-dev-setup/ai-sandbox/workspace`. Put only
reviewed project files and narrowly scoped credentials there. Use the agent's
supported device-code/manual authentication if available; loopback connections
are intentionally blocked in HTTPS mode. No administrator environment or tokens
are passed to the agent. Do not assume credentials or files in the workspace
are protected from the agent itself. Work and login state persist between
sessions until the VM is reverted/destroyed. Export reviewed results and revoke
credentials before deleting the VM. The script never destroys the VM itself.

This is defense in depth, not a guarantee of containment: the guest kernel,
other local services, abstract Unix sockets in online mode, public-addressed
host/LAN services and external firewall changes remain relevant. Do not use an
actively hostile or sensitive workload without separate host-level restrictions.
Do not flush/reload firewall rules or change policy during an agent session.

### Raspberry Pi or general Debian server

Run on Raspberry Pi OS (prefer current Lite ARM64), or add `--server` to use the
same script on a Debian-derived system without Pi-specific hardware steps.

```bash
curl -fsSLo ~/pi-hardening.sh \
  https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/pi-hardening.sh
chmod +x ~/pi-hardening.sh
~/pi-hardening.sh start
```

The wizard inventories running services and listening ports, then offers capped
persistent or volatile logging, unattended package updates, SSH hardening,
UFW firewall with user-selected TCP/UDP ports, hardware watchdog and Bluetooth
service management. All changes are opt-in. SSH settings are validated and
rolled back on failed validation/reload. Use a local console for SSH/firewall
changes (the script skips these when it detects SSH). Retest key login before
leaving the console. Unattended updates depend on your distribution's configured
origins; check them, and review the effective firewall and log settings. No
automatic reboot is initiated. For a report run `~/pi-hardening.sh verify`
(add `--server` on non-Pi systems).

Recovery: keep a backup of the SD card or VM. At a local console, `sudo ufw disable`
disables UFW (including pre-existing rules). Restore/remove only the script's
named drop-ins and reload the relevant service; use the backup for complete
reversal. `--help` lists the commands and precautions.

### Offline and preview operation

Copy either **complete** script from another machine or paste it with `cat >
~/ai-sandbox-setup.sh` (or `~/pi-hardening.sh`), followed by Ctrl+D. Run `chmod +x`
on the copied script and then run `start --offline`. The AI script needs no
package downloads for offline session isolation; the Pi script skips optional
steps whose packages are absent. Existing APT timers, if enabled, are not
stopped by Pi offline setup; it may enable timers for a future boot only with
approval. Disconnect networking at the hypervisor or physically when strict
machine-wide offline operation is needed.

Both scripts support `start --dry-run` for a non-mutating preview. In a terminal
it asks the same optional questions; without one it uses safe preview defaults.
The original v2 script and legacy entry points are unchanged. Live integration
checks on a disposable VM and a Pi are required before relying on the new controls;
see [TESTING.md](TESTING.md).

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
