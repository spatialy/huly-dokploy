#!/bin/bash
# Bump template version and/or Huly upstream version for active blueprints.
# The legacy huly-v7 blueprint is left as-is (manage manually if needed).
#
# Usage:
#   ./scripts/bump-version.sh patch               # Bump BOTH v7-next + v7-pg patch
#   ./scripts/bump-version.sh minor               # Bump BOTH minor
#   ./scripts/bump-version.sh major               # Bump BOTH major
#   ./scripts/bump-version.sh next [patch]         # Bump only v7-next (default: patch)
#   ./scripts/bump-version.sh pg [patch]           # Bump only v7-pg (default: patch)
#   ./scripts/bump-version.sh huly v0.7.360        # Update Huly images in BOTH + auto patch
#   ./scripts/bump-version.sh status               # Show current versions

set -euo pipefail
cd "$(dirname "$0")/.."

TOML_NEXT="blueprints/huly-v7-next/template.toml"
TOML_PG="blueprints/huly-v7-pg/template.toml"
ENV_NEXT="coolify/huly-v7-next/.env.example"
ENV_PG="coolify/huly-v7-pg/.env.example"
COOLIFY_YAML="coolify/huly.yaml"

# --- Helpers ---

get_version() { grep -o 'TEMPLATE_VERSION=v[0-9.]*' "$1" | head -1 | sed 's/TEMPLATE_VERSION=v//'; }
get_huly()    { grep -o 'HULY_VERSION=v[0-9.]*' "$1" | head -1 | cut -d= -f2; }

bump_semver() {
  local current="$1" part="$2"
  IFS='.' read -r M m p <<< "$current"
  case "$part" in
    major) M=$((M + 1)); m=0; p=0 ;;
    minor) m=$((m + 1)); p=0 ;;
    patch) p=$((p + 1)) ;;
  esac
  echo "${M}.${m}.${p}"
}

# Update meta.json: set version badge and sync Huly version in description
update_meta() {
  local id="$1" new_ver="$2" huly_ver="$3"
  python3 -c "
import json, re
with open('meta.json') as f:
    data = json.load(f)
for e in data:
    if e['id'] == '${id}':
        e['version'] = 'v${new_ver}'
        e['description'] = re.sub(r'\(Huly v[0-9.]+', '(Huly ${huly_ver}', e['description'])
with open('meta.json', 'w') as f:
    json.dump(data, f, indent=4)
    f.write('\n')
"
}

# --- Core operations ---

bump_template() {
  local toml="$1" part="$2" id="$3"
  local old new huly
  old=$(get_version "$toml")
  new=$(bump_semver "$old" "$part")
  huly=$(get_huly "$toml")

  sed -i '' "s/TEMPLATE_VERSION=v${old}/TEMPLATE_VERSION=v${new}/" "$toml"
  update_meta "$id" "$new" "$huly"

  echo "  ${id}: v${old} -> v${new} (Huly ${huly})"
}

bump_huly_in() {
  local file="$1" new_huly="$2"
  local old_huly
  old_huly=$(get_huly "$file")
  sed -i '' "s/HULY_VERSION=${old_huly}/HULY_VERSION=${new_huly}/g" "$file"
}

# Stats image uses s-prefix tags (upstream stopped publishing v-prefix after v0.7.353)
bump_stats_in() {
  local file="$1" new_huly="$2"
  local new_stats="s${new_huly#v}"
  sed -i '' "s/STATS_VERSION=s[0-9.]*/STATS_VERSION=${new_stats}/g" "$file"
}

# Update HULY_VERSION defaults in Coolify yaml (${HULY_VERSION:-vX.Y.Z} pattern)
bump_huly_coolify_yaml() {
  local new_huly="$1"
  sed -i '' "s/HULY_VERSION:-v[0-9.]*}/HULY_VERSION:-${new_huly}}/g" "$COOLIFY_YAML"
}

show_status() {
  echo "Current versions:"
  echo "  huly-v7-next:  v$(get_version "$TOML_NEXT")  (Huly $(get_huly "$TOML_NEXT"))"
  echo "  huly-v7-pg:    v$(get_version "$TOML_PG")  (Huly $(get_huly "$TOML_PG"))"
  echo ""
  echo "Legacy (not managed by this script):"
  echo "  huly-v7:       v$(get_version blueprints/huly-v7/template.toml)  (Huly $(get_huly blueprints/huly-v7/template.toml))"
}

# --- Main ---

case "${1:-status}" in
  next)
    echo "Bumping huly-v7-next template version..."
    bump_template "$TOML_NEXT" "${2:-patch}" "huly-v7-next"
    ;;
  pg)
    echo "Bumping huly-v7-pg template version..."
    bump_template "$TOML_PG" "${2:-patch}" "huly-v7-pg"
    ;;
  patch|minor|major)
    echo "Bumping both template versions ($1)..."
    bump_template "$TOML_NEXT" "$1" "huly-v7-next"
    bump_template "$TOML_PG" "$1" "huly-v7-pg"
    ;;
  huly)
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 huly <version>"
      echo "Example: $0 huly v0.7.360"
      exit 1
    fi
    NEW_HULY="$2"
    if [[ ! "$NEW_HULY" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Error: Huly version must be vX.Y.Z (e.g., v0.7.360)"
      exit 1
    fi

    echo "Updating Huly upstream to ${NEW_HULY}..."
    bump_huly_in "$TOML_NEXT" "$NEW_HULY"
    bump_huly_in "$TOML_PG" "$NEW_HULY"
    bump_huly_in "$ENV_NEXT" "$NEW_HULY"
    bump_huly_in "$ENV_PG" "$NEW_HULY"
    bump_huly_coolify_yaml "$NEW_HULY"
    bump_stats_in "$TOML_NEXT" "$NEW_HULY"
    bump_stats_in "$TOML_PG" "$NEW_HULY"
    bump_stats_in "$ENV_NEXT" "$NEW_HULY"
    bump_stats_in "$ENV_PG" "$NEW_HULY"
    sed -i '' "s/STATS_VERSION:-s[0-9.]*}/STATS_VERSION:-s${NEW_HULY#v}}/g" "$COOLIFY_YAML"
    echo "  HULY_VERSION -> ${NEW_HULY} (blueprints + coolify)"
    echo "  STATS_VERSION -> s${NEW_HULY#v}"
    echo ""
    echo "Auto-bumping template patch versions..."
    bump_template "$TOML_NEXT" "patch" "huly-v7-next"
    bump_template "$TOML_PG" "patch" "huly-v7-pg"
    ;;
  status|"")
    show_status
    exit 0
    ;;
  *)
    echo "Usage: $0 [next|pg|patch|minor|major|huly <vX.Y.Z>|status]"
    echo ""
    echo "Commands:"
    echo "  patch              Bump both v7-next + v7-pg patch version (default)"
    echo "  minor              Bump both minor versions"
    echo "  major              Bump both major versions"
    echo "  next [patch]       Bump only v7-next (default: patch)"
    echo "  pg [patch]         Bump only v7-pg (default: patch)"
    echo "  huly v0.7.360      Update Huly upstream images in both + auto patch"
    echo "  status             Show current versions"
    echo ""
    show_status
    exit 1
    ;;
esac

echo ""
echo "Done."
