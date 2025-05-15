# debian-dev-setup

This repo provides a clean, two-phase bootstrap + development setup process for Debian-based Linux systems.

It helps you:

* ✅ Set up a fresh system (with optional user creation and sudo)
* ✅ Install key development tools:

  * [Visual Studio Code](https://code.visualstudio.com/)
  * [Git](https://git-scm.com/)
  * [Node.js & npm](https://nodejs.org/)

Perfect for Ubuntu, Kali, Linux Mint, Pop!_OS, and other Debian-derived systems.

---

## 🚀 Quick Start

### 📌 Option A: Full Setup (Recommended for Fresh Installs)

Run this **as root** or with `sudo` to prepare your system and optionally create a new user:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/bootstrap-system.sh)"
```

You will be guided through:

* Running `apt update && upgrade`
* Creating a new user (optional)
* Adding that user to the `sudo` group (optional)

If you create a new user, you’ll be shown instructions like:

```bash
su - yourusername
bash <(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/setup-vscode-git.sh)
```

---

### ⚙️ Option B: Just Install Dev Tools (For Existing User Accounts)

If your system is already set up and you're ready to install VS Code, Git, and Node.js, run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/setup-vscode-git.sh)
```

This script will:

* Install VS Code from Microsoft’s official `.deb` package
* Install Git (if not already installed)
* Install Node.js & npm (if not already installed)
* Prompt you for your Git username and email

---

## 📁 File Overview

| File                  | Description                                        |
| --------------------- | -------------------------------------------------- |
| `bootstrap-system.sh` | Prepares system and optionally creates a new user  |
| `setup-vscode-git.sh` | Installs VS Code, Git, Node.js, and configures Git |

---

## 🔐 Requirements

* A Debian-based OS (Ubuntu, Kali, Linux Mint, etc.)
* Internet access
* `sudo` privileges (for setup or user creation)

---

## 🙋 Author

Created by [Siavash Ashkiani](https://github.com/ashkiani)
Pull requests and suggestions welcome!
