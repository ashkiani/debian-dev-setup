#!/bin/bash
#==================================================
# Script Name: setup-vscode-git.sh
# Description: Installs VS Code, Git, and Node.js on Debian-based systems
# Author: Siavash Ashkiani
# Date: 2025-05-14
#==================================================

set -e  # Exit on error

echo "=================================================="
echo " VS Code, Git, and Node.js Setup Script"
echo " Author: Siavash Ashkiani"
echo " Date: 2025-05-15"
echo "=================================================="

echo
echo "This script will:"
echo "  - Download and install Visual Studio Code"
echo "  - Install Git and Node.js if not already present"
echo "  - Configure your Git credentials"
echo

read -p "Do you want to proceed? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo
echo "Updating package lists..."
sudo apt-get update -y

# Ensure wget is installed
if ! command -v wget >/dev/null 2>&1; then
  echo "Installing wget..."
  sudo apt-get install -y wget
fi

# Ensure git is installed
if ! command -v git >/dev/null 2>&1; then
  echo "Installing git..."
  sudo apt-get install -y git
fi

# Ensure Node.js is installed
if ! command -v node >/dev/null 2>&1; then
  echo "Installing Node.js..."
  sudo apt-get install -y nodejs npm
else
  echo "✅ Node.js is already installed (version: $(node -v))"
fi

# Prompt for VS Code download URL and filename
DEFAULT_URL="https://go.microsoft.com/fwlink/?LinkID=760868"
read -p "VS Code download URL [default: $DEFAULT_URL]: " VSCODE_URL
VSCODE_URL="${VSCODE_URL:-$DEFAULT_URL}"

DEFAULT_DEB="vscode.deb"
read -p "Filename to save the downloaded .deb package [default: $DEFAULT_DEB]: " VSCODE_DEB
VSCODE_DEB="${VSCODE_DEB:-$DEFAULT_DEB}"

echo
echo "Downloading VS Code from: $VSCODE_URL"
echo "Saving as: $VSCODE_DEB"
wget -O "$VSCODE_DEB" "$VSCODE_URL"

# Install VS Code
if sudo apt install "./$VSCODE_DEB" -y; then
  echo "✅ VS Code installed via apt."
else
  echo "⚠️ VS Code install via apt failed, using dpkg fallback..."
  sudo dpkg -i "./$VSCODE_DEB" || true
  sudo apt-get install -f -y
fi

# Preconfigure repo integration
echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections

# Clean up .deb
rm -f "$VSCODE_DEB"

# Prompt for Git credentials
echo
echo "Let's configure Git."

while [[ -z "$GIT_USER" ]]; do
  read -p "Enter your Git user name: " GIT_USER
done

while [[ -z "$GIT_EMAIL" ]]; do
  read -p "Enter your Git email: " GIT_EMAIL
done

git config --global user.name "$GIT_USER"
git config --global user.email "$GIT_EMAIL"

echo
echo "✅ Setup complete! VS Code, Git, and Node.js are installed and Git is configured."