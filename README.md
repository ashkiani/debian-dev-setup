# debian-dev-setup
One-command setup for VS Code, Git, and Node.js on any Debian-based Linux system.

---


# debian-dev-setup

A simple one-liner script to quickly set up a new Debian-based Linux system with:

- ✅ [Visual Studio Code](https://code.visualstudio.com/)
- ✅ [Git](https://git-scm.com/)
- ✅ [Node.js & npm](https://nodejs.org/)

Perfect for Ubuntu, Kali, Linux Mint, or any other Debian-derived distribution.

---

## 🔧 Usage

Run this in your terminal on a fresh Linux machine:

```bash
curl -fsSL https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/debian-dev-setup.sh | bash
```

Or using `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/ashkiani/debian-dev-setup/main/debian-dev-setup.sh | bash
```


---

## 📋 What This Script Does

* Prompts you for confirmation before proceeding
* Downloads and installs VS Code from the official Microsoft link
* Installs Git if not already present
* Installs Node.js and npm if not already present
* Prompts you to enter your Git username and email
* Cleans up downloaded files after installation

---

## ✅ Supported Platforms

This script is intended for **Debian-based distributions**, including but not limited to:

* Ubuntu
* Kali Linux
* Linux Mint
* Pop!\_OS
* Elementary OS

---

## 💡 Author

Created by [Siavash Ashkiani](https://github.com/ashkiani)
For questions, feel free to open an issue or submit a pull request.


---
