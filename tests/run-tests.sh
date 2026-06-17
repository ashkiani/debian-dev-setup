#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

echo '== Bash syntax =='
bash -n vm-setup-v2.sh config-v2.example.sh tests/*.sh
echo 'PASS: Bash syntax'

echo
echo '== workflow behavior =='
./tests/test-vm-setup-v2.sh

echo
echo '== compatibility checks =='
./tests/test-legacy-checksums.sh

echo
echo 'All repository tests passed.'
