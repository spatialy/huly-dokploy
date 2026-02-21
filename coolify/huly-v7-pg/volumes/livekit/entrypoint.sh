#!/bin/sh
set -e

echo "=== LiveKit Entrypoint ==="
echo "Injecting API keys and domain into config..."

cp /etc/livekit.template /etc/livekit.yaml
sed -i "s|LIVEKIT_KEY_PLACEHOLDER|$LIVEKIT_API_KEY|g" /etc/livekit.yaml
sed -i "s|LIVEKIT_SECRET_PLACEHOLDER|$LIVEKIT_API_SECRET|g" /etc/livekit.yaml
sed -i "s|LIVEKIT_DOMAIN_PLACEHOLDER|$HOST_ADDRESS|g" /etc/livekit.yaml

echo "LiveKit config ready. Starting server..."
exec /livekit-server --config /etc/livekit.yaml
