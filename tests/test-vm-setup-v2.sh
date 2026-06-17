#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$ROOT_DIR/vm-setup-v2.sh"

passes=0
failures=0

pass() { printf 'PASS: %s\n' "$1"; ((passes += 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; ((failures += 1)); }

assert_true() {
  local name=$1
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

assert_false() {
  local name=$1
  shift
  if "$@"; then fail "$name"; else pass "$name"; fi
}

assert_contains() {
  local name=$1 file=$2 pattern=$3
  if grep -Eq "$pattern" "$file"; then pass "$name"; else fail "$name"; fi
}

assert_not_contains() {
  local name=$1 file=$2 pattern=$3
  if grep -Eq "$pattern" "$file"; then fail "$name"; else pass "$name"; fi
}

assert_true  "valid short hostname" validate_hostname "kali-lab-01"
assert_true  "valid FQDN hostname" validate_hostname "kali-lab-01.example.test"
assert_false "hostname rejects underscore" validate_hostname "kali_lab"
assert_false "hostname rejects leading hyphen" validate_hostname "-kali"
assert_false "hostname rejects empty label" validate_hostname "kali..lab"

assert_true  "valid username" validate_username "devuser"
assert_true  "valid service-style username" validate_username "lab_user-2"
assert_false "username rejects uppercase" validate_username "DevUser"
assert_false "username rejects shell punctuation" validate_username "user;id"

assert_true  "valid apt package name" validate_package_name "libssl-dev:amd64"
assert_false "package rejects command separator" validate_package_name "git;id"

assert_true  "valid systemd service unit" validate_service_unit "ssh@lab.service"
assert_false "service rejects option-like name" validate_service_unit "--now.service"
assert_false "service requires .service suffix" validate_service_unit "ssh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/hosts" <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 kali # VM hostname
::1 localhost ip6-localhost ip6-loopback
HOSTS

rewrite_hosts_file "$work/hosts" "$work/transition" kali red-team-vm transition
rewrite_hosts_file "$work/transition" "$work/final" kali red-team-vm final

assert_contains "transition keeps old hostname" "$work/transition" '^127\.0\.1\.1[[:space:]]+kali[[:space:]]+red-team-vm([[:space:]]+#.*)?$'
assert_contains "transition preserves comment" "$work/transition" '# VM hostname$'
assert_contains "final contains new hostname" "$work/final" '^127\.0\.1\.1[[:space:]]+red-team-vm([[:space:]]+#.*)?$'
assert_not_contains "final removes old hostname token" "$work/final" '(^|[[:space:]])kali([[:space:]]|$)'
assert_contains "final preserves localhost" "$work/final" '^127\.0\.0\.1[[:space:]]+localhost$'

cat > "$work/no-127-1-1" <<'HOSTS'
127.0.0.1 localhost kali
::1 localhost ip6-localhost
HOSTS
rewrite_hosts_file "$work/no-127-1-1" "$work/generated" kali lab-vm final
assert_contains "adds Debian 127.0.1.1 mapping when absent" "$work/generated" '^127\.0\.1\.1[[:space:]]+lab-vm$'
assert_not_contains "removes old hostname from other loopback row" "$work/generated" '^127\.0\.0\.1.*[[:space:]]kali([[:space:]]|$)'


cat > "$work/protected-localhost" <<'HOSTS'
127.0.0.1 localhost LOCALHOST.localdomain
127.0.1.1 KaLi
::1 localhost ip6-localhost ip6-loopback
HOSTS
rewrite_hosts_file "$work/protected-localhost" "$work/protected-result" LOCALHOST lab-vm final
assert_contains "never removes protected localhost token" "$work/protected-result" '^127\.0\.0\.1[[:space:]]+localhost[[:space:]]+LOCALHOST\.localdomain$'
assert_contains "protected-name edge case still writes new hostname" "$work/protected-result" '^127\.0\.1\.1[[:space:]]+lab-vm[[:space:]]+KaLi$'

cat > "$work/case-hostname" <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 KaLi old-alias
HOSTS
rewrite_hosts_file "$work/case-hostname" "$work/case-result" kali red-team-vm final
assert_not_contains "old hostname removal is case-insensitive" "$work/case-result" '(^|[[:space:]])KaLi([[:space:]]|$)'
assert_contains "final rewrite preserves unrelated aliases" "$work/case-result" '^127\.0\.1\.1[[:space:]]+red-team-vm[[:space:]]+old-alias$'

choice=$(printf '2\n' | choose_one "test menu" one two three 2>/dev/null)
if [[ $choice == 2 ]]; then
  pass "menu selection returns the chosen index"
else
  fail "menu selection returns the chosen index"
fi

items=(git curl git jq curl)
dedupe_array items
if [[ ${items[*]} == $'git\ncurl\njq' ]]; then
  pass "deduplicates package arrays while preserving order"
else
  fail "deduplicates package arrays while preserving order"
fi

printf '\n%d passed; %d failed\n' "$passes" "$failures"
(( failures == 0 ))
