#!/bin/bash
#==================================================
# Script Name: bootstrap-system.sh
# Description: Prepares system (update, user creation),
#              and guides user to complete dev setup
# Author: Siavash Ashkiani
# Date: 2025-05-15
#==================================================

set -e

if [[ "$EUID" -ne 0 ]]; then
  echo "❌ This script must be run as root (e.g., with sudo)."
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
  echo "✅ System update and upgrade complete."
fi

echo
read -p "Would you like to create a new user account? [y/N]: " create_user
if [[ "$create_user" =~ ^[Yy]$ ]]; then
  read -p "Enter new username: " NEW_USER

  if id "$NEW_USER" &>/dev/null; then
    echo "⚠️ User '$NEW_USER' already exists. Skipping creation."
  else
    adduser "$NEW_USER"

    read -p "Do you want to give '$NEW_USER' sudo privileges? [y/N]: " add_sudo
    if [[ "$add_sudo" =~ ^[Yy]$ ]]; then
      usermod -aG sudo "$NEW_USER"
      echo "✅ '$NEW_USER' added to sudo group."
    fi
  fi

  echo
  echo "✅ User '$NEW_USER' has been created and configured."
  echo "👉 To continue with dev setup, switch to the new user and run:"
  echo
  echo "    su - $NEW_USER"
  echo "    bash <(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/debian-dev-setup.sh)"
  echo
  exit 0
fi

# If no user is created, offer to run the dev setup directly
echo
read -p "Would you like to run the dev setup now (VS Code, Git, Node.js)? [y/N]: " run_here
if [[ "$run_here" =~ ^[Yy]$ ]]; then
  bash <(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/debian-dev-setup.sh)
else
  echo
  echo "📝 You can manually run the dev setup anytime with:"
  echo "    bash <(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/debian-dev-setup.sh)"
  echo
fi
