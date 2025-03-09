# 🚀 NGINX Configuration Tool

## 👥 Authors
- Sean Rokah
- Nehoray Kanizo

## 📄 Overview
This script is a tool for configuring NGINX with various options. It can be used to set up a complete NGINX configuration file with a properly nested `http` block, `server` block, and `location` directives. The script can also check for the presence of NGINX and install it if necessary.

## 🌟 Features
- 🌐 Virtual host configuration
- 🏠 User directory support
- 🔒 Basic HTTP authentication
- 🔐 PAM authentication
- 🖥️ CGI scripting support

## 🛠️ Usage
The script must be run with root privileges.

### ⚙️ Options
- `--check-nginx`: Check and install NGINX if not present.
- `--virtual-host`: Configure a virtual host (requires domain name).
- `--user-dir`: Add user directory support.
- `--auth`: Add basic HTTP authentication.
- `--auth-pam`: Add PAM authentication.
- `--cgi`: Add CGI scripting support.
- `--all`: Enable all options.
- `-h, --help`: Show this help message.

### 📋 Example
```bash
sudo ./nginx_task.sh --check-nginx --virtual-host --auth
```
This will check for NGINX, install it if necessary, configure a virtual host, and add basic HTTP authentication.

## 📜 Instructions
1. Ensure you have root privileges.
2. Download the script to your desired location.
3. Make the script executable:
    ```bash
    chmod +x /path/to/nginx_task.sh
    ```
4. Run the script with the desired options:
    ```bash
    sudo /path/to/nginx_task.sh [OPTIONS]
    ```

## 📝 Notes
- This script assumes a Debian-based system with NGINX installed. It may need to be modified for other distributions or configurations.
- The script will create a backup of the existing NGINX configuration file before making any changes.

## 📂 Navigator 
- [Nginx_Tool.sh](./Task/Nginx_Tool.sh)
