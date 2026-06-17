#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
expected_bootstrap='b33c3ce364f77ed0cf7c3fa0f47b2d042367de48cd7cf4992cfb1cdc123e550f'
expected_dev='47ab5333e1da1871894968c8be182439f2e48e2e040eb06d9f28597b2745dd94'
actual_bootstrap=$(sha256sum bootstrap-system.sh | awk '{print $1}')
actual_dev=$(sha256sum debian-dev-setup.sh | awk '{print $1}')
[[ $actual_bootstrap == "$expected_bootstrap" ]] || { echo 'bootstrap-system.sh changed' >&2; exit 1; }
[[ $actual_dev == "$expected_dev" ]] || { echo 'debian-dev-setup.sh changed' >&2; exit 1; }
echo 'PASS: original script checksums match'
