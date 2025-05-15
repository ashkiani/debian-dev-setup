# debian-dev-setup

A two-phase bootstrap + development setup for Debian-based Linux systems.

This tool helps you quickly set up:

- ✅ A clean system with optional updates and user account creation
- ✅ A development environment with:
  - [Visual Studio Code](https://code.visualstudio.com/)
  - [Git](https://git-scm.com/)
  - [Node.js & npm](https://nodejs.org/)

Perfect for Ubuntu, Kali, Linux Mint, Pop!_OS, and other Debian-derived systems.

---

## 🛠️ Setup Scripts

### 1. `bootstrap-system.sh`

Prepares your system by optionally:

- Running `apt update && upgrade`
- Creating a new user account
- Granting `sudo` access to that user
- Automatically downloading and running the main setup script under that user

### 2. `setup-vscode-git.sh`

Handles the development setup:

- Installs Git (if missing)
- Installs Node.js and npm (if missing)
- Installs Visual Studio Code from official `.deb`
- Configures Git with your name and email
- Cleans up after install

---

## 🚀 How to Use

### Option A: Full Setup (recommended for fresh installs)

Run the bootstrap script as `root` or with `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/bootstrap-system.sh | sudo bash
```

> This will guide you through system update, user creation, and then automatically switch and run the main setup script under the new user.

---

### Option B: Just Install Dev Tools (for existing user accounts)

If your system is already set up, you can run just the development setup:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/setup-vscode-git.sh)
```

---

## 🔐 Requirements

- Debian-based OS
- Internet access
- `sudo` privileges for user setup or package installation

---

## 📁 File Overview

| File                  | Purpose                                |
|-----------------------|----------------------------------------|
| `bootstrap-system.sh` | Prepares system and user environment   |
| `setup-vscode-git.sh` | Installs VS Code, Git, Node.js         |

---

## 🙋 Author

Created by [Siavash Ashkiani](https://github.com/ashkiani)  
Feel free to open issues or PRs if you'd like to improve it!
