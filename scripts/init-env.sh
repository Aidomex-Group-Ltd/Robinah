#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if [[ -e .env ]]; then printf '%s\n' '.env already exists; it has not been replaced.'; exit 1; fi
command -v openssl >/dev/null || { printf '%s\n' 'Install openssl first.' >&2; exit 1; }
read -r -p 'Shop domain (for example shop.example.com): ' shop_domain
read -r -p 'Owner email: ' owner_email
read -r -p 'Database name (default robinah_db): ' database_name
database_name=${database_name:-robinah_db}
[[ "$shop_domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && "$shop_domain" == *.* ]] || { printf '%s\n' 'Enter a hostname without https:// or a path.' >&2; exit 1; }
[[ "$owner_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || { printf '%s\n' 'Invalid email.' >&2; exit 1; }
[[ "$database_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { printf '%s\n' 'Database names may use letters, digits and underscores only.' >&2; exit 1; }
umask 077

# Automated secrets: every value below comes from openssl rand.
database_url=$database_name
secret_base_key=$(openssl rand -hex 64)   # SECRET_BASE_KEY, 64 bytes
jwt_secret=$(openssl rand -hex 32)        # JWT_SECRET, 32 bytes
live_signing_salt=$(openssl rand -hex 16) # LIVE_SIGNING_SALT, 16 bytes
shop_secret=$(openssl rand -hex 64)       # legacy SECRET_KEY_BASE alias
db_password=$(openssl rand -hex 16)
owner_password=$(openssl rand -hex 16)

cat > .env <<EOF
PHX_HOST=$shop_domain
APP_PORT=4100
DATABASE_URL=$database_url
SECRET_BASE_KEY=$secret_base_key
SECRET_KEY_BASE=$shop_secret
JWT_SECRET=$jwt_secret
LIVE_SIGNING_SALT=$live_signing_salt
ADMIN_EMAIL=$owner_email
ADMIN_PASSWORD=$owner_password
POSTGRES_USER=robinah
POSTGRES_PASSWORD=$db_password
POSTGRES_DB=$database_url
EOF

printf '\nCreated .env with private file permissions.\nGenerated with openssl: DATABASE_URL, SECRET_BASE_KEY, JWT_SECRET, LIVE_SIGNING_SALT.\nOwner email: %s\nOwner password: %s\nStore this password in your password manager.\n' "$owner_email" "$owner_password"
