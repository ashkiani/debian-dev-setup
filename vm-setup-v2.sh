#!/usr/bin/env bash
# ============================================================================
# Script Name: vm-setup-v2.sh
# Description: Offline-first, resumable setup for Debian-based virtual machines
# Author: Siavash Ashkiani
# License: MIT
#
# Features:
#   * Offline-first system bootstrap
#   * Safe hostname changes
#   * Creation and validation of a new sudo user
#   * SSH key generation
#   * Service and listening-socket inventory
#   * Resumable post-login configuration
#   * Network reconnection assistance
#   * System maintenance and modular package profiles
#   * Optional firewall, logging, auditing, and baseline reporting
# ============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="2.0.1"
readonly PROJECT_NAME="debian-dev-setup"
readonly INSTALL_DIR="/usr/local/lib/${PROJECT_NAME}/v2"
readonly INSTALLED_SCRIPT="${INSTALL_DIR}/vm-setup-v2.sh"
readonly STATE_DIR="/var/lib/${PROJECT_NAME}/v2"
readonly STATE_FILE="${STATE_DIR}/state.env"
readonly REPORT_DIR="/var/log/${PROJECT_NAME}"
readonly DEFAULT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/${PROJECT_NAME}/config-v2.sh"
readonly VSCODE_DEB_URL="https://go.microsoft.com/fwlink/?LinkID=760868"
readonly MICROSOFT_SIGNING_KEY_FINGERPRINT="BC528686B50D79E339D3721CEB3E94ADBE1229CF"

DRY_RUN=0
CONFIG_FILE=""
COMMAND=""

# Package profiles can be replaced or extended in config-v2.sh.
PACKAGE_PROFILE_ESSENTIALS=(
  ca-certificates curl wget gnupg git jq unzip zip openssh-client
)
PACKAGE_PROFILE_BUILD=(
  build-essential cmake ninja-build pkg-config gdb
)
PACKAGE_PROFILE_PYTHON=(
  python3 python3-pip python3-venv pipx
)
PACKAGE_PROFILE_NODE=(
  nodejs npm
)
PACKAGE_PROFILE_JAVA=(
  default-jdk
)
PACKAGE_PROFILE_CONTAINERS=(
  podman buildah
)
CUSTOM_PROFILE_NAME="Custom package profile"
PACKAGE_PROFILE_CUSTOM=()

# Services shown in the guided review when present. Nothing is disabled by
# default. Add names in config-v2.sh to extend this list.
SERVICE_REVIEW_CANDIDATES=(
  bluetooth.service
  cups.service
  cups-browsed.service
  avahi-daemon.service
  ModemManager.service
  pcscd.service
  apache2.service
  nginx.service
  postgresql.service
  mysql.service
  mariadb.service
  ssh.service
  tor.service
)

# ---------- presentation ----------------------------------------------------

if [[ -t 1 ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_BOLD=$'\033[1m'
  readonly C_BLUE=$'\033[34m'
  readonly C_GREEN=$'\033[32m'
  readonly C_YELLOW=$'\033[33m'
  readonly C_RED=$'\033[31m'
else
  readonly C_RESET="" C_BOLD="" C_BLUE="" C_GREEN="" C_YELLOW="" C_RED=""
fi

info()    { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
success() { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()     { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
section() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_RESET"; }

on_error() {
  local exit_code=$?
  local line_no=${BASH_LINENO[0]:-unknown}
  printf '%s[FAIL]%s Command failed near line %s (exit %s).\n' \
    "$C_RED" "$C_RESET" "$line_no" "$exit_code" >&2
  printf 'Re-run with the same subcommand after correcting the problem; completed actions are designed to be idempotent.\n' >&2
  exit "$exit_code"
}
trap on_error ERR

usage() {
  cat <<'USAGE'
Usage:
  vm-setup-v2.sh [global options] <command>

Commands:
  start       Begin the offline-first VM bootstrap as the current login user.
  continue    Continue after logging in as the newly created user.
  dev         Run only online maintenance and optional developer-tool setup.
  services    Inventory services and optionally disable selected services.
  security    Offer optional firewall, persistent logging, auditd, and ClamAV.
  baseline    Save a read-only system inventory for later comparison.
  status      Show saved workflow state and current system checks.
  help        Show this help.

Global options:
  --config FILE   Source an optional Bash configuration file.
  --dry-run       Print privileged/destructive commands instead of running them.
  --version       Print the script version.

Important:
  Run this script as a normal login user, not directly as root. It requests
  sudo only for the operations that need it.
USAGE
}

# ---------- generic helpers -------------------------------------------------

quote_cmd() {
  local arg
  printf '  '
  for arg in "$@"; do printf '%q ' "$arg"; done
  printf '\n'
}

run() {
  if (( DRY_RUN )); then
    quote_cmd "$@"
  else
    "$@"
  fi
}

run_root() {
  if (( DRY_RUN )); then
    quote_cmd sudo -- "$@"
  else
    sudo -- "$@"
  fi
}

run_as_user() {
  local user=$1
  shift
  if (( DRY_RUN )); then
    quote_cmd sudo -H -u "$user" -- "$@"
  else
    sudo -H -u "$user" -- "$@"
  fi
}

pause() {
  local message=${1:-"Press Enter to continue..."}
  read -r -p "$message" _
}

ask_yes_no() {
  local prompt=$1
  local default=${2:-N}
  local suffix answer
  if [[ $default == Y ]]; then suffix='[Y/n]'; else suffix='[y/N]'; fi
  while true; do
    read -r -p "$prompt $suffix: " answer
    answer=${answer:-$default}
    case "$answer" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) warn "Please answer yes or no." ;;
    esac
  done
}

choose_one() {
  local prompt=$1
  shift
  local options=("$@")
  local choice i
  printf '%s\n' "$prompt" >&2
  for i in "${!options[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${options[$i]}" >&2
  done
  while true; do
    read -r -p "Choose [1-${#options[@]}]: " choice
    if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      printf '%s' "$choice"
      return 0
    fi
    warn "Enter a number from 1 to ${#options[@]}."
  done
}

require_normal_user() {
  (( EUID != 0 )) || die "Run this as your normal login user, without sudo. The script will request sudo when needed."
}

require_sudo() {
  command -v sudo >/dev/null 2>&1 || die "sudo is required for this workflow."
  if (( DRY_RUN )); then
    info "Dry-run: skipping sudo credential validation."
  else
    sudo -v || die "Could not obtain sudo privileges."
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

load_config() {
  local candidate=""
  if [[ -n $CONFIG_FILE ]]; then
    candidate=$CONFIG_FILE
  elif [[ -f $DEFAULT_CONFIG ]]; then
    candidate=$DEFAULT_CONFIG
  fi

  if [[ -n $candidate ]]; then
    [[ -r $candidate ]] || die "Configuration file is not readable: $candidate"
    # This file is intentionally Bash: it can extend arrays and define profiles.
    # Only source a configuration file you trust.
    # shellcheck disable=SC1090
    source "$candidate"
    info "Loaded configuration: $candidate"
  fi
}

os_release_value() {
  local key=$1
  [[ -r /etc/os-release ]] || return 1
  (
    # shellcheck disable=SC1091
    source /etc/os-release
    printf '%s' "${!key:-}"
  )
}

ensure_debian_family() {
  local id id_like
  id=$(os_release_value ID || true)
  id_like=$(os_release_value ID_LIKE || true)
  case " $id $id_like " in
    *" debian "*|*" ubuntu "*) ;;
    *) die "This script supports Debian-derived systems. Detected ID='$id', ID_LIKE='$id_like'." ;;
  esac
}

validate_hostname() {
  local value=$1 label
  local -a labels
  [[ ${#value} -le 253 ]] || return 1
  [[ $value != .* && $value != *. && $value != *..* ]] || return 1
  IFS='.' read -r -a labels <<< "$value"
  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
    [[ $label =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

validate_username() {
  local value=$1
  [[ ${#value} -le 32 ]] || return 1
  [[ $value =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

validate_package_name() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9.+:-]*$ ]]
}

validate_service_unit() {
  [[ $1 =~ ^[A-Za-z0-9_][A-Za-z0-9_.@:-]*\.service$ ]]
}

current_static_hostname() {
  hostnamectl --static 2>/dev/null || hostname
}

state_get() {
  local key=$1
  [[ -r $STATE_FILE ]] || return 1
  awk -F= -v k="$key" '$1 == k {sub(/^[^=]*=/, ""); print; exit}' "$STATE_FILE"
}

state_set_many() {
  local tmp key value pair
  if (( DRY_RUN )); then
    info "Dry-run: would update state file $STATE_FILE"
    for pair in "$@"; do printf '  %s\n' "$pair"; done
    return 0
  fi

  tmp=$(mktemp)
  if [[ -r $STATE_FILE ]]; then sudo cat "$STATE_FILE" > "$tmp"; fi

  for pair in "$@"; do
    key=${pair%%=*}
    value=${pair#*=}
    awk -F= -v k="$key" '$1 != k' "$tmp" > "${tmp}.next"
    mv "${tmp}.next" "$tmp"
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  done

  sudo install -d -m 0755 "$STATE_DIR"
  sudo install -m 0644 "$tmp" "$STATE_FILE"
  rm -f "$tmp"
}

install_local_copy() {
  local source_path
  source_path=$(readlink -f "${BASH_SOURCE[0]}")
  [[ -f $source_path ]] || die "The script must be saved as a local file before it can manage networking."

  run_root install -d -m 0755 "$INSTALL_DIR"
  run_root install -m 0755 "$source_path" "$INSTALLED_SCRIPT"
  success "Installed a resumable local copy at $INSTALLED_SCRIPT"
}

# ---------- network handling ------------------------------------------------

has_default_route() {
  ip route show default 2>/dev/null | grep -q '^default '
}

https_probe() {
  local url=${1:-https://deb.debian.org/}
  if command_exists curl; then
    curl -fsSI --connect-timeout 4 --max-time 8 "$url" >/dev/null 2>&1
  elif command_exists wget; then
    wget -q --spider --timeout=8 "$url" >/dev/null 2>&1
  elif command_exists timeout; then
    # Minimal installations may have neither curl nor wget before the first
    # online apt operation. Bash /dev/tcp still lets us verify DNS + TCP/443.
    getent ahosts deb.debian.org >/dev/null 2>&1 &&
      timeout 5 bash -c 'exec 3<>/dev/tcp/deb.debian.org/443' >/dev/null 2>&1
  else
    # Last-resort signal: route plus DNS. apt-get remains the authoritative test.
    has_default_route && getent ahosts deb.debian.org >/dev/null 2>&1
  fi
}

network_report() {
  local nm="unavailable" route="absent" dns="failed" https="failed"
  if command_exists nmcli; then
    nm=$(nmcli -t -f STATE general 2>/dev/null || printf 'unknown')
  fi
  has_default_route && route="present"
  getent ahosts deb.debian.org >/dev/null 2>&1 && dns="working"
  if https_probe; then
    https="working"
  fi

  printf 'NetworkManager: %s\n' "$nm"
  printf 'Default route:   %s\n' "$route"
  printf 'DNS resolution:  %s\n' "$dns"
  printf 'HTTPS probe:     %s\n' "$https"
}

prepare_offline_state() {
  section "Step 1: disconnect or verify networking"
  network_report
  printf '\n'

  local choice
  choice=$(choose_one "How should networking be handled?" \
    "I already disconnected the VM adapter; only verify and continue" \
    "Disable NetworkManager networking now (reversible)" \
    "Pause while I disconnect the virtual adapter manually" \
    "Continue without disconnecting networking")

  case "$choice" in
    1)
      if has_default_route; then
        warn "A default route still exists. The VM may still have network access."
        ask_yes_no "Continue anyway?" N || die "Disconnect networking, then run start again."
      else
        success "No default route detected."
      fi
      state_set_many "NETWORK_DISCONNECT_METHOD=external"
      ;;
    2)
      command_exists nmcli || die "nmcli is not installed; use the hypervisor/manual option instead."
      run_root nmcli networking off
      sleep 1
      network_report
      if has_default_route; then
        warn "A default route remains after nmcli networking off. Verify the VM adapter manually."
      fi
      state_set_many "NETWORK_DISCONNECT_METHOD=networkmanager"
      ;;
    3)
      pause "Disconnect the VM's network adapter in the hypervisor, then press Enter..."
      network_report
      if has_default_route; then
        warn "A default route still exists."
        ask_yes_no "Continue anyway?" N || die "Networking was not confirmed disconnected."
      fi
      state_set_many "NETWORK_DISCONNECT_METHOD=external"
      ;;
    4)
      warn "Continuing while networking may be available."
      state_set_many "NETWORK_DISCONNECT_METHOD=none"
      ;;
  esac
}

reconnect_network() {
  section "Step 8: reconnect networking"
  local method
  method=$(state_get NETWORK_DISCONNECT_METHOD || printf 'unknown')

  case "$method" in
    networkmanager)
      if command_exists nmcli; then
        run_root nmcli networking on
        run_root nmcli radio wifi on || true
        info "NetworkManager networking was re-enabled."
      else
        warn "nmcli is no longer available; reconnect networking manually."
      fi
      ;;
    external)
      pause "Reconnect the VM's virtual network adapter in the hypervisor, then press Enter..."
      ;;
    none)
      info "The script did not disable networking."
      ;;
    *)
      warn "The saved disconnect method is unknown. Reconnect the VM adapter manually if needed."
      pause
      ;;
  esac

  if command_exists nmcli; then
    nmcli device status || true
  fi

  local attempts=0
  while (( attempts < 3 )); do
    if https_probe; then
      success "Internet connectivity confirmed over HTTPS."
      state_set_many "NETWORK_RECONNECTED=1"
      return 0
    fi
    ((attempts += 1))
    warn "Internet connectivity is not yet confirmed."
    network_report
    (( attempts < 3 )) || break
    pause "Fix/reconnect networking, then press Enter to retry..."
  done

  die "Internet access is required for the online phase. Reconnect it and run: $INSTALLED_SCRIPT continue"
}

# ---------- hostname migration ---------------------------------------------

rewrite_hosts_file() {
  local input=$1 output=$2 old_host=$3 new_host=$4 mode=$5
  awk -v old="$old_host" -v new="$new_host" -v mode="$mode" '
    function same_name(a, b) { return tolower(a) == tolower(b) }
    function is_loopback(ip) { return ip == "127.0.0.1" || ip == "127.0.1.1" || ip == "::1" }
    function is_protected_name(name,    lower) {
      lower = tolower(name)
      return lower == "localhost" || lower == "localhost.localdomain" || lower == "ip6-localhost" || lower == "ip6-loopback"
    }
    function removable_old_name(name) { return same_name(name, old) && !is_protected_name(name) }
    function emit_127_line(    i, token, out, seen_new, seen_old) {
      out = "127.0.1.1"
      seen_new = 0
      seen_old = 0
      for (i = 2; i <= field_count; i++) {
        token = fields[i]
        if (token == "") continue
        if (same_name(token, new)) seen_new = 1
        if (same_name(token, old)) seen_old = 1
      }

      if (mode == "transition") {
        if (!seen_old && old != "") out = out "\t" old
        for (i = 2; i <= field_count; i++) {
          token = fields[i]
          if (token != "" && !same_name(token, new)) out = out "\t" token
        }
        out = out "\t" new
      } else {
        out = out "\t" new
        for (i = 2; i <= field_count; i++) {
          token = fields[i]
          if (token != "" && !removable_old_name(token) && !same_name(token, new)) out = out "\t" token
        }
      }
      print out comment_suffix
    }
    {
      raw = $0
      comment_suffix = ""
      comment_pos = index(raw, "#")
      if (comment_pos > 0) {
        comment_suffix = " " substr(raw, comment_pos)
        raw = substr(raw, 1, comment_pos - 1)
      }
      field_count = split(raw, fields, /[[:space:]]+/)
      first = ""
      for (i = 1; i <= field_count; i++) {
        if (fields[i] != "") { first = fields[i]; break }
      }

      if (first == "127.0.1.1") {
        # Normalize fields so the address is element 1.
        delete normalized
        n = 1
        normalized[1] = "127.0.1.1"
        for (i = 1; i <= field_count; i++) {
          if (fields[i] != "" && fields[i] != "127.0.1.1") normalized[++n] = fields[i]
        }
        delete fields
        for (i = 1; i <= n; i++) fields[i] = normalized[i]
        field_count = n
        emit_127_line()
        found_127 = 1
        next
      }

      if (mode == "final" && is_loopback(first)) {
        out = first
        for (i = 1; i <= field_count; i++) {
          token = fields[i]
          if (token != "" && token != first && !removable_old_name(token)) out = out "\t" token
        }
        print out comment_suffix
        next
      }

      print $0
    }
    END {
      if (!found_127) {
        if (mode == "transition" && old != "") print "127.0.1.1\t" old "\t" new
        else print "127.0.1.1\t" new
      }
    }
  ' "$input" > "$output"
}

change_hostname_safely() {
  section "Step 2: hostname"
  local old_host new_host temp_transition temp_final backup_suffix
  old_host=$(current_static_hostname)
  printf 'Current hostname: %s\n' "$old_host"

  if ! ask_yes_no "Change the hostname?" Y; then
    state_set_many "OLD_HOSTNAME=$old_host" "NEW_HOSTNAME=$old_host" "HOSTNAME_CHANGED=0"
    return 0
  fi

  while true; do
    read -r -p "New hostname: " new_host
    if validate_hostname "$new_host"; then break; fi
    warn "Use valid DNS-style labels: letters, digits, and hyphens; no spaces or underscores."
  done

  if [[ ${new_host,,} == ${old_host,,} ]]; then
    info "The hostname is already '$new_host'."
    state_set_many "OLD_HOSTNAME=$old_host" "NEW_HOSTNAME=$new_host" "HOSTNAME_CHANGED=0"
    return 0
  fi

  temp_transition=$(mktemp)
  temp_final=$(mktemp)
  backup_suffix=$(date +%Y%m%d-%H%M%S)
  rewrite_hosts_file /etc/hosts "$temp_transition" "$old_host" "$new_host" transition
  rewrite_hosts_file "$temp_transition" "$temp_final" "$old_host" "$new_host" final

  info "Planned transitional /etc/hosts entry keeps '$old_host' resolvable while hostnamectl runs."
  if (( DRY_RUN )); then
    printf '%s\n' '--- transitional /etc/hosts ---'
    cat "$temp_transition"
    printf '%s\n' '--- final /etc/hosts ---'
    cat "$temp_final"
  else
    sudo cp -a /etc/hosts "/etc/hosts.pre-${PROJECT_NAME}-${backup_suffix}"
    [[ ! -e /etc/hostname ]] || sudo cp -a /etc/hostname "/etc/hostname.pre-${PROJECT_NAME}-${backup_suffix}"
    sudo install -m 0644 "$temp_transition" /etc/hosts
    sudo hostnamectl set-hostname "$new_host"
    sudo install -m 0644 "$temp_final" /etc/hosts
  fi
  rm -f "$temp_transition" "$temp_final"

  if (( ! DRY_RUN )); then
    [[ $(current_static_hostname) == "$new_host" ]] || die "hostnamectl did not retain the requested hostname."
    getent hosts "$new_host" >/dev/null 2>&1 || warn "The new hostname is not currently resolved by getent; inspect /etc/hosts."
    sudo -n true || die "sudo validation failed after the hostname change. Restore the saved /etc/hosts backup from a root console."
  fi

  state_set_many \
    "OLD_HOSTNAME=$old_host" \
    "NEW_HOSTNAME=$new_host" \
    "HOSTNAME_CHANGED=1" \
    "HOSTS_BACKUP_SUFFIX=$backup_suffix"
  success "Hostname changed to '$new_host' without dropping the old local mapping mid-operation."
}

# ---------- user and key setup ---------------------------------------------

create_replacement_user() {
  section "Steps 3-4: create the replacement sudo user"
  local old_user new_user old_groups group_csv
  old_user=$(id -un)
  printf 'Current login user: %s\n' "$old_user"

  if ! ask_yes_no "Create or configure a replacement user?" Y; then
    warn "The current user will not be locked by this workflow."
    state_set_many "OLD_USER=$old_user" "NEW_USER=$old_user" "REPLACEMENT_USER_CREATED=0"
    return 0
  fi

  while true; do
    read -r -p "New username: " new_user
    if validate_username "$new_user"; then break; fi
    warn "Use a Debian-style username: lowercase letters/digits plus _, -, or a final $."
  done

  [[ $new_user != "$old_user" ]] || die "The replacement username must differ from the current user."

  if id "$new_user" >/dev/null 2>&1; then
    info "User '$new_user' already exists; creation will be skipped."
  else
    run_root adduser "$new_user"
  fi

  if (( ! DRY_RUN )); then
    local new_uid uid_min new_shell
    new_uid=$(id -u "$new_user")
    uid_min=$(awk '$1 == "UID_MIN" {print $2; exit}' /etc/login.defs 2>/dev/null || true)
    uid_min=${uid_min:-1000}
    new_shell=$(getent passwd "$new_user" | cut -d: -f7)
    (( new_uid != 0 && new_uid >= uid_min )) || die "'$new_user' is not a regular login account (UID $new_uid; UID_MIN $uid_min)."
    case "$new_shell" in
      */nologin|*/false) die "'$new_user' has a non-login shell: $new_shell" ;;
    esac
  fi

  run_root usermod -aG sudo "$new_user"
  if (( ! DRY_RUN )); then
    sudo visudo -cf /etc/sudoers >/dev/null
  fi
  success "'$new_user' belongs to the sudo group."

  old_groups=$(id -nG "$old_user" | tr ' ' '\n' | grep -vxF "$old_user" | grep -vxF sudo | paste -sd, - || true)
  if [[ -n $old_groups ]]; then
    printf 'Other supplementary groups held by %s: %s\n' "$old_user" "$old_groups"
    if ask_yes_no "Copy these supplementary groups to '$new_user'?" N; then
      group_csv=$old_groups
      run_root usermod -aG "$group_csv" "$new_user"
      success "Copied selected group memberships."
    fi
  fi

  local old_shell
  old_shell=$(getent passwd "$old_user" | cut -d: -f7)
  state_set_many \
    "OLD_USER=$old_user" \
    "NEW_USER=$new_user" \
    "OLD_USER_ORIGINAL_SHELL=$old_shell" \
    "REPLACEMENT_USER_CREATED=1"

  info "The original account remains enabled. Account changes are offered only after '$new_user' logs in and passes sudo validation."
}

generate_ssh_key() {
  section "Step 5: SSH key pair"
  local target_user choice key_type bits key_file home_dir host comment
  target_user=$(state_get NEW_USER || id -un)
  host=$(state_get NEW_HOSTNAME || current_static_hostname)
  home_dir=$(getent passwd "$target_user" | cut -d: -f6)
  [[ -n $home_dir ]] || die "Could not determine the home directory for '$target_user'."

  if ! command_exists ssh-keygen; then
    warn "ssh-keygen is unavailable while the VM is offline. Key generation will be offered again after openssh-client can be installed online."
    state_set_many "SSH_KEY_GENERATED=0" "SSH_KEY_PENDING=1"
    return 0
  fi

  choice=$(choose_one "Choose an SSH key option for '$target_user':" \
    "Ed25519 (recommended)" \
    "ECDSA P-521" \
    "RSA 4096 (for compatibility with older systems)" \
    "Skip SSH key generation")

  case "$choice" in
    1) key_type=ed25519; bits=""; key_file="$home_dir/.ssh/id_ed25519" ;;
    2) key_type=ecdsa; bits=521; key_file="$home_dir/.ssh/id_ecdsa" ;;
    3) key_type=rsa; bits=4096; key_file="$home_dir/.ssh/id_rsa" ;;
    4) state_set_many "SSH_KEY_GENERATED=0"; return 0 ;;
  esac

  if [[ -e $key_file || -e ${key_file}.pub ]]; then
    warn "A key already exists at $key_file."
    if ! ask_yes_no "Generate another key with a custom filename?" N; then
      state_set_many "SSH_KEY_GENERATED=0" "SSH_KEY_PATH=$key_file"
      return 0
    fi

    local key_name
    while true; do
      read -r -p "New key filename inside $home_dir/.ssh [id_${key_type}_vm]: " key_name
      key_name=${key_name:-"id_${key_type}_vm"}
      if [[ ! $key_name =~ ^[A-Za-z0-9._-]+$ ]]; then
        warn "Use a filename only; slashes and shell metacharacters are not allowed."
        continue
      fi
      key_file="$home_dir/.ssh/$key_name"
      if [[ -e $key_file || -e ${key_file}.pub ]]; then
        warn "That key filename already exists."
        continue
      fi
      break
    done
  fi

  comment="${target_user}@${host}"
  run_root install -d -m 0700 -o "$target_user" -g "$(id -gn "$target_user")" "$home_dir/.ssh"

  local cmd=(ssh-keygen -t "$key_type" -a 100 -C "$comment" -f "$key_file")
  [[ -z $bits ]] || cmd+=( -b "$bits" )
  info "ssh-keygen will ask for a passphrase. A passphrase is strongly recommended."
  run_as_user "$target_user" "${cmd[@]}"

  state_set_many "SSH_KEY_GENERATED=1" "SSH_KEY_PENDING=0" "SSH_KEY_PATH=$key_file" "SSH_KEY_TYPE=$key_type"
  success "SSH key created for '$target_user': ${key_file}.pub"
}

# ---------- service review --------------------------------------------------

service_present() {
  local unit=$1
  validate_service_unit "$unit" || return 1
  systemctl cat -- "$unit" >/dev/null 2>&1 || systemctl list-unit-files --no-legend -- "$unit" 2>/dev/null | grep -q .
}

service_enabled_or_active() {
  local unit=$1
  systemctl is-enabled -- "$unit" >/dev/null 2>&1 || systemctl is-active -- "$unit" >/dev/null 2>&1
}

save_service_report() {
  local report_tmp stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  report_tmp=$(mktemp)
  {
    printf 'Generated: %s\n\n' "$(date --iso-8601=seconds)"
    printf '%s\n' '=== Enabled service unit files ==='
    systemctl list-unit-files --type=service --state=enabled --no-pager || true
    printf '\n%s\n' '=== Running services ==='
    systemctl list-units --type=service --state=running --no-pager || true
    printf '\n%s\n' '=== Listening sockets ==='
    if command_exists ss; then run_root ss -lntup || true; else printf 'ss command unavailable\n'; fi
  } > "$report_tmp"

  if (( DRY_RUN )); then
    info "Dry-run: would save service report to $REPORT_DIR/services-$stamp.txt"
    rm -f "$report_tmp"
  else
    sudo install -d -m 0755 "$REPORT_DIR"
    sudo install -m 0644 "$report_tmp" "$REPORT_DIR/services-$stamp.txt"
    rm -f "$report_tmp"
    success "Service report saved to $REPORT_DIR/services-$stamp.txt"
  fi
}

review_services() {
  section "Step 6: service inventory and opt-in disabling"
  command_exists systemctl || die "systemctl is required for service review."
  save_service_report

  printf '\nEnabled services:\n'
  systemctl list-unit-files --type=service --state=enabled --no-pager || true
  printf '\nRunning services:\n'
  systemctl list-units --type=service --state=running --no-pager || true

  if ! ask_yes_no "Review common optional services one by one?" N; then
    return 0
  fi

  local unit description
  for unit in "${SERVICE_REVIEW_CANDIDATES[@]}"; do
    service_present "$unit" || continue
    service_enabled_or_active "$unit" || continue
    description=$(systemctl show -p Description --value -- "$unit" 2>/dev/null || true)
    printf '\n%s — %s\n' "$unit" "${description:-No description available}"
    systemctl status --no-pager --lines=3 -- "$unit" 2>/dev/null || true

    if [[ $unit == ssh.service && -n ${SSH_CONNECTION:-} ]]; then
      warn "You appear to be connected over SSH. Disabling ssh.service could disconnect you."
    fi

    if ask_yes_no "Disable and stop $unit?" N; then
      run_root systemctl disable --now -- "$unit"
      success "Disabled $unit"
    fi
  done

  if ask_yes_no "Enter another service unit to review manually?" N; then
    while true; do
      read -r -p "Service unit (blank to finish): " unit
      [[ -n $unit ]] || break
      [[ $unit == *.service ]] || unit="${unit}.service"
      if ! validate_service_unit "$unit"; then
        warn "Use a conventional service unit name ending in .service; option-like or escaped names are not accepted here."
        continue
      fi
      if ! service_present "$unit"; then
        warn "No installed unit named '$unit'."
        continue
      fi
      systemctl status --no-pager -- "$unit" || true
      if ask_yes_no "Disable and stop $unit?" N; then
        run_root systemctl disable --now -- "$unit"
      fi
    done
  fi
}

# ---------- desktop configuration ------------------------------------------

configure_gnome_power() {
  local lock_minutes suspend_minutes lock_seconds suspend_seconds
  read -r -p "Lock the session after how many idle minutes? [15]: " lock_minutes
  lock_minutes=${lock_minutes:-15}
  [[ $lock_minutes =~ ^[0-9]+$ ]] || { warn "Invalid value; skipping GNOME settings."; return; }
  lock_seconds=$((lock_minutes * 60))

  read -r -p "Suspend on AC after how many idle minutes? Use 0 for never. [0]: " suspend_minutes
  suspend_minutes=${suspend_minutes:-0}
  [[ $suspend_minutes =~ ^[0-9]+$ ]] || { warn "Invalid value; skipping GNOME settings."; return; }
  suspend_seconds=$((suspend_minutes * 60))

  gsettings set org.gnome.desktop.session idle-delay "uint32 $lock_seconds"
  gsettings set org.gnome.desktop.screensaver lock-enabled true
  gsettings set org.gnome.desktop.screensaver lock-delay "uint32 0"
  if (( suspend_seconds == 0 )); then
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
  else
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout "$suspend_seconds"
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'suspend'
  fi
  success "GNOME idle-lock and AC sleep settings updated for $(id -un)."
}

configure_desktop_settings() {
  section "Step 7: desktop lock and sleep settings"
  local desktop=${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}
  printf 'Detected desktop/session: %s\n' "$desktop"

  case "${desktop,,}" in
    *xfce*)
      info "Xfce stores these settings per user and releases occasionally rename internal properties."
      info "This script opens the supported settings panels instead of writing undocumented configuration keys."
      if ask_yes_no "Open Xfce power-manager settings now?" Y; then
        if command_exists xfce4-power-manager; then
          xfce4-power-manager -c || true
        else
          warn "xfce4-power-manager is not installed."
        fi
      fi
      if ask_yes_no "Open Xfce screensaver/lock settings now?" Y; then
        if command_exists xfce4-screensaver-preferences; then
          xfce4-screensaver-preferences || true
        elif command_exists xfce4-settings-manager; then
          xfce4-settings-manager || true
        else
          warn "No Xfce screensaver settings command was found."
        fi
      fi
      ;;
    *gnome*)
      if command_exists gsettings && ask_yes_no "Configure GNOME idle lock and AC sleep from this script?" Y; then
        configure_gnome_power
      else
        info "Open Settings > Power and Settings > Privacy > Screen Lock manually."
      fi
      ;;
    *kde*|*plasma*)
      info "KDE/Plasma settings differ by version; the script will use the supported GUI."
      if ask_yes_no "Open KDE System Settings now?" Y; then
        if command_exists systemsettings; then systemsettings || true
        elif command_exists systemsettings5; then systemsettings5 || true
        else warn "KDE System Settings was not found."
        fi
      fi
      ;;
    *)
      warn "Desktop settings were not automated for '$desktop'. Configure screen locking and sleep manually."
      ;;
  esac
}

# ---------- old-account finalization ---------------------------------------

finalize_old_user() {
  section "Step 4 completion: lock the original account"
  local old_user new_user original_shell choice processes
  old_user=$(state_get OLD_USER || true)
  new_user=$(state_get NEW_USER || true)
  original_shell=$(state_get OLD_USER_ORIGINAL_SHELL || printf '/bin/bash')

  [[ -n $old_user && -n $new_user ]] || { warn "No replacement-user state exists; skipping account lock."; return; }
  if [[ $old_user == "$new_user" ]] || [[ $(state_get REPLACEMENT_USER_CREATED || printf '0') != 1 ]]; then
    info "No separate replacement account was configured; the current account will not be locked."
    return 0
  fi
  [[ $(id -un) == "$new_user" ]] || die "Run continue while logged in as '$new_user', not '$(id -un)'."
  id -nG "$new_user" | tr ' ' '\n' | grep -qx sudo || die "'$new_user' is not in the sudo group."
  require_sudo
  if (( ! DRY_RUN )); then sudo -v; fi
  success "sudo works for '$new_user'."

  processes=$(pgrep -a -u "$old_user" 2>/dev/null || true)
  if [[ -n $processes ]]; then
    warn "The old account still owns running processes:"
    printf '%s\n' "$processes"
    warn "The script will not terminate them automatically."
  fi

  choice=$(choose_one "How should '$old_user' be handled?" \
    "Defer; leave the account unchanged" \
    "Lock password authentication only (SSH keys may still work)" \
    "Disable the account: expire it, lock password, and set nologin shell")

  case "$choice" in
    1)
      state_set_many "OLD_USER_LOCK_MODE=deferred"
      ;;
    2)
      run_root usermod -L "$old_user"
      state_set_many "OLD_USER_LOCK_MODE=password"
      success "Password authentication locked for '$old_user'."
      ;;
    3)
      local nologin=/usr/sbin/nologin
      [[ -x $nologin ]] || nologin=/sbin/nologin
      [[ -x $nologin ]] || die "nologin was not found."
      run_root usermod -L -e 1 -s "$nologin" "$old_user"
      state_set_many "OLD_USER_LOCK_MODE=disabled" "OLD_USER_ORIGINAL_SHELL=$original_shell"
      success "Account '$old_user' was expired, password-locked, and assigned a nologin shell; its home directory was retained."
      ;;
  esac

  cat <<RECOVERY
Recovery from a root console or another sudo account:
  sudo usermod -e '' -U '$old_user'
  sudo usermod -s '$original_shell' '$old_user'
RECOVERY
}

# ---------- package installation -------------------------------------------

append_profile() {
  local -n destination=$1
  shift
  destination+=("$@")
}

dedupe_array() {
  local -n arr=$1
  local -A seen=()
  local item
  local output=()
  for item in "${arr[@]}"; do
    [[ -n $item ]] || continue
    if [[ -z ${seen[$item]+x} ]]; then
      seen[$item]=1
      output+=("$item")
    fi
  done
  arr=("${output[@]}")
}

select_packages() {
  local -n selected=$1
  local custom package
  ask_yes_no "Install essential CLI tools (curl, wget, Git, jq, zip/unzip)?" Y && append_profile selected "${PACKAGE_PROFILE_ESSENTIALS[@]}"
  ask_yes_no "Install C/C++ build and debugging tools?" N && append_profile selected "${PACKAGE_PROFILE_BUILD[@]}"
  ask_yes_no "Install Python development tools?" N && append_profile selected "${PACKAGE_PROFILE_PYTHON[@]}"
  ask_yes_no "Install Node.js and npm from the distribution repositories?" N && append_profile selected "${PACKAGE_PROFILE_NODE[@]}"
  ask_yes_no "Install the default Java Development Kit?" N && append_profile selected "${PACKAGE_PROFILE_JAVA[@]}"
  ask_yes_no "Install Podman and Buildah?" N && append_profile selected "${PACKAGE_PROFILE_CONTAINERS[@]}"
  if (( ${#PACKAGE_PROFILE_CUSTOM[@]} > 0 )); then
    ask_yes_no "Install ${CUSTOM_PROFILE_NAME}?" N && append_profile selected "${PACKAGE_PROFILE_CUSTOM[@]}"
  fi

  read -r -p "Additional apt packages (space-separated, blank for none): " custom
  if [[ -n $custom ]]; then
    # Deliberately split user input on spaces here.
    local old_ifs=$IFS
    local -a custom_packages
    IFS=' '
    read -r -a custom_packages <<< "$custom"
    IFS=$old_ifs
    for package in "${custom_packages[@]}"; do
      if validate_package_name "$package"; then selected+=("$package")
      else warn "Skipping suspicious package name: $package"
      fi
    done
  fi
  dedupe_array selected
}

install_vscode_repo() {
  local arch tmp_key
  arch=$(dpkg --print-architecture)
  case "$arch" in
    amd64|arm64|armhf) ;;
    *) die "Microsoft's documented VS Code apt repository does not list architecture '$arch'." ;;
  esac

  run_root apt-get install -y ca-certificates wget gpg
  if (( DRY_RUN )); then
    info "Dry-run: would download Microsoft's repository signing key and create /etc/apt/sources.list.d/vscode.sources"
    return 0
  fi

  tmp_key=$(mktemp)
  wget -qO "$tmp_key" https://packages.microsoft.com/keys/microsoft.asc
  local actual_fingerprint
  actual_fingerprint=$(gpg --batch --show-keys --with-colons "$tmp_key" | awk -F: '$1 == "fpr" {print $10; exit}')
  if [[ $actual_fingerprint != "$MICROSOFT_SIGNING_KEY_FINGERPRINT" ]]; then
    rm -f "$tmp_key"
    die "Microsoft signing-key fingerprint mismatch. Expected $MICROSOFT_SIGNING_KEY_FINGERPRINT, got ${actual_fingerprint:-none}."
  fi
  info "Verified Microsoft repository signing-key fingerprint: $actual_fingerprint"
  gpg --batch --quiet --dearmor --output "${tmp_key}.gpg" "$tmp_key"
  sudo install -m 0644 "${tmp_key}.gpg" /usr/share/keyrings/microsoft.gpg
  rm -f "$tmp_key" "${tmp_key}.gpg"

  sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null <<EOF_SOURCES
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: $arch
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF_SOURCES

  sudo apt-get update
  sudo apt-get install -y code
  success "VS Code installed from Microsoft's apt repository."
}

install_vscode_deb() {
  local tmp_deb arch
  arch=$(dpkg --print-architecture)
  [[ $arch == amd64 ]] || die "LinkID=760868 is the x64 .deb redirect; use the Microsoft apt-repository option on '$arch'."
  tmp_deb=$(mktemp --suffix=.deb)
  run_root apt-get install -y ca-certificates curl
  if (( DRY_RUN )); then
    info "Dry-run: would download $VSCODE_DEB_URL and install the resulting .deb"
    return 0
  fi

  # This preseed must happen before apt installs the package.
  printf '%s\n' 'code code/add-microsoft-repo boolean true' | sudo debconf-set-selections
  curl -fL --retry 3 --output "$tmp_deb" "$VSCODE_DEB_URL"
  sudo apt-get install -y "$tmp_deb"
  rm -f "$tmp_deb"
  success "VS Code installed from Microsoft's current .deb redirect."
}

install_vscode_optional() {
  local choice
  choice=$(choose_one "Visual Studio Code installation:" \
    "Install from Microsoft's apt repository (recommended for updates and architecture handling)" \
    "Install the current official .deb through LinkID=760868" \
    "Skip VS Code")
  case "$choice" in
    1) install_vscode_repo ;;
    2) install_vscode_deb ;;
    3) ;;
  esac
}

configure_git_optional() {
  command_exists git || return 0
  if ! ask_yes_no "Configure global Git name and email for $(id -un)?" Y; then return 0; fi

  local current_name current_email git_name git_email
  current_name=$(git config --global user.name 2>/dev/null || true)
  current_email=$(git config --global user.email 2>/dev/null || true)
  read -r -p "Git user.name [${current_name:-none}]: " git_name
  read -r -p "Git user.email [${current_email:-none}]: " git_email
  git_name=${git_name:-$current_name}
  git_email=${git_email:-$current_email}
  [[ -n $git_name ]] && git config --global user.name "$git_name"
  [[ -n $git_email ]] && git config --global user.email "$git_email"
  success "Git configuration updated."
}

online_maintenance_and_tools() {
  section "Step 9: system maintenance"
  reconnect_network_if_needed

  if ask_yes_no "Run apt update, full-upgrade, autoremove, and autoclean now?" Y; then
    run_root apt-get update

    local do_full_upgrade=1
    if (( ! DRY_RUN )); then
      local upgrade_plan
      upgrade_plan=$(mktemp)
      sudo apt-get --simulate full-upgrade > "$upgrade_plan"
      if grep -q '^Remv ' "$upgrade_plan"; then
        warn "The full-upgrade simulation would remove packages:"
        grep '^Remv ' "$upgrade_plan" | sed 's/^/  /'
        if ! ask_yes_no "Proceed with those removals?" N; then
          do_full_upgrade=0
          warn "Skipped full-upgrade; optional developer-tool setup can still continue."
        fi
      else
        info "The full-upgrade simulation did not report package removals."
      fi
      rm -f "$upgrade_plan"
    fi

    if (( do_full_upgrade )); then
      run_root apt-get full-upgrade -y

      local do_autoremove=1
      if (( ! DRY_RUN )); then
        local autoremove_plan
        autoremove_plan=$(mktemp)
        sudo apt-get --simulate autoremove > "$autoremove_plan"
        if grep -q '^Remv ' "$autoremove_plan"; then
          warn "autoremove would remove these packages:"
          grep '^Remv ' "$autoremove_plan" | sed 's/^/  /'
          ask_yes_no "Run autoremove?" N || do_autoremove=0
        fi
        rm -f "$autoremove_plan"
      fi
      (( do_autoremove )) && run_root apt-get autoremove -y
      run_root apt-get autoclean
      success "System maintenance completed."
    fi
  fi

  section "Optional developer tools"
  local selected_packages=()
  select_packages selected_packages
  if (( ${#selected_packages[@]} > 0 )); then
    printf 'Packages selected:\n'
    printf '  %s\n' "${selected_packages[@]}"
    if ask_yes_no "Install these packages?" Y; then
      run_root apt-get update
      if (( DRY_RUN )); then
        run_root apt-get install -y "${selected_packages[@]}"
      else
        local install_plan
        install_plan=$(mktemp)
        if sudo apt-get --simulate install "${selected_packages[@]}" > "$install_plan" 2>&1; then
          grep -E '^(Inst|Remv) ' "$install_plan" | sed 's/^/  /' || true
          sudo apt-get install -y "${selected_packages[@]}"
        else
          warn "APT could not resolve the selected package set:"
          sed 's/^/  /' "$install_plan" >&2
          warn "No selected packages were installed. Adjust the profile or custom package names and rerun 'dev'."
        fi
        rm -f "$install_plan"
      fi
    fi
  fi

  install_vscode_optional
  configure_git_optional

  if [[ $(state_get SSH_KEY_PENDING 2>/dev/null || printf '0') == 1 ]]; then
    if ask_yes_no "Install openssh-client and generate the deferred SSH key now?" Y; then
      run_root apt-get install -y openssh-client
      generate_ssh_key
    fi
  fi

  if [[ $(os_release_value ID || true) == kali ]] && command_exists kali-tweaks; then
    if ask_yes_no "Run kali-tweaks interactively now?" N; then
      run kali-tweaks
    fi
  fi
}

reconnect_network_if_needed() {
  if https_probe; then
    success "Internet connectivity is already available."
    return 0
  fi
  reconnect_network
}

# ---------- security extras -------------------------------------------------

configure_ufw() {
  warn "A firewall can interfere with listening services and penetration-testing labs. Review every rule."
  local ssh_allowed=0
  if [[ -n ${SSH_CONNECTION:-} ]]; then
    warn "This shell is connected over SSH. UFW will not be enabled unless OpenSSH is allowed first."
  fi
  run_root apt-get install -y ufw
  run_root ufw default deny incoming
  run_root ufw default allow outgoing

  if [[ -n ${SSH_CONNECTION:-} ]] || systemctl is-active ssh.service >/dev/null 2>&1; then
    if ask_yes_no "Allow the OpenSSH service through UFW?" Y; then
      run_root ufw allow OpenSSH
      ssh_allowed=1
    fi
  fi

  if ask_yes_no "Enable UFW with the rules shown above?" N; then
    if [[ -n ${SSH_CONNECTION:-} && $ssh_allowed -ne 1 ]]; then
      warn "Refusing to enable UFW in an SSH session without an OpenSSH allow rule."
      return 0
    fi
    run_root ufw --force enable
    run_root ufw status verbose
  else
    info "UFW was installed/configured but not enabled."
  fi
}

configure_persistent_journal() {
  local max_use
  read -r -p "Maximum persistent journal size [500M]: " max_use
  max_use=${max_use:-500M}
  [[ $max_use =~ ^[0-9]+[KMGTP]$ ]] || { warn "Invalid size; using 500M."; max_use=500M; }

  if (( DRY_RUN )); then
    info "Dry-run: would create /etc/systemd/journald.conf.d/10-${PROJECT_NAME}.conf with Storage=persistent and SystemMaxUse=$max_use"
    return 0
  fi

  sudo install -d -m 0755 /etc/systemd/journald.conf.d
  sudo tee "/etc/systemd/journald.conf.d/10-${PROJECT_NAME}.conf" >/dev/null <<EOF_JOURNAL
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=$max_use
EOF_JOURNAL
  sudo systemctl restart systemd-journald
  success "Persistent journald storage enabled with a $max_use cap."
}

install_auditd() {
  run_root apt-get install -y auditd audispd-plugins
  run_root systemctl enable auditd.service
  if (( ! DRY_RUN )); then
    sudo service auditd start || true
    sudo auditctl -s || true
  fi
  success "auditd installed and enabled. No custom audit rules were imposed."
}

install_clamav() {
  warn "ClamAV can consume resources and may quarantine samples used in malware-analysis labs."
  ask_yes_no "Install ClamAV anyway?" N || return 0
  run_root apt-get install -y clamav clamav-daemon
  if (( ! DRY_RUN )); then
    sudo systemctl stop clamav-freshclam.service 2>/dev/null || true
    sudo freshclam || true
    sudo systemctl enable --now clamav-freshclam.service 2>/dev/null || true
  fi
  success "ClamAV installed. Quarantine policy remains under your control."
}

ssh_server_audit() {
  if ! command_exists sshd; then
    info "OpenSSH server is not installed; nothing to audit."
    return 0
  fi
  printf 'Effective SSH server settings:\n'
  if (( DRY_RUN )); then
    quote_cmd sudo -- sshd -T
  else
    sudo sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication|x11forwarding|maxauthtries|allowusers|allowgroups) ' || true
  fi
  info "This is audit-only; the script does not rewrite sshd_config or risk locking out remote access."
}

save_system_baseline() {
  section "Read-only system baseline"
  warn "The report contains local usernames, network addresses, services, and installed-package versions. Store it accordingly."

  local stamp report_tmp uid_min
  stamp=$(date +%Y%m%d-%H%M%S)
  if (( DRY_RUN )); then
    info "Dry-run: would save a baseline report to $REPORT_DIR/baseline-$stamp.txt"
    return 0
  fi

  uid_min=$(awk '$1 == "UID_MIN" {print $2; exit}' /etc/login.defs 2>/dev/null || true)
  uid_min=${uid_min:-1000}
  report_tmp=$(mktemp)

  {
    printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
    printf 'Collector: %s v%s\n\n' "$PROJECT_NAME" "$SCRIPT_VERSION"

    printf '%s\n' '=== Host and operating system ==='
    hostnamectl 2>/dev/null || true
    printf '\nKernel: '; uname -a
    printf 'Architecture: %s\n' "$(dpkg --print-architecture 2>/dev/null || printf unknown)"
    if command_exists systemd-detect-virt; then printf 'Virtualization: %s\n' "$(systemd-detect-virt 2>/dev/null || printf none)"; fi
    printf '\n/etc/os-release:\n'
    cat /etc/os-release 2>/dev/null || true

    printf '\n%s\n' '=== Interactive/local accounts ==='
    getent passwd | awk -F: -v min="$uid_min" '($3 == 0 || $3 >= min) {printf "%s\tuid=%s\tgid=%s\thome=%s\tshell=%s\n", $1, $3, $4, $6, $7}'
    printf '\nCurrent identity and groups:\n'
    id

    printf '\n%s\n' '=== Network state ==='
    if command_exists ip; then
      ip -brief address 2>/dev/null || true
      printf '\nRoutes:\n'
      ip route show table all 2>/dev/null || true
    fi
    printf '\nListening sockets:\n'
    if command_exists ss; then sudo ss -lntup 2>/dev/null || ss -lntu 2>/dev/null || true; else printf 'ss command unavailable\n'; fi

    printf '\n%s\n' '=== Enabled and running services ==='
    systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null || true
    printf '\nRunning:\n'
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null || true

    printf '\n%s\n' '=== Firewall and Linux security modules ==='
    if command_exists ufw; then sudo ufw status verbose 2>/dev/null || true; else printf 'UFW not installed\n'; fi
    if command_exists aa-status; then sudo aa-status 2>/dev/null || true; else printf 'AppArmor status tool not installed\n'; fi
    if command_exists auditctl; then sudo auditctl -s 2>/dev/null || true; else printf 'auditd tools not installed\n'; fi
    if command_exists journalctl; then journalctl --disk-usage 2>/dev/null || true; fi

    printf '\n%s\n' '=== Checksums of selected system configuration files ==='
    local file
    for file in /etc/hosts /etc/hostname /etc/passwd /etc/group /etc/sudoers /etc/apt/sources.list; do
      [[ -f $file ]] && sudo sha256sum "$file" 2>/dev/null || true
    done
    if [[ -d /etc/apt/sources.list.d ]]; then
      find /etc/apt/sources.list.d -maxdepth 1 -type f -print0 2>/dev/null |
        sort -z |
        xargs -0 -r sudo sha256sum 2>/dev/null || true
    fi

    printf '\n%s\n' '=== Installed Debian packages ==='
    dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null | sort || true
  } > "$report_tmp"

  sudo install -d -m 0755 "$REPORT_DIR"
  sudo install -m 0644 "$report_tmp" "$REPORT_DIR/baseline-$stamp.txt"
  rm -f "$report_tmp"
  success "System baseline saved to $REPORT_DIR/baseline-$stamp.txt"
}

security_extras() {
  section "Optional security and forensic-readiness features"
  reconnect_network_if_needed
  run_root apt-get update

  ask_yes_no "Configure the UFW host firewall?" N && configure_ufw
  ask_yes_no "Enable capped persistent systemd journal storage?" Y && configure_persistent_journal
  ask_yes_no "Install and enable auditd (without custom rules)?" N && install_auditd
  ask_yes_no "Consider installing ClamAV?" N && install_clamav
  ask_yes_no "Show an audit of effective OpenSSH server settings?" Y && ssh_server_audit

  if command_exists aa-status; then
    printf '\nAppArmor status:\n'
    run_root aa-status || true
  else
    info "AppArmor tools are not installed. No kernel security module changes were attempted."
  fi
}

# ---------- workflow commands ----------------------------------------------

start_workflow() {
  require_normal_user
  ensure_debian_family
  require_sudo
  install_local_copy

  state_set_many \
    "SCRIPT_VERSION=$SCRIPT_VERSION" \
    "WORKFLOW_STARTED=$(date --iso-8601=seconds)" \
    "START_USER=$(id -un)" \
    "START_COMMAND_PATH=$INSTALLED_SCRIPT"

  prepare_offline_state
  change_hostname_safely
  create_replacement_user
  generate_ssh_key
  review_services
  state_set_many "OFFLINE_PHASE_COMPLETE=1"

  local new_user
  new_user=$(state_get NEW_USER || id -un)
  section "Offline phase complete"
  if [[ $new_user != $(id -un) ]]; then
    cat <<NEXT
1. Log out of '$(id -un)'.
2. Log in as '$new_user'.
3. While still offline, run:

   $INSTALLED_SCRIPT continue

The old account remains enabled until the continuation phase validates sudo for '$new_user'.
NEXT
  else
    cat <<NEXT
No replacement account was selected. Continue with:

   $INSTALLED_SCRIPT continue
NEXT
  fi
}

continue_workflow() {
  require_normal_user
  ensure_debian_family
  [[ -r $STATE_FILE ]] || die "No saved workflow state exists. Run '$0 start' first."

  local expected_user
  expected_user=$(state_get NEW_USER || true)
  if [[ -n $expected_user && $expected_user != $(id -un) ]]; then
    die "The saved workflow expects user '$expected_user'; current user is '$(id -un)'."
  fi

  require_sudo
  configure_desktop_settings
  finalize_old_user
  reconnect_network_if_needed
  online_maintenance_and_tools

  if ask_yes_no "Review optional security/logging features now?" N; then
    security_extras
  fi
  ask_yes_no "Save a read-only post-setup system baseline report?" Y && save_system_baseline

  state_set_many "WORKFLOW_COMPLETE=1" "WORKFLOW_COMPLETED=$(date --iso-8601=seconds)"
  section "Setup complete"
  status_command
}

dev_command() {
  require_normal_user
  ensure_debian_family
  require_sudo
  online_maintenance_and_tools
}

services_command() {
  require_normal_user
  ensure_debian_family
  require_sudo
  review_services
}

security_command() {
  require_normal_user
  ensure_debian_family
  require_sudo
  security_extras
  ask_yes_no "Save a read-only post-security system baseline report?" Y && save_system_baseline
}

baseline_command() {
  require_normal_user
  ensure_debian_family
  require_sudo
  save_system_baseline
}

status_command() {
  section "debian-dev-setup status"
  printf 'Script version:     %s\n' "$SCRIPT_VERSION"
  printf 'Current user:       %s\n' "$(id -un)"
  printf 'Current hostname:   %s\n' "$(current_static_hostname)"
  printf 'Distribution:       %s (%s)\n' "$(os_release_value PRETTY_NAME || printf unknown)" "$(dpkg --print-architecture 2>/dev/null || printf unknown)"
  printf 'Installed copy:     %s\n' "$([[ -x $INSTALLED_SCRIPT ]] && printf yes || printf no)"
  printf 'State file:         %s\n' "$([[ -r $STATE_FILE ]] && printf '%s' "$STATE_FILE" || printf none)"
  printf '\n'
  network_report

  if [[ -r $STATE_FILE ]]; then
    printf '\nSaved workflow state:\n'
    sed 's/^/  /' "$STATE_FILE"
  fi

  local old_user lock_status
  old_user=$(state_get OLD_USER || true)
  if [[ -n $old_user ]] && id "$old_user" >/dev/null 2>&1; then
    lock_status=$(sudo -n passwd -S "$old_user" 2>/dev/null || true)
    if [[ -z $lock_status ]]; then lock_status="Run with a cached sudo credential to display shadow-password status."; fi
    printf '\nOld account status:\n  %s\n' "$lock_status"
  fi
}

parse_args() {
  while (($#)); do
    case "$1" in
      --config)
        (($# >= 2)) || die "--config requires a file path."
        CONFIG_FILE=$2
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --version)
        printf '%s\n' "$SCRIPT_VERSION"
        exit 0
        ;;
      -h|--help)
        COMMAND=help
        shift
        ;;
      start|continue|dev|services|security|baseline|status|help)
        [[ -z $COMMAND ]] || die "Only one command may be specified."
        COMMAND=$1
        shift
        ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
  COMMAND=${COMMAND:-help}
}

main() {
  parse_args "$@"
  load_config
  case "$COMMAND" in
    start) start_workflow ;;
    continue) continue_workflow ;;
    dev) dev_command ;;
    services) services_command ;;
    security) security_command ;;
    baseline) baseline_command ;;
    status) status_command ;;
    help) usage ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
