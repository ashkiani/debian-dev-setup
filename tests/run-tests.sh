#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

echo '== Bash syntax =='
for file in vm-setup-v2.sh ai-sandbox-setup.sh pi-hardening.sh config-v2.example.sh tests/*.sh; do
  bash -n "$file"
done
echo 'PASS: Bash syntax'

echo
echo '== workflow behavior =='
./tests/test-vm-setup-v2.sh

echo
echo '== compatibility checks =='
./tests/test-legacy-checksums.sh

echo
echo '== standalone follow-ups =='
./tests/test-follow-ups.sh
echo
echo 'All repository tests passed.'
