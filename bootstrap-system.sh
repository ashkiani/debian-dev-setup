#!/bin/bash
#==================================================
# Script Name: bootstrap-system.sh
# Description: Prepares system (update, user creation),
#              then auto-runs debian-dev-setup.sh
# Author: Siavash Ashkiani
# Date: 2025-05-15
#==================================================

set -e

if [[ "$EUID" -ne 0 ]]; then
  echo " This script must be run as root (e.g., with sudo)."
  exit 1
fi

echo "=================================================="
echo " Bootstrap System Script"
echo " Author: Siavash Ashkiani"
echo " Date: 2025-05-15"
echo "=================================================="

echo
read -p "Would you like to update and upgrade the system first? [y/N]: " do_update
if [[ "$do_update" =~ ^[Yy]$ ]]; then
  apt-get update && apt-get upgrade -y
  echo "System update and upgrade complete."
fi

echo
read -p "Would you like to create a new user account? [y/N]: " create_user
if [[ "$create_user" =~ ^[Yy]$ ]]; then
  read -p "Enter new username: " NEW_USER

  if id "$NEW_USER" &>/dev/null; then
    echo "User '$NEW_USER' already exists. Skipping creation."
  else
    adduser "$NEW_USER"

    read -p "Do you want to give '$NEW_USER' sudo privileges? [y/N]: " add_sudo
    if [[ "$add_sudo" =~ ^[Yy]$ ]]; then
      usermod -aG sudo "$NEW_USER"
      echo "'$NEW_USER' added to sudo group."
    fi
  fi

  echo
  read -p "Do you want to switch to '$NEW_USER' and begin dev setup now? [y/N]: " switch_now
  if [[ "$switch_now" =~ ^[Yy]$ ]]; then
    echo "Downloading debian-dev-setup.sh and switching..."
    curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/debian-dev-setup.sh -o /home/"$NEW_USER"/debian-dev-setup.sh
    chown "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"/debian-dev-setup.sh
    chmod +x /home/"$NEW_USER"/debian-dev-setup.sh
    su - "$NEW_USER" -c "bash ~/debian-dev-setup.sh"
    exit 0
  fi
fi

# If no user was created or no switch happened, run dev setup here
echo
read -p "Would you like to run the dev setup now (VS Code, Git, Node.js)? [y/N]: " run_here
if [[ "$run_here" =~ ^[Yy]$ ]]; then
  curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/debian-dev-setup.sh | bash
else
  echo
  echo " You can manually run the setup later with:"
  echo "    bash <(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/debian-dev-setup.sh)"
  echo
fi
