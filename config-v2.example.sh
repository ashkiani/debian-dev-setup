# Optional configuration for vm-setup-v2.sh
#
# Default location:
#   ~/.config/debian-dev-setup/config-v2.sh
#
# An alternate file can be supplied with:
#   ./vm-setup-v2.sh --config /path/to/config-v2.sh dev
#
# This file is sourced as Bash code. Use only configuration files from trusted
# sources.

# Append packages to an existing profile.
PACKAGE_PROFILE_ESSENTIALS+=(
  htop
  tree
  tmux
)

# Replace an existing profile by assigning a new array.
# PACKAGE_PROFILE_NODE=(nodejs npm)

# Define an additional package profile.
CUSTOM_PROFILE_NAME="Additional command-line utilities"
PACKAGE_PROFILE_CUSTOM=(
  ripgrep
  fd-find
  shellcheck
)

# Add services to the interactive service review. A service is shown only when
# it is installed and enabled or running. Disabling a service always requires
# explicit confirmation.
SERVICE_REVIEW_CANDIDATES+=(
  docker.service
  libvirtd.service
)
