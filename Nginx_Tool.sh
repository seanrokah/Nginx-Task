#!/bin/bash
######################################
# Written By : Sean Rokah & Nehoray Kanizo  
# Date: 2025-09-03
# Purpose: NGINX Configuration Tool
# Version: 1.0.0
#
# This script is a tool for configuring NGINX with various options.
# It can be used to set up a complete NGINX configuration file with a properly
# nested http block, server block, and location directives.
# The script can also check for the presence of NGINX and install it if necessary.
# Options include:
#  - Virtual host configuration
#  - User directory support
#  - Basic HTTP authentication
#  - PAM authentication
#  - CGI scripting support
# The script can be run with individual options or all options together.
# It must be run with root privileges.
#
# Usage: ./nginx_task.sh [OPTIONS]
# Options:
#  --check-nginx      Check and install NGINX if not present.
#  --virtual-host     Configure a virtual host (requires domain name).
#  --user-dir         Add user directory support.
#  --auth             Add basic HTTP authentication.
#  --auth-pam         Add PAM authentication.
#  --cgi              Add CGI scripting support.
#  --all              Enable all options.
#  -h, --help         Show this help message.
#
# Example:
#  ./nginx_task.sh --check-nginx --virtual-host --auth
# This will check for NGINX, install it if necessary, configure a virtual host,
# and add basic HTTP authentication.
#
# Note: This script assumes a Debian-based system with NGINX installed.
# It may need to be modified for other distributions or configurations.
######################################


set -e

CHECK_NGINX=0
VHOST=0
USER_DIR=0
AUTH=0
AUTH_PAM=0
CGI=0

usage() {
    cat <<EOF
Usage: $0 [OPTION]
Options:
  --check-nginx      Check and install NGINX if not present.
  --virtual-host     Configure a virtual host (requires domain name).
  --user-dir         Add user directory support.
  --auth             Add basic HTTP authentication.
  --auth-pam         Add PAM authentication.
  --cgi              Add CGI scripting support.
  --all              Enable all options.
  -h, --help         Show this help message.
EOF
}

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

while [ "$1" != "" ]; do
    case "$1" in
        --check-nginx)
            CHECK_NGINX=1
            ;;
        --virtual-host)
            VHOST=1
            ;;
        --user-dir)
            USER_DIR=1
            ;;
        --auth)
            AUTH=1
            ;;
        --auth-pam)
            AUTH_PAM=1
            ;;
        --cgi)
            CGI=1
            ;;
        --all)
            CHECK_NGINX=1
            VHOST=1
            USER_DIR=1
            AUTH=1
            AUTH_PAM=1
            CGI=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

install_package() {
    if ! dpkg -s "$1" >/dev/null 2>&1; then
        echo "Package $1 is not installed. Installing..."
        apt update && apt install -y "$1"
    else
        echo "Package $1 is already installed."
    fi
}

check_nginx_installed() {
    echo "Checking if NGINX is installed..."
    if ! command -v nginx >/dev/null 2>&1; then
        echo "NGINX not found. Installing NGINX..."
        apt update && apt install -y nginx
    else
        echo "NGINX is installed."
    fi
}

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (e.g., using sudo)."
    exit 1
fi

if [ "$CHECK_NGINX" -eq 1 ]; then
    check_nginx_installed
fi

DOMAIN="localhost"
DOC_ROOT="/var/www/default"

if [ "$VHOST" -eq 1 ]; then
    read -p "Enter the virtual host domain name (e.g., example.com): " input_domain
    if [ -n "$input_domain" ]; then
        DOMAIN="$input_domain"
        DOC_ROOT="/var/www/${DOMAIN}"
        echo "Creating document root at ${DOC_ROOT}..."
        mkdir -p "$DOC_ROOT"
        echo "<html><body><h1>Welcome to ${DOMAIN}</h1></body></html>" > "${DOC_ROOT}/index.html"
    else
        echo "No domain provided. Using default domain: ${DOMAIN}"
    fi
else
    mkdir -p "$DOC_ROOT"
    [ -f "${DOC_ROOT}/index.html" ] || echo "<html><body><h1>Welcome to ${DOMAIN}</h1></body></html>" > "${DOC_ROOT}/index.html"
fi

USER_DIR_BLOCK=""
AUTH_BLOCK=""
AUTH_PAM_BLOCK=""
CGI_BLOCK=""

if [ "$USER_DIR" -eq 1 ]; then
    USER_DIR_BLOCK=$(cat <<'EOF'
        # User directories (e.g., http://domain/~username/)
        location ~ ^/~([^/]+)(/.*)?$ {
            alias /home/$1/public_html$2;
            autoindex on;
        }
EOF
)
fi

if [ "$AUTH" -eq 1 ]; then
    install_package apache2-utils
    read -p "Enter username for basic auth: " auth_user
    read -s -p "Enter password for basic auth: " auth_pass
    echo
    htpasswd -cb /etc/nginx/.htpasswd "${auth_user}" "${auth_pass}"
    AUTH_BLOCK=$(cat <<'EOF'
        # Basic Authentication for /protected
        location /protected {
            auth_basic "Restricted Area";
            auth_basic_user_file /etc/nginx/.htpasswd;
            try_files $uri $uri/ =404;
        }
EOF
)
fi

if [ "$AUTH_PAM" -eq 1 ]; then
    PAM_MODULE="/usr/lib/nginx/modules/ngx_http_auth_pam_module.so"
    if [ -f "$PAM_MODULE" ]; then
        MODULE_CONF="/etc/nginx/modules-enabled/50-mod-http-auth-pam.conf"
        echo "load_module $PAM_MODULE;" > "$MODULE_CONF"
        echo "PAM module loaded via $MODULE_CONF."
        AUTH_PAM_BLOCK=$(cat <<'EOF'
        # PAM Authentication for /pam-protected
        location /pam-protected {
            auth_pam "PAM Restricted";
            auth_pam_service_name "nginx";
            try_files $uri $uri/ =404;
        }
EOF
)
    else
        echo "PAM module not found at $PAM_MODULE. Skipping PAM configuration."
    fi
fi

if [ "$CGI" -eq 1 ]; then
    install_package fcgiwrap
    systemctl enable fcgiwrap
    systemctl start fcgiwrap
    CGI_BLOCK=$(cat <<'EOF'
        # CGI scripting support
        location /cgi-bin/ {
    alias /usr/lib/cgi-bin/;
    fastcgi_pass unix:/var/run/fcgiwrap.socket;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME /usr/lib/cgi-bin$fastcgi_script_name;
    fastcgi_param DOCUMENT_ROOT /usr/lib/cgi-bin;
}

EOF
)
fi


NGINX_CONFIG=$(cat <<EOF
# Generated by nginx_task.sh on $(date)
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    server {
        listen 80;
        server_name ${DOMAIN};
        root ${DOC_ROOT};
        index index.html;

        # Default location block
        location / {
            try_files \$uri \$uri/ =404;
        }

${USER_DIR_BLOCK}

${AUTH_BLOCK}

${AUTH_PAM_BLOCK}

${CGI_BLOCK}
    }
}
EOF
)

CONFIG_FILE="/etc/nginx/nginx.conf"
BACKUP_FILE="/etc/nginx/nginx.conf.bak_$(date +%Y%m%d%H%M%S)"
if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up existing NGINX configuration to $BACKUP_FILE..."
    cp "$CONFIG_FILE" "$BACKUP_FILE"
fi

echo "Writing complete configuration to $CONFIG_FILE..."
echo "${NGINX_CONFIG}" > "$CONFIG_FILE"

echo "Testing NGINX configuration..."
if nginx -t; then
    echo "NGINX configuration test passed. Reloading NGINX..."
    systemctl reload nginx
else
    echo "NGINX configuration test failed. Please review the configuration."
    exit 1
fi

echo "Script execution complete. Your NGINX configuration is now updated."

