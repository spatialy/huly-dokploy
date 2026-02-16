#!/bin/bash
# Bump the template semantic version across all files.
# Usage: ./scripts/bump-version.sh [major|minor|patch]
# Example: ./scripts/bump-version.sh patch   # v1.1.0 -> v1.1.1
#          ./scripts/bump-version.sh minor   # v1.1.0 -> v1.2.0
#          ./scripts/bump-version.sh major   # v1.1.0 -> v2.0.0

set -euo pipefail
cd "$(dirname "$0")/.."

PART="${1:-patch}"
CURRENT=$(cat VERSION | tr -d '[:space:]')

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$PART" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *) echo "Usage: $0 [major|minor|patch]"; exit 1 ;;
esac

NEW="${MAJOR}.${MINOR}.${PATCH}"

echo "Bumping template version: v${CURRENT} -> v${NEW}"

# 1. VERSION file
printf '%s\n' "$NEW" > VERSION

# 2. meta.json — update version badge
sed -i '' "s/\"version\": \"v${CURRENT}\"/\"version\": \"v${NEW}\"/" meta.json

# 3. meta.json — update Huly version in description (keep as-is, only bump template version)

# 4. template.toml — TEMPLATE_VERSION env var
sed -i '' "s/TEMPLATE_VERSION=v${CURRENT}/TEMPLATE_VERSION=v${NEW}/" blueprints/huly-v7/template.toml

echo "Done. Updated files:"
echo "  VERSION              -> ${NEW}"
echo "  meta.json            -> v${NEW}"
echo "  template.toml        -> TEMPLATE_VERSION=v${NEW}"
echo ""
echo "To also bump the Huly upstream version, edit HULY_VERSION in template.toml manually."
