#!/bin/bash
# Bump template version and/or Huly upstream version.
#
# Usage:
#   ./scripts/bump-version.sh patch               # v1.1.0 -> v1.1.1
#   ./scripts/bump-version.sh minor               # v1.1.0 -> v1.2.0
#   ./scripts/bump-version.sh major               # v1.1.0 -> v2.0.0
#   ./scripts/bump-version.sh huly v0.7.320       # Update Huly images + auto patch bump

set -euo pipefail
cd "$(dirname "$0")/.."

TOML="blueprints/huly-v7/template.toml"

# Read current versions
CURRENT_TPL=$(cat VERSION | tr -d '[:space:]')
CURRENT_HULY=$(grep -o 'HULY_VERSION=v[0-9.]*' "$TOML" | head -1 | cut -d= -f2)

sync_huly_to_description() {
  local huly_ver="$1"
  # Update the (Huly vX.Y.Z) portion in meta.json description
  sed -i '' "s/(Huly v[0-9.]*)/(Huly ${huly_ver})/" meta.json
}

bump_template() {
  local PART="$1"
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_TPL"

  case "$PART" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
  esac

  local NEW="${MAJOR}.${MINOR}.${PATCH}"
  echo "Template version: v${CURRENT_TPL} -> v${NEW}"

  # VERSION file
  printf '%s\n' "$NEW" > VERSION

  # meta.json version badge
  sed -i '' "s/\"version\": \"v${CURRENT_TPL}\"/\"version\": \"v${NEW}\"/" meta.json

  # template.toml TEMPLATE_VERSION env var
  sed -i '' "s/TEMPLATE_VERSION=v${CURRENT_TPL}/TEMPLATE_VERSION=v${NEW}/" "$TOML"

  # Always sync current Huly version into meta.json description
  local huly_ver
  huly_ver=$(grep -o 'HULY_VERSION=v[0-9.]*' "$TOML" | head -1 | cut -d= -f2)
  sync_huly_to_description "$huly_ver"

  echo "  VERSION              -> ${NEW}"
  echo "  meta.json            -> v${NEW} (Huly ${huly_ver})"
  echo "  template.toml        -> TEMPLATE_VERSION=v${NEW}"
}

bump_huly() {
  local NEW_HULY="$1"
  # Validate format
  if [[ ! "$NEW_HULY" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Huly version must be vX.Y.Z (e.g., v0.7.320)"
    exit 1
  fi

  echo "Huly upstream: ${CURRENT_HULY} -> ${NEW_HULY}"

  # template.toml HULY_VERSION env var
  sed -i '' "s/HULY_VERSION=${CURRENT_HULY}/HULY_VERSION=${NEW_HULY}/" "$TOML"

  # meta.json description
  sync_huly_to_description "$NEW_HULY"

  echo "  template.toml        -> HULY_VERSION=${NEW_HULY}"
  echo "  meta.json            -> description updated"
  echo ""

  # Auto-bump template patch version
  bump_template patch
}

case "${1:-patch}" in
  major|minor|patch)
    bump_template "$1"
    ;;
  huly)
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 huly <version>"
      echo "Example: $0 huly v0.7.320"
      exit 1
    fi
    bump_huly "$2"
    ;;
  *)
    echo "Usage: $0 [major|minor|patch|huly <vX.Y.Z>]"
    echo ""
    echo "Commands:"
    echo "  patch              Bump template patch version (default)"
    echo "  minor              Bump template minor version"
    echo "  major              Bump template major version"
    echo "  huly v0.7.320      Update Huly upstream images + auto patch bump"
    echo ""
    echo "Current versions:"
    echo "  Template:  v${CURRENT_TPL}"
    echo "  Huly:      ${CURRENT_HULY}"
    exit 1
    ;;
esac

echo ""
echo "Done."
