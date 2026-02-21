#!/bin/sh
set -e

CERT_PATH="${CERTIFICATE_PATH:-/var/cfg/certificate.p12}"
CERT_PASS="${CERTIFICATE_PASSWORD:-password}"

echo "=== Sign Service Entrypoint ==="

if [ ! -f "$CERT_PATH" ]; then
  echo "No certificate found. Generating self-signed..."
  openssl ecparam -genkey -name prime256v1 -out /tmp/sign-key.pem 2>/dev/null
  openssl req -new -x509 -key /tmp/sign-key.pem -out /tmp/sign-cert.pem \
    -days 3650 -subj "/CN=Huly Document Signing/O=Huly Self-Hosted" 2>/dev/null
  openssl pkcs12 -export -out "$CERT_PATH" \
    -inkey /tmp/sign-key.pem -in /tmp/sign-cert.pem \
    -passout "pass:$CERT_PASS" 2>/dev/null
  rm -f /tmp/sign-key.pem /tmp/sign-cert.pem
  echo "Self-signed certificate generated. Replace with AATL cert for production."
else
  echo "Certificate found at $CERT_PATH"
fi

echo "Starting sign service..."
exec dumb-init node bundle.js
