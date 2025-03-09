#!/bin/bash
######################################
# Writtent By : Sean Rokah & Nehoray Kanizo Aka 
#
# nginx_task.sh - Script to set up a complete NGINX configuration file
# with a properly nested http block, server block, and location directives.
#
# Usage:
#  ./nginx_task.sh [--check-nginx] [--virtual-host] [--user-dir] [--auth] [--auth-pam] [--cgi] [--all]
# Use --all to run all configuration options.
#
# This script will back up your existing /etc/nginx/nginx.conf and then write
# a new complete configuration file that .
#
# It must be run with root privileges.
######################################

set -e

# Initialize option flags
CHECK_NGINX=0
VHOST=0
USER_DIR=0
AUTH=0
AUTH_PAM=0
CGI=0

# Function: Print usage
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

# Parse command-line arguments
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

# Function: Check if a package is installed; if not, install it.
install_package() {
    if ! dpkg -s "$1" >/dev/null 2>&1; then
        echo "Package $1 is not installed. Installing..."
        apt update && apt install -y "$1"
    else
        echo "Package $1 is already installed."
    fi
}

# Function: Check that NGINX is installed; if not, install it.
check_nginx_installed() {
    echo "Checking if NGINX is installed..."
    if ! command -v nginx >/dev/null 2>&1; then
        echo "NGINX not found. Installing NGINX..."
        apt update && apt install -y nginx
    else
        echo "NGINX is installed."
    fi
}

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (e.g., using sudo)."
    exit 1
fi

# Run NGINX check if requested
if [ "$CHECK_NGINX" -eq 1 ]; then
    check_nginx_installed
fi

# Default domain and document root if not using virtual-host option
DOMAIN="localhost"
DOC_ROOT="/var/www/default"

# If virtual host option is selected, prompt for domain name and create document root.
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
    # For non-virtual-host configurations, ensure a default doc root exists.
    mkdir -p "$DOC_ROOT"
    [ -f "${DOC_ROOT}/index.html" ] || echo "<html><body><h1>Welcome to ${DOMAIN}</h1></body></html>" > "${DOC_ROOT}/index.html"
fi

# Variables to hold additional location blocks
USER_DIR_BLOCK=""
AUTH_BLOCK=""
AUTH_PAM_BLOCK=""
CGI_BLOCK=""

# If user directory support is enabled, create location block
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

# If basic auth is enabled, prompt for credentials and create htpasswd file and location block.
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

# If PAM auth is enabled, check for the module and add PAM location block.
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

# Back up the current main configuration file.
CONFIG_FILE="/etc/nginx/nginx.conf"
BACKUP_FILE="/etc/nginx/nginx.conf.bak_$(date +%Y%m%d%H%M%S)"
if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up existing NGINX configuration to $BACKUP_FILE..."
    cp "$CONFIG_FILE" "$BACKUP_FILE"
fi

echo "Writing complete configuration to $CONFIG_FILE..."
echo "${NGINX_CONFIG}" > "$CONFIG_FILE"

# Test NGINX configuration and reload if successful
echo "Testing NGINX configuration..."
if nginx -t; then
    echo "NGINX configuration test passed. Reloading NGINX..."
    systemctl reload nginx
else
    echo "NGINX configuration test failed. Please review the configuration."
    exit 1
fi

echo "Script execution complete. Your NGINX configuration is now updated."

