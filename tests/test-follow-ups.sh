#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/ai" "$TMP/pi"
cp "$ROOT/ai-sandbox-setup.sh" "$TMP/ai/"
cp "$ROOT/pi-hardening.sh" "$TMP/pi/"
# A dry-run must never invoke sudo, even if the command would otherwise fail.
cat > "$TMP/bin/sudo" <<'GUARD'
#!/usr/bin/env bash
printf 'sudo invoked\n' >> "$DDS_TEST_SENTINEL"
exit 99
GUARD
chmod +x "$TMP/bin/sudo"
export DDS_TEST_SENTINEL="$TMP/mutation"
export PATH="$TMP/bin:$PATH"
ai=$TMP/ai/ai-sandbox-setup.sh
pi=$TMP/pi/pi-hardening.sh
count=0
pass(){ count=$((count + 1)); printf 'PASS: %s\n' "$1"; }
has(){ grep -Fq -- "$2" "$1" || { cat "$1"; printf 'Missing: %s\n' "$2" >&2; exit 1; }; pass "$3"; }
reject(){ if "$@" > "$TMP/reject" 2>&1 </dev/null; then echo "Expected failure: $*" >&2; exit 1; fi; pass "Rejected: $*"; }
"$ai" --help > "$TMP/ai-help"; has "$TMP/ai-help" 'No repository checkout needed' 'AI standalone help'
"$pi" --help > "$TMP/pi-help"; has "$TMP/pi-help" 'No repository checkout needed' 'Pi standalone help'
(cd "$TMP/ai"; ./ai-sandbox-setup.sh start --offline --dry-run </dev/null) > "$TMP/offline" 2>&1
has "$TMP/offline" 'offline none 120 4096 200 256 0' 'AI offline defaults'
if grep -Fq 'apt-get' "$TMP/offline"; then echo 'Offline requested apt' >&2; exit 1; fi; pass 'Offline setup never requests apt'
(cd "$TMP/ai"; ./ai-sandbox-setup.sh start --dry-run --network https --dns 1.1.1.1 </dev/null) > "$TMP/online" 2>&1
has "$TMP/online" 'https 1.1.1.1 120 4096 200 256 0' 'HTTPS policy'
has "$TMP/online" 'fib daddr type local counter drop' 'Local addresses blocked'
has "$TMP/online" '192.168.0.0/16' 'Private addresses blocked'
has "$TMP/online" 'ip daddr 1.1.1.1 udp dport 53 counter accept' 'DNS resolver restricted'
has "$TMP/online" 'meta nfproto ipv4 tcp dport 443 counter accept' 'HTTPS port-only egress'
has "$TMP/online" 'output meta skuid 999 counter drop' 'Default deny for agent UID'
"$ai" run --dry-run </dev/null > "$TMP/run" 2>&1
has "$TMP/run" 'PrivateNetwork=yes' 'Offline private network'
has "$TMP/run" 'ProtectSystem=strict' 'Read-only system'
has "$TMP/run" 'NoNewPrivileges=yes' 'No privilege escalation'
has "$TMP/run" 'RuntimeMaxSec=120min' 'Session expiration'
has "$TMP/run" 'MemoryMax=4096M' 'Memory limit'
has "$TMP/run" 'CPUQuota=200%' 'CPU limit'
has "$TMP/run" 'TasksMax=256' 'Task limit'
has "$TMP/run" 'RestrictNamespaces=yes' 'Strict outer namespace restrictions'
has "$TMP/run" '/usr/bin/env -i' 'Admin environment not inherited'
"$ai" verify --dry-run </dev/null > "$TMP/verify" 2>&1
has "$TMP/verify" 'NoNewPrivs' 'Verification runs session probe'
reject "$ai" start --dry-run --network https --dns 192.168.1.1
reject "$ai" start --dry-run --network https --dns 1.1.1.999
reject "$ai" start --dry-run --network https --dns '1.1.1.1; id'
reject "$ai" start --dry-run --offline --network https
reject "$ai" start --dry-run --network invalid
reject "$ai" start --dry-run --dns 1.1.1.1
reject "$ai" install 'unknown'
(cd "$TMP/pi"; ./pi-hardening.sh start --dry-run --offline </dev/null) > "$TMP/pi-preview" 2>&1
has "$TMP/pi-preview" 'SSH' 'Pi SSH step'
has "$TMP/pi-preview" 'Inbound firewall' 'Pi firewall step'
has "$TMP/pi-preview" 'Raspberry Pi hardware' 'Pi hardware step'
has "$TMP/pi-preview" 'Dry-run: no changes made' 'Pi preview completion'
"$pi" start --dry-run --server </dev/null > "$TMP/server" 2>&1
if grep -Fq 'Raspberry Pi hardware' "$TMP/server"; then exit 1; fi; pass 'Server mode skips Pi-specific steps'
# Exercise approved options in a preview by replacing ONLY interactive input.
# Offline package absence must not invoke apt; provide a simulated installed-package query.
bash -c 'source "$1"; DRY=1; OFFLINE=1; ask(){ return 0; }; choose(){ printf "%s\n" "$2"; }; packages(){ return 0; }; start' _ "$pi" > "$TMP/pi-all" 2>&1
has "$TMP/pi-all" 'SystemMaxUse=100M' 'Capped journal configuration'
has "$TMP/pi-all" 'Unattended-Upgrade::Automatic-Reboot "false"' 'No automatic reboot'
has "$TMP/pi-all" 'PasswordAuthentication no' 'SSH key-only configuration'
has "$TMP/pi-all" 'ufw default deny incoming' 'Firewall default deny'
has "$TMP/pi-all" 'RuntimeWatchdogSec=30s' 'Watchdog configuration'
has "$TMP/pi-all" 'disable --now bluetooth.service' 'Opt-in Bluetooth control'
bash -c 'source "$1"; valid_rule 22/tcp; valid_rule 51820/udp; ! valid_rule 0/tcp; ! valid_rule 65536/tcp; ! valid_rule "22/tcp;id"' _ "$pi"; pass 'Firewall port/protocol validation'
[[ ! -e $DDS_TEST_SENTINEL ]] || { echo 'Unexpected sudo invocation' >&2; exit 1; }; pass 'No dry-run privileged operations'
printf 'All %s follow-up assertions passed.\n' "$count"
