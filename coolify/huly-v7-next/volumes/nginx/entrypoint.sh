#!/bin/sh
set -e

# Calculate parent domain from HOST_ADDRESS
# huly.example.com -> example.com
# app.huly.example.com -> huly.example.com
PARENT_DOMAIN=$(echo "$HOST_ADDRESS" | sed 's/^[^.]*\.//')

echo "=== Huly V7 Nginx Entrypoint ==="
echo "HOST_ADDRESS: $HOST_ADDRESS"
echo "PARENT_DOMAIN: $PARENT_DOMAIN"

# Always regenerate config from template (template is read-only, never modified)
cp /etc/nginx/nginx.template /etc/nginx/conf.d/default.conf
sed -i "s/PARENT_DOMAIN_PLACEHOLDER/.$PARENT_DOMAIN/g" /etc/nginx/conf.d/default.conf
sed -i "s/HOST_ADDRESS_PLACEHOLDER/$HOST_ADDRESS/g" /etc/nginx/conf.d/default.conf

echo "Nginx config generated from template!"
echo "Starting nginx..."

# Start nginx in foreground
exec nginx -g 'daemon off;'
