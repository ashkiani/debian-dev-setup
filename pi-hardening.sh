#!/usr/bin/env bash
# Standalone, interactive hardening for Raspberry Pi OS / Debian-derived servers.
# License: MIT
set -Eeuo pipefail
readonly VERSION=0.1.0
readonly SSH_CONF=/etc/ssh/sshd_config.d/00-debian-dev-setup.conf
readonly JOURNAL_CONF=/etc/systemd/journald.conf.d/60-debian-dev-setup.conf
readonly UPDATE_CONF=/etc/apt/apt.conf.d/52debian-dev-setup
readonly WATCHDOG_CONF=/etc/systemd/system.conf.d/60-debian-dev-setup-watchdog.conf
DRY=0 OFFLINE=0 SERVER=0
info(){ printf '[INFO] %s\n' "$*" >&2; }
warn(){ printf '[WARN] %s\n' "$*" >&2; }
die(){ printf '[FAIL] %s\n' "$*" >&2; exit 1; }
section(){ printf '\n== %s ==\n' "$*" >&2; }
trap 'warn "Stopped near line $LINENO. Review completed steps; rerun start if appropriate."' ERR
run(){ if ((DRY)); then printf 'Would run: '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }
root(){ run sudo -- "$@"; }
ask(){ local a; if [[ ! -t 0 ]] && ((DRY)); then info "$* [preview: no]"; return 1; fi; read -r -p "$* [y/N] " a || return 1; [[ $a =~ ^([yY]|[yY][eE][sS])$ ]]; }
choose(){ local a; if [[ ! -t 0 ]] && ((DRY)); then printf '%s\n' "$2"; return; fi; read -r -p "$1 [$2]: " a || die 'Input ended.'; printf '%s\n' "${a:-$2}"; }
write_file(){ local dest=$1 mode=$2 tmp; if ((DRY)); then info "Would write $dest ($mode)"; cat; return; fi; tmp=$(mktemp); if ! cat > "$tmp" || ! sudo install -o root -g root -m "$mode" -- "$tmp" "$dest"; then rm -f -- "$tmp"; die "Cannot write $dest"; fi; rm -f -- "$tmp"; }
preflight(){
  ((DRY)) && return 0
  [[ $EUID != 0 ]] || die 'Run as a normal sudo-capable administrator, not root.'
  [[ $(ps -p 1 -o comm=) == systemd ]] || die 'systemd is required.'
  command -v apt-get >/dev/null || die 'A Debian-derived distribution is required.'
  if ((!SERVER)); then local model=''; [[ ! -r /proc/device-tree/model ]] || model=$(tr -d '\0' < /proc/device-tree/model); [[ $model == *'Raspberry Pi'* ]] || die 'Raspberry Pi not detected. Use --server for a general Debian server.'; fi
  sudo -v
}
console(){ if [[ -n ${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-} ]]; then warn 'Skipping: use a physical/local console for this change to avoid locking yourself out.'; return 1; fi; return 0; }
packages(){ local p missing=(); for p in "$@"; do if [[ $(dpkg-query -W -f='${Status}' "$p" 2>/dev/null || :) != 'install ok installed' ]]; then missing+=("$p"); fi; done; ((${#missing[@]})) || return 0; if ((OFFLINE)); then warn "Offline: missing packages: ${missing[*]}; this step is skipped."; return 1; fi; info "Needed packages: ${missing[*]}"; ask 'May apt update and install these packages from your configured repositories?' || return 1; root apt-get update || die 'apt update failed.'; root apt-get install --no-install-recommends --no-remove -y "${missing[@]}" || die 'Package installation failed.'; }
# A separate named drop-in is used for each control; never rewrite vendor files.
configure_journal(){
  local storage
  storage=$(choose 'Journal storage: persistent (survives reboot), volatile (less SD wear), or skip' persistent)
  case $storage in skip) return;; persistent|volatile) ;; *) die 'Invalid journal storage.';; esac
  root install -d -m 0755 /etc/systemd/journald.conf.d
  cat <<CONF | write_file "$JOURNAL_CONF" 0644
[Journal]
Storage=$storage
Compress=yes
SystemMaxUse=100M
SystemKeepFree=200M
RuntimeMaxUse=50M
MaxRetentionSec=7day
CONF
  root systemctl restart systemd-journald.service
  info 'Journal size targets are not hard quotas. Volatile logging loses evidence on reboot.'
}
configure_updates(){
  warn 'Automatic updates use configured APT origins; verify that your OS includes security updates. No automatic reboot will be enabled by this script.'
  packages unattended-upgrades || return 0
  cat <<'CONF' | write_file "$UPDATE_CONF" 0644
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "false";
CONF
  if ((OFFLINE)); then root systemctl enable apt-daily.timer apt-daily-upgrade.timer; info 'Timers enabled for future boots, not started by this script. Existing timers are not stopped.'; else root systemctl enable --now apt-daily.timer apt-daily-upgrade.timer; fi
  info 'When online, inspect allowed origins with sudo unattended-upgrade --dry-run --debug.'
}
configure_ssh(){
  local backup='' effective setting
  console || return 0
  if ((!DRY)) && [[ ! -x /usr/sbin/sshd ]]; then info 'SSH server not installed; skipped.'; return 0; fi
  warn 'Disables password, keyboard-interactive and root SSH login, X11 and SSH forwarding. Confirm non-root key login works and keep physical console access.'
  ask 'Have you tested key-based administrator login and do you approve these SSH restrictions?' || return 0
  if ((!DRY)); then sudo /usr/sbin/sshd -t || die 'Existing SSH configuration is invalid.'; if sudo test -e "$SSH_CONF"; then backup=$(sudo mktemp /etc/ssh/dds-ssh-backup.XXXXXX); sudo cp -p -- "$SSH_CONF" "$backup"; fi; fi
  root install -d -m 0755 /etc/ssh/sshd_config.d
  cat <<'CONF' | write_file "$SSH_CONF" 0644
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
CONF
  if ((DRY)); then root /usr/sbin/sshd -t; root /usr/sbin/sshd -T; root systemctl reload ssh.service; return 0; fi
  rollback_ssh(){ if [[ -n $backup ]]; then sudo cp -p -- "$backup" "$SSH_CONF"; else sudo rm -f -- "$SSH_CONF"; fi; }
  if ! sudo /usr/sbin/sshd -t || ! effective=$(sudo /usr/sbin/sshd -T); then rollback_ssh; die 'SSH validation failed; previous drop-in restored.'; fi
  for setting in 'permitrootlogin no' 'passwordauthentication no' 'kbdinteractiveauthentication no' 'pubkeyauthentication yes' 'x11forwarding no' 'allowagentforwarding no' 'allowtcpforwarding no'; do
    if ! grep -Fxq "$setting" <<< "$effective"; then rollback_ssh; die "Setting not effective: $setting. Previous drop-in restored."; fi
  done
  if systemctl is-active --quiet ssh.service; then if ! sudo systemctl reload ssh.service; then rollback_ssh; sudo systemctl reload ssh.service || warn 'Reload after rollback failed; inspect locally.'; die 'SSH reload failed; previous drop-in restored.'; fi; fi
  [[ -z $backup ]] || info "Previous SSH drop-in: $backup"
  warn 'Global settings checked. Match blocks and socket activation may differ. Test another key login before leaving the console.'
}
valid_rule(){ [[ $1 =~ ^([1-9][0-9]{0,4})/(tcp|udp)$ ]] && ((10#${BASH_REMATCH[1]} <= 65535)); }
configure_firewall(){
  local requested rule sshports p found; local -a rules=()
  console || return 0
  warn 'UFW changes inbound policy. This is for an endpoint, not a router, bridge or container host. Existing rules remain; review them first. New allowed ports are open to all sources.'
  if ((!DRY)) && command -v ufw >/dev/null; then sudo ufw status verbose; fi
  requested=$(choose 'Required inbound ports, space-separated (e.g. 22/tcp 51820/udp), or none' none)
  if [[ $requested != none ]]; then read -r -a rules <<< "$requested"; for rule in "${rules[@]}"; do valid_rule "$rule" || die "Invalid port/protocol: $rule"; done; fi
  if ((!DRY)) && (systemctl is-active --quiet ssh.service || systemctl is-active --quiet ssh.socket); then
    [[ -x /usr/sbin/sshd ]] || die 'SSH is active but sshd is unavailable; cannot validate its ports.'
    sshports=$(sudo /usr/sbin/sshd -T | awk '$1=="port" {print $2}'); [[ -n $sshports ]] || die 'Could not determine SSH ports.'
    for p in $sshports; do found=0; for rule in "${rules[@]}"; do [[ $rule != "$p/tcp" ]] || found=1; done; ((found)) || die "SSH is active on $p/tcp; include that port, or disable SSH separately first."; done
    if systemctl is-active --quiet ssh.socket; then warn 'SSH socket activation may listen on additional ports; check the listening socket inventory.'; fi
  fi
  info "New inbound rules: ${rules[*]:-none}. Default deny incoming, allow outgoing. Existing routed policy unchanged."
  ask 'Apply this firewall policy? Confirm local console access and every required service/port.' || return 0
  packages ufw || return 0
  for rule in "${rules[@]}"; do root ufw allow "$rule"; done
  root ufw default deny incoming
  root ufw default allow outgoing
  root ufw --force enable
  root ufw status verbose
  warn 'IPv6 coverage depends on UFW configuration; verify both protocols as applicable. To recover at console: sudo ufw disable.'
}
configure_watchdog(){
  if ((!DRY)) && [[ ! -c /dev/watchdog0 && ! -c /dev/watchdog ]]; then warn 'No hardware watchdog device found; skipped.'; return 0; fi
  warn 'Hardware watchdog may reboot a hung Pi. Confirm firmware support; setting applies at next reboot.'
  ask 'Enable a 30-second hardware watchdog?' || return 0
  root install -d -m 0755 /etc/systemd/system.conf.d
  printf '[Manager]\nRuntimeWatchdogSec=30s\n' | write_file "$WATCHDOG_CONF" 0644
}
review(){ section 'Current system'; run systemctl list-units --type=service --state=running --no-pager; if command -v ss >/dev/null; then root ss -lntu; fi; }
start(){
  preflight
  if ((!DRY)); then [[ -t 0 ]] || die 'start needs an interactive terminal.'; fi
  warn 'Back up the system or SD card. Review each change; nothing is disabled without approval. For firewall and SSH changes use a local console.'
  if ((!DRY)); then ask 'Begin guided hardening?' || { info 'No changes made.'; return; }; fi
  review
  section '1. Logging and SD-card wear'
  info 'Bound journald storage; choose persistent logs for evidence or volatile logs for reduced writes.'
  if ask 'Configure journal storage and retention?'; then configure_journal; fi
  section '2. Automatic security maintenance'
  if ask 'Configure unattended updates (network may be used later by APT timers)?'; then configure_updates; fi
  section '3. Secure remote access'
  if ask 'Review and harden existing SSH server?'; then configure_ssh; fi
  section '4. Inbound firewall'
  if ask 'Configure UFW firewall and allowed inbound ports?'; then configure_firewall; fi
  if ((!SERVER)); then
    section '5. Raspberry Pi hardware and services'
    if ask 'Review hardware watchdog option?'; then configure_watchdog; fi
    if ask 'Disable Bluetooth service? This can disconnect Bluetooth input/devices.'; then
      if ((DRY)) || systemctl cat bluetooth.service >/dev/null 2>&1; then root systemctl disable --now bluetooth.service; else info 'Bluetooth service not present.'; fi
    fi
  fi
  section 'Review remaining services'
  info 'Review unused services and network listeners; no automatic service removal or interface changes.'
  if ((!DRY)); then verify; else info 'Dry-run: no changes made.'; fi
  info 'No automatic reboot. See verify and --help for inspection/recovery.'
}
verify(){
  section 'Hardening report (inspection only)'
  local file
  for file in "$JOURNAL_CONF" "$UPDATE_CONF" "$SSH_CONF" "$WATCHDOG_CONF"; do if [[ -f $file ]]; then info "Installed drop-in: $file"; run cat "$file"; else info "Not configured by this script: $file"; fi; done
  if [[ -x /usr/sbin/sshd ]]; then if ((DRY)); then root /usr/sbin/sshd -t; root /usr/sbin/sshd -T; else sudo /usr/sbin/sshd -t || die 'sshd configuration is invalid.'; sudo /usr/sbin/sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|x11forwarding|allowagentforwarding|allowtcpforwarding) '; fi; fi
  if command -v ufw >/dev/null; then root ufw status verbose; fi
  run systemctl list-timers --all --no-pager apt-daily.timer apt-daily-upgrade.timer
  run journalctl --disk-usage
  if ((!SERVER)); then run systemctl show -p RuntimeWatchdogUSec; if ((!DRY)); then systemctl is-enabled bluetooth.service 2>/dev/null || :; systemctl is-active bluetooth.service 2>/dev/null || :; fi; fi
  review
  info 'Report shows current settings and listeners; test remote access and allowed ports from a separate machine. It is not a security certification.'
}
usage(){ cat <<HELP
Usage: $0 start [--dry-run] [--offline] [--server]
       $0 verify [--server] [--dry-run]
       $0 --help | --version
No repository checkout needed. Every change is opt-in. --server skips Pi hardware checks/options.
--offline: no package downloads; skip steps with missing packages; APT timers may run later.
--dry-run: no changes; review prompts at a terminal.
Recovery at local console: sudo ufw disable (disables all UFW rules);
remove or restore only the named debian-dev-setup drop-ins and reload the affected service.
Do not reboot until you have validated access. Use your backup for complete restoration.
HELP
}
main(){ local cmd=${1:-start}; if (($#)); then shift; fi; case $cmd in --help|-h|help) usage; return;; --version) echo "$VERSION"; return;; start|verify) ;; *) die 'Unknown command; see --help.';; esac
  while (($#)); do case $1 in --dry-run) DRY=1;; --offline) [[ $cmd == start ]] || die '--offline only for start.'; OFFLINE=1;; --server) SERVER=1;; *) die "Unknown option: $1";; esac; shift; done
  if [[ $cmd == start ]]; then start; else preflight; verify; fi
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
