#!/usr/bin/env bash
# Standalone follow-up to vm-setup-v2.sh: provision and run a disposable AI VM.
# License: MIT
set -Eeuo pipefail
readonly VERSION=0.1.0
readonly ACCOUNT=dds-ai-agent BASE=/var/lib/debian-dev-setup/ai-sandbox
readonly WORK=$BASE/workspace LOGIN_HOME=$BASE/account
readonly ETC=/etc/debian-dev-setup/ai-sandbox UNIT=dds-ai-session.service
readonly FW=dds-ai-firewall.service TABLE=dds_ai_sandbox
readonly DENY4='0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 192.88.99.0/24, 192.168.0.0/16, 198.18.0.0/15, 198.51.100.0/24, 203.0.113.0/24, 224.0.0.0/3'
DRY=0 OFFLINE=0 MODE='' DNS='' MINUTES=120 MEMORY=4096 CPU=200 TASKS=256 NESTED=0
info(){ printf '[INFO] %s\n' "$*" >&2; }
warn(){ printf '[WARN] %s\n' "$*" >&2; }
die(){ printf '[FAIL] %s\n' "$*" >&2; exit 1; }
section(){ printf '\n== %s ==\n' "$*" >&2; }
trap 'warn "Stopped near line $LINENO. Review output; rerun start after correcting the problem."' ERR
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
  systemd-detect-virt --vm --quiet || die 'A recognized virtual machine is required.'
  [[ -z ${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-} ]] || die 'Use the VM console, not SSH.'
  local version; version=$(systemd-run --version); [[ $version =~ ^systemd[[:space:]]+([0-9]+) ]] && (( BASH_REMATCH[1] >= 248 )) || die 'systemd 248 or newer is required for the session restrictions.'
  sudo -v
}
positive(){ [[ $1 =~ ^[1-9][0-9]{0,5}$ ]]; }
valid_dns(){ local a b c d x; [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1; IFS=. read -r a b c d <<< "$1"; for x in "$a" "$b" "$c" "$d"; do [[ $x == 0 || $x != 0* ]] && ((10#$x <= 255)) || return 1; done; ((a>0 && a<224 && a!=10 && a!=127 && !(a==100 && b>=64 && b<=127) && !(a==169 && b==254) && !(a==172 && b>=16 && b<=31) && !(a==192 && (b==168 || (b==0 && (c==0 || c==2)) || (b==88 && c==99))) && !(a==198 && (b==18 || b==19 || (b==51 && c==100))) && !(a==203 && b==0 && c==113))); }
validate(){ [[ $MODE == offline || $MODE == https ]] || die 'Choose offline or https.'; if [[ $MODE == https ]]; then valid_dns "$DNS" || die 'A public IPv4 DNS address is required.'; else [[ -z $DNS ]] || die 'DNS is only used in HTTPS mode.'; fi; for v in "$MINUTES" "$MEMORY" "$CPU" "$TASKS"; do positive "$v" || die 'Limits must be positive integers (up to six digits).'; done; [[ $NESTED == 0 || $NESTED == 1 ]] || die 'Invalid namespace setting.'; }
render_rules(){ local uid=$1; [[ $uid =~ ^[1-9][0-9]*$ ]] || die 'Invalid agent UID.'; cat <<RULES
add table inet $TABLE
flush table inet $TABLE
add chain inet $TABLE output { type filter hook output priority -10; policy accept; }
RULES
  if [[ $MODE == https ]]; then cat <<RULES
add rule inet $TABLE output meta skuid $uid oifname "lo" counter drop
add rule inet $TABLE output meta skuid $uid fib daddr type local counter drop
add rule inet $TABLE output meta skuid $uid ip daddr { $DENY4 } counter drop
add rule inet $TABLE output meta skuid $uid ip daddr $DNS udp dport 53 counter accept
add rule inet $TABLE output meta skuid $uid ip daddr $DNS tcp dport 53 counter accept
add rule inet $TABLE output meta skuid $uid meta nfproto ipv4 tcp dport 443 counter accept
RULES
  fi
  printf 'add rule inet %s output meta skuid %s counter drop\n' "$TABLE" "$uid"
}
read_policy(){ local extra; if ((DRY)) && [[ ! -r $ETC/policy ]]; then MODE=${MODE:-offline}; validate; return; fi; [[ -f $ETC/policy && ! -L $ETC/policy && $(stat -c '%u:%a' "$ETC/policy") == 0:644 ]] || die 'Missing or unsafe policy; run start.'; read -r MODE DNS MINUTES MEMORY CPU TASKS NESTED extra < "$ETC/policy" || die 'Invalid policy.'; [[ -z $extra ]] || die 'Invalid policy.'; [[ $DNS != none ]] || DNS=''; validate; }
account_check(){
  local uid gid home shell
  IFS=: read -r _ _ uid gid _ home shell < <(getent passwd "$ACCOUNT") || die 'Agent account missing.'
  [[ $uid != 0 && $home == "$LOGIN_HOME" && $shell == /usr/sbin/nologin && $(id -nG "$ACCOUNT") == "$ACCOUNT" ]] || die 'Unexpected agent account attributes.'
  [[ $(sudo passwd -S "$ACCOUNT" | awk '{print $2}') == L ]] || die 'Agent password is not locked.'
  [[ $(stat -c '%u:%a' "$BASE") == 0:755 && $(stat -c '%u:%a' "$LOGIN_HOME") == 0:755 && $(stat -c '%u:%a' "$ETC") == 0:755 && $(stat -c '%u:%g:%a' "$WORK") == "$uid:$gid:700" && ! -L $BASE && ! -L $LOGIN_HOME && ! -L $WORK && ! -L $ETC ]] || die 'Unexpected workspace or policy permissions. Inspect the paths or revert the VM snapshot before retrying.'
  if grep -q "^$ACCOUNT:" /etc/subuid /etc/subgid 2>/dev/null; then die 'Agent has subordinate ID mappings; remove them before running.'; fi
  if sudo -l -U "$ACCOUNT" >/dev/null 2>&1; then die 'Agent may have sudo privileges; inspect sudoers.'; fi
}
idle(){ if systemctl is-active --quiet "$UNIT" || pgrep -u "$ACCOUNT" >/dev/null 2>&1; then die 'Agent processes already exist. Stop the session and inspect remaining processes.'; fi; }
packages(){ local p missing=(); for p in "$@"; do if [[ $(dpkg-query -W -f='${Status}' "$p" 2>/dev/null || :) != 'install ok installed' ]]; then missing+=("$p"); fi; done; ((${#missing[@]})) || return 0; if ((OFFLINE)); then warn "Offline: missing packages: ${missing[*]}. No package download will be attempted."; return 1; fi; info "Needed packages: ${missing[*]}"; if ((!DRY)) || [[ -t 0 ]]; then ask 'May apt update and install these packages from your configured distribution repositories?' || return 1; fi; root apt-get update || die 'apt update failed.'; root apt-get install --no-install-recommends --no-remove -y "${missing[@]}" || die 'Package installation failed.'; }
firewall_setup(){
  local uid=$1
  render_rules "$uid" | write_file "$ETC/firewall.nft" 0644
  cat <<SERVICE | write_file "/etc/systemd/system/$FW" 0644
[Unit]
Description=AI sandbox UID outbound policy
After=nftables.service ufw.service
Before=$UNIT
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f $ETC/firewall.nft
[Install]
WantedBy=multi-user.target
SERVICE
  root nft -c -f "$ETC/firewall.nft"
  root systemctl daemon-reload
  root systemctl enable "$FW"
  root systemctl restart "$FW"
}
start(){
  preflight
  section '1. Confirm the disposable VM boundary'
  warn 'Use a fresh snapshot/clone. In the hypervisor disable shared folders, clipboard, drag/drop, USB passthrough and host/LAN access. NAT alone does not isolate your LAN. Never put host credentials or sensitive files in this VM.'
  if ((!DRY)); then [[ -t 0 ]] || die 'start needs an interactive terminal.'; ask 'Have you prepared the VM and checked these host-side controls?' || die 'No changes made.'; fi
  section '2. Choose networking and session limits'
  if ((OFFLINE)) && [[ -z $MODE ]]; then MODE=offline; fi
  if [[ -z $MODE ]]; then MODE=$(choose 'Network: offline (no external networking) or https (public IPv4/443 and DNS)' offline); fi
  if ((OFFLINE)) && [[ $MODE != offline ]]; then die '--offline requires offline networking.'; fi
  if [[ $MODE == https && -z $DNS ]]; then DNS=$(choose 'Public IPv4 DNS resolver (queries sent in plaintext)' 1.1.1.1); fi
  MINUTES=$(choose 'Session time limit in minutes' "$MINUTES"); MEMORY=$(choose 'Memory limit in MiB' "$MEMORY"); CPU=$(choose 'CPU percent (100 = one CPU)' "$CPU"); TASKS=$(choose 'Maximum processes/threads' "$TASKS")
  if ask 'Allow nested namespaces/mount syscalls for agent-native sandboxes? This relaxes an outer restriction'; then NESTED=1; fi
  validate
  info "Mode=$MODE; minutes=$MINUTES; memory=${MEMORY}MiB; CPU=$CPU%; tasks=$TASKS; nested=$NESTED. Workspace persists until VM is destroyed/reverted. No disk quota; set a bounded virtual disk outside the VM."
  if ((!DRY)); then ask 'Apply these settings?' || die 'No changes made.'; fi
  section '3. Prepare the locked agent account'
  if ((!DRY)); then
    idle
    # Never repair ownership by following a pre-existing unexpected path.
    for dir in "${BASE%/*}" "${ETC%/*}" "$BASE" "$LOGIN_HOME" "$ETC"; do
      if [[ -e $dir || -L $dir ]]; then [[ -d $dir && ! -L $dir && $(stat -c '%u:%a' "$dir") == 0:755 ]] || die "Unexpected directory: $dir"; fi
    done
    if getent passwd "$ACCOUNT" >/dev/null; then account_check; elif [[ -e $WORK || -L $WORK ]]; then die 'Unexpected existing workspace; inspect it before retrying.'; fi
  fi
  # Internet-enabled mode requires nftables; isolated offline mode needs no packages.
  if [[ $MODE == https ]]; then packages nftables || die 'HTTPS requires nftables; install it first or choose offline.'; fi
  root install -d -o root -g root -m 0755 "$BASE" "$LOGIN_HOME" "$ETC"
  if getent passwd "$ACCOUNT" >/dev/null; then
    info 'Existing dedicated account passed checks (or is being previewed).'
  else
    root useradd --system --user-group --no-create-home --home-dir "$LOGIN_HOME" --shell /usr/sbin/nologin "$ACCOUNT"
  fi
  root passwd -l "$ACCOUNT"
  root install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 0700 "$WORK"
  if ((!DRY)); then account_check; fi
  section '4. Apply network policy'
  local uid=999
  if ((!DRY)); then uid=$(id -u "$ACCOUNT"); fi
  if [[ $MODE == https ]] || command -v nft >/dev/null || [[ -e /etc/systemd/system/$FW ]]; then
    firewall_setup "$uid"
  else
    info 'Offline session will use a private network namespace and deny IP sockets; nftables is not required for this mode.'
  fi
  if [[ $MODE == https ]]; then printf 'nameserver %s\noptions timeout:2 attempts:2\n' "$DNS" | write_file "$ETC/resolv.conf" 0644; fi
  printf '%s %s %s %s %s %s %s\n' "$MODE" "${DNS:-none}" "$MINUTES" "$MEMORY" "$CPU" "$TASKS" "$NESTED" | write_file "$ETC/policy" 0644
  if ((!DRY)); then verify; fi
  section '5. Optional AI agent installation'
  if [[ $MODE == https ]] && ((!OFFLINE)); then
    if ask 'Install Codex now?'; then install_agent codex; fi
    if ask 'Install Claude Code now?'; then install_agent claude; fi
  else info 'Offline mode does not download agents. Use a pre-provisioned VM or copy reviewed software into the workspace.'; fi
  info "Setup complete (or previewed). Workspace: $WORK"
  if ((!DRY)); then
    if ask 'Start an agent session now?'; then menu_run; fi
  else info 'Dry-run: no changes made.'; fi
}
launch(){
  local uid=999 term=${TERM:-xterm} arg; local -a args escaped=()
  [[ $term =~ ^[a-zA-Z0-9._+-]{1,64}$ ]] || term=xterm
  if ((!DRY)); then account_check; idle; uid=$(id -u "$ACCOUNT"); fi
  if [[ $MODE == https ]] || [[ -e /etc/systemd/system/$FW ]]; then
    if ((!DRY)); then render_rules "$uid" | sudo cmp -s - "$ETC/firewall.nft" || die 'Firewall policy drift. Run start again.'; if [[ $MODE == https ]]; then printf 'nameserver %s\noptions timeout:2 attempts:2\n' "$DNS" | sudo cmp -s - "$ETC/resolv.conf" || die 'DNS policy drift.'; fi; fi
    root nft -c -f "$ETC/firewall.nft"; root systemctl restart "$FW"; root nft list table inet "$TABLE"
    args=(-p "BindsTo=$FW" -p "After=$FW")
  else args=(); fi
  args+=(--unit="$UNIT" --collect --service-type=exec --uid="$ACCOUNT" --gid="$ACCOUNT" --working-directory="$WORK"
    -p NoNewPrivileges=yes -p 'CapabilityBoundingSet=' -p 'AmbientCapabilities=' -p ProtectSystem=strict -p ProtectHome=yes -p "ReadWritePaths=$WORK"
    -p PrivateTmp=yes -p PrivateDevices=yes -p PrivateIPC=yes -p ProtectKernelTunables=yes -p ProtectKernelModules=yes -p ProtectKernelLogs=yes -p ProtectControlGroups=yes -p ProtectClock=yes -p ProtectHostname=yes -p ProtectProc=invisible -p RestrictSUIDSGID=yes -p RestrictRealtime=yes -p LockPersonality=yes
    -p 'TemporaryFileSystem=/run:ro' -p 'InaccessiblePaths=-/usr/bin/crontab -/usr/bin/at -/mnt -/media' -p UMask=0077 -p "RuntimeMaxSec=${MINUTES}min" -p "MemoryMax=${MEMORY}M" -p "CPUQuota=${CPU}%" -p "TasksMax=$TASKS" -p KillMode=control-group -p TimeoutStopSec=10s -p LimitCORE=0)
  if ((NESTED)); then args+=(-p 'SystemCallFilter=~@reboot @swap @module @raw-io @debug'); else args+=(-p RestrictNamespaces=yes -p 'SystemCallFilter=~@mount @reboot @swap @module @raw-io @debug'); fi
  if [[ $MODE == offline ]]; then args+=(-p PrivateNetwork=yes -p 'RestrictAddressFamilies=AF_UNIX'); else args+=(-p 'RestrictAddressFamilies=AF_UNIX AF_INET' -p "BindReadOnlyPaths=$ETC/resolv.conf:/etc/resolv.conf"); fi
  if [[ ${CHECK_ONLY:-0} == 0 && -t 0 && -t 1 ]]; then args+=(--pty --wait); else args+=(--pipe --wait); fi
  if systemd-run --help 2>/dev/null | grep -- '--expand-environment' >/dev/null; then args+=(--expand-environment=no); else for arg in "$@"; do escaped+=("${arg//\$/\$\$}"); done; set -- "${escaped[@]}"; fi
  root systemd-run "${args[@]}" -- /usr/bin/env -i "HOME=$WORK" "USER=$ACCOUNT" "LOGNAME=$ACCOUNT" "PATH=$WORK/.local/bin:/usr/bin:/bin" "TERM=$term" "$@"
}
install_agent(){ local name=$1 package version; [[ $MODE == https ]] || die 'Agent installation requires HTTPS mode.'; case $name in codex) package=@openai/codex;; claude) package=@anthropic-ai/claude-code;; *) die 'Choose codex or claude.';; esac
  version=$(choose "Version of $package (exact version recommended; latest is mutable)" latest)
  [[ $version == latest || $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]] || die 'Invalid version.'
  ask "Download $package@$version from npm and allow its install scripts to run as the restricted agent (not root)?" || return 0
  packages nodejs npm ca-certificates || die 'Node/npm required; install a supported version if distro packages are too old.'
  launch /usr/bin/npm install --global --prefix "$WORK/.local" --registry=https://registry.npmjs.org/ --no-audit --no-fund "$package@$version"
}
menu_run(){ local selected; selected=$(choose 'Start shell, codex or claude' shell); case $selected in shell) launch /bin/bash --noprofile --norc;; codex|claude) if ((!DRY)); then sudo test -x "$WORK/.local/bin/$selected" || die "Not installed. Run $0 install $selected."; fi; launch "$WORK/.local/bin/$selected";; *) die 'Unknown choice.';; esac; }
verify(){
  section 'Verification: account, policy and active session'
  if ((!DRY)); then account_check; fi
  # Execute inside the same transient service as the agent; no external probes.
  CHECK_ONLY=1 launch /bin/bash --noprofile --norc -c 'set -eu
    test "$(id -u)" != 0; test "$(id -Gn)" = "$USER"
    grep -Eq "^NoNewPrivs:[[:space:]]*1$" /proc/self/status
    grep -Eq "^CapEff:[[:space:]]*0+$" /proc/self/status
    test ! -w /etc; test ! -r /root; test ! -w /usr; test "$PWD" = "$HOME"
    for dir in /etc /usr; do opts=$(findmnt -n -o OPTIONS --target "$dir"); case ",$opts," in *,ro,*) ;; *) exit 1;; esac; done
    testfile=$(mktemp "$HOME/.dds-probe.XXXXXX"); rm -- "$testfile"
    if [[ $1 == offline ]]; then test "$(tail -n +3 /proc/net/dev | cut -d: -f1 | tr -d "[:space:]")" = lo; test "$(tail -n +3 /proc/net/dev | wc -l)" -eq 1; fi
    echo "[PASS] Session identity, privilege, filesystem, workspace and offline interface checks (as applicable)."' probe "$MODE"
  info 'HTTPS rules are reloaded at session start; verify external host/LAN isolation separately. This probe is not a penetration test.'
}
usage(){ cat <<HELP
Usage: $0 start [--dry-run] [--offline] [--network offline|https] [--dns PUBLIC_IPV4]
       $0 run [--dry-run]              # interactive shell/agent choice
       $0 install codex|claude        # optional user-local installation
       $0 verify                     # run active security checks when idle
       $0 stop                       # end the complete agent process group
       $0 --help | --version
No repository checkout needed. Copy this entire file to an offline VM if needed.
--offline: no package downloads; offline session networking only.
--dry-run: no changes; interactive questions on a terminal, safe defaults otherwise.
Host-side isolation and snapshot/revert/destruction are your responsibility.
HELP
}
main(){ local cmd=${1:-start} agent=''; if (($#)); then shift; fi; case $cmd in -h|--help|help) usage; return;; --version) echo "$VERSION"; return;; install) agent=${1:-}; [[ $agent == codex || $agent == claude ]] || die 'Choose codex or claude.'; shift;; start|run|verify|stop) ;; *) die 'Unknown command; see --help.';; esac
  while (($#)); do case $1 in --dry-run) DRY=1;; --offline) [[ $cmd == start ]] || die 'Option only for start.'; OFFLINE=1;; --network) [[ $cmd == start && $# -ge 2 ]] || die 'Expected start --network MODE.'; MODE=$2; shift;; --dns) [[ $cmd == start && $# -ge 2 ]] || die 'Expected start --dns ADDRESS.'; DNS=$2; shift;; *) die "Unknown option: $1";; esac; shift; done
  if [[ $cmd == start ]]; then start; return; fi
  preflight
  if [[ $cmd == stop ]]; then root systemctl stop "$UNIT"; return; fi
  read_policy
  case $cmd in run) menu_run;; install) install_agent "$agent";; verify) verify;; esac
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
