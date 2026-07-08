#!/bin/bash
# Mirror all images used by the huly-v7-pg blueprint to a registry you control.
#
# Why: the entire stack is pulled from the `hardcoreeng` Docker Hub org. With the
# hosted huly.app service winding down (July 2026), a mirror protects existing
# deployments against those images becoming unavailable — a redeploy or server
# move would otherwise fail at `docker pull`.
#
# Usage:
#   ./scripts/mirror-images.sh <target>                    # mirror everything
#   ./scripts/mirror-images.sh <target> --huly-only        # only hardcoreeng/* images
#   ./scripts/mirror-images.sh <target> --dry-run          # print the plan, copy nothing
#   ./scripts/mirror-images.sh <target> --skip-existing    # resume: skip images already
#                                                          # mirrored with matching digest
#   ./scripts/mirror-images.sh <target> --public           # also set each GHCR package
#                                                          # to public after copying
#   ./scripts/mirror-images.sh <target> --visibility-only  # skip copying; only set
#                                                          # visibility on existing packages
#
#   <target> is a registry/namespace you own, e.g. ghcr.io/youruser/huly
#
# Authenticate to BOTH ends first:
#   skopeo login ghcr.io          (or: docker login ghcr.io — write:packages scope)
#   skopeo login docker.io        (or: docker login — free Docker Hub account)
#
# Docker Hub rate limits: anonymous pulls are capped at 100/6h per IP, and a full
# multi-arch mirror needs ~120 manifest pulls. A free authenticated Docker Hub
# account (200 pulls/6h) fits a full run; if a run is interrupted by the limit,
# wait for the window and resume with --skip-existing (it verifies against the
# mirror first, so already-copied images cost no Docker Hub pulls).
#
# Uses skopeo when available (copies all architectures without local disk),
# otherwise falls back to docker pull/tag/push. Strongly prefer skopeo:
# the docker fallback needs ~2 GB of free space in /var/lib/docker (images are
# removed after each push), and only copies the host architecture.
#
# GHCR creates every new package PRIVATE by default, regardless of the source
# repo's visibility — this is a per-package platform default, not something this
# script controls until you ask it to. Use --public (or --visibility-only to fix
# already-mirrored packages without re-copying) to flip packages to public, which
# keeps GHCR storage/bandwidth free and lets servers pull without credentials.
# Requires a GitHub token in $GH_TOKEN (or $GITHUB_TOKEN): classic PAT with the
# read:packages + write:packages scopes, or a fine-grained PAT with "Packages:
# read and write" permission — generate one at https://github.com/settings/tokens.
# If <target>'s owner is a GitHub organization (not a personal account), also
# pass --org.
#
# After mirroring, point a deployment at the mirror by setting:
#   HULY_IMAGE_PREFIX=ghcr.io/youruser/huly
# This switches all hardcoreeng/* images. Infra images (nginx, postgres, redis,
# elastic, minio, mongo, redpanda, livekit) are also mirrored for completeness,
# but switching those requires editing the image lines in the compose file.

set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:?Usage: $0 <target-registry/namespace> [--huly-only] [--dry-run] [--skip-existing] [--public] [--visibility-only] [--org]}"
shift
HULY_ONLY=false
DRY_RUN=false
SKIP_EXISTING=false
SET_PUBLIC=false
VISIBILITY_ONLY=false
IS_ORG=false
for arg in "$@"; do
  case "$arg" in
    --huly-only)       HULY_ONLY=true ;;
    --dry-run)         DRY_RUN=true ;;
    --skip-existing)   SKIP_EXISTING=true ;;
    --public)          SET_PUBLIC=true ;;
    --visibility-only) VISIBILITY_ONLY=true; SET_PUBLIC=true ;;
    --org)             IS_ORG=true ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

if [ "$SET_PUBLIC" = true ] && [ "$DRY_RUN" = false ]; then
  GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [ -z "$GH_TOKEN" ]; then
    echo "--public/--visibility-only needs a GitHub token in \$GH_TOKEN or \$GITHUB_TOKEN" >&2
    echo "(classic PAT with read:packages + write:packages, or fine-grained PAT with Packages: read and write)" >&2
    exit 1
  fi
fi

# Parse the GHCR owner and package-path prefix out of the target, e.g.
# ghcr.io/spatialy/huly -> owner=spatialy, prefix=huly
GHCR_OWNER=""
GHCR_PREFIX=""
if [ "$SET_PUBLIC" = true ]; then
  case "$TARGET" in
    ghcr.io/*)
      rest="${TARGET#ghcr.io/}"
      GHCR_OWNER="${rest%%/*}"
      GHCR_PREFIX="${rest#*/}"
      [ "$GHCR_PREFIX" = "$rest" ] && GHCR_PREFIX=""
      ;;
    *)
      echo "--public/--visibility-only only supports ghcr.io targets" >&2
      exit 1
      ;;
  esac
fi

# Sets a GHCR package to public via the GitHub API. $1 = image name (no tag).
set_package_public() {
  local image="$1"
  local pkg_name="${GHCR_PREFIX:+${GHCR_PREFIX}/}${image}"
  local pkg_encoded="${pkg_name//\//%2F}"
  local api_base="https://api.github.com/user/packages"
  [ "$IS_ORG" = true ] && api_base="https://api.github.com/orgs/${GHCR_OWNER}/packages"

  local http_code
  http_code=$(curl -sS -o /tmp/ghcr-visibility-resp.$$ -w '%{http_code}' -X PATCH \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${api_base}/container/${pkg_encoded}" \
    -d '{"visibility":"public"}') || http_code="000"

  if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
    echo "    -> public"
  else
    echo "    -> FAILED to set public (HTTP ${http_code}): $(cat /tmp/ghcr-visibility-resp.$$ 2>/dev/null | head -c 200)" >&2
    VISIBILITY_FAILED="${VISIBILITY_FAILED} ${pkg_name}"
  fi
  rm -f /tmp/ghcr-visibility-resp.$$
}
VISIBILITY_FAILED=""

COMPOSE="coolify/huly-v7-pg/docker-compose.yml"
ENV_EXAMPLE="coolify/huly-v7-pg/.env.example"

HULY_VERSION=$(grep -o '^HULY_VERSION=v[0-9.]*' "$ENV_EXAMPLE" | cut -d= -f2)
if [ -z "$HULY_VERSION" ]; then
  echo "Could not determine HULY_VERSION from $ENV_EXAMPLE" >&2
  exit 1
fi

echo "Huly version:  ${HULY_VERSION}"
echo "Mirror target: ${TARGET}"

# Collect image refs from the compose file and resolve compose variables
IMAGES=$(grep -E '^[[:space:]]*image:' "$COMPOSE" \
  | sed -e 's/.*image:[[:space:]]*//' -e 's/"//g' \
  | sed -e "s/\${HULY_VERSION}/${HULY_VERSION}/" \
        -e 's/${HULY_IMAGE_PREFIX:-hardcoreeng}/hardcoreeng/' \
  | sort -u)

if [ "$HULY_ONLY" = true ]; then
  IMAGES=$(echo "$IMAGES" | grep '^hardcoreeng/')
fi

COUNT=$(echo "$IMAGES" | grep -c .)
echo "Images to mirror: ${COUNT}"
echo

USE_SKOPEO=false
if [ "$VISIBILITY_ONLY" = true ]; then
  : # no copying involved — skip the skopeo/docker detection entirely
elif command -v skopeo >/dev/null 2>&1; then
  USE_SKOPEO=true
  echo "Using skopeo (multi-arch copy, no local storage)."
elif [ "$DRY_RUN" = false ]; then
  command -v docker >/dev/null 2>&1 || { echo "Need skopeo or docker installed." >&2; exit 1; }
  echo "skopeo not found — falling back to docker pull/tag/push (host architecture only)."
  [ "$SKIP_EXISTING" = true ] && echo "Note: --skip-existing requires skopeo — ignored; everything will be re-copied."
fi
echo

FAILED=""
for src in $IMAGES; do
  # Target keeps only name:tag — hardcoreeng/account:v0.7.426 -> <target>/account:v0.7.426
  name_tag="${src##*/}"
  image_name="${name_tag%%:*}"
  dst="${TARGET}/${name_tag}"

  # Fully-qualified source ref for skopeo: prefix docker.io unless the image
  # already names a registry (first path segment contains a dot or colon)
  if [[ "$src" != */* ]]; then
    src_ref="docker.io/library/${src}"
  else
    first="${src%%/*}"
    case "$first" in
      *.*|*:*) src_ref="${src}" ;;
      *)       src_ref="docker.io/${src}" ;;
    esac
  fi

  if [ "$VISIBILITY_ONLY" = true ]; then
    echo "==> ${image_name}"
    [ "$DRY_RUN" = true ] && { echo "    -> would set public"; continue; }
    set_package_public "$image_name"
    continue
  fi

  echo "==> ${src_ref}  ->  ${dst}"
  [ "$DRY_RUN" = true ] && continue

  # Resume support: skip when the mirror already holds this exact manifest.
  # Checks the destination (GHCR) first so skipped images cost zero Docker Hub
  # pulls; only consults the source digest when the destination tag exists.
  if [ "$SKIP_EXISTING" = true ] && [ "$USE_SKOPEO" = true ]; then
    dst_digest=$(skopeo inspect --format '{{.Digest}}' "docker://${dst}" 2>/dev/null || true)
    if [ -n "$dst_digest" ]; then
      src_digest=$(skopeo inspect --format '{{.Digest}}' "docker://${src_ref}" 2>/dev/null || true)
      if [ -n "$src_digest" ] && [ "$src_digest" = "$dst_digest" ]; then
        echo "    already mirrored (digest match) — skipping"
        [ "$SET_PUBLIC" = true ] && set_package_public "$image_name"
        continue
      fi
    fi
  fi

  copy_ok=true
  if [ "$USE_SKOPEO" = true ]; then
    skopeo copy --all --retry-times 3 "docker://${src_ref}" "docker://${dst}" || copy_ok=false
  else
    # Remove each image locally after pushing — the full stack unpacks to 15-20 GB
    # and fills /var/lib/docker (or the Docker Desktop VM disk) otherwise.
    if { docker pull "$src" && docker tag "$src" "$dst" && docker push "$dst"; }; then
      docker rmi "$dst" "$src" >/dev/null 2>&1 || true
    else
      copy_ok=false
    fi
  fi

  if [ "$copy_ok" = true ]; then
    [ "$SET_PUBLIC" = true ] && set_package_public "$image_name"
  else
    FAILED="${FAILED} ${src}"
  fi
done

echo
if [ -n "$FAILED" ]; then
  echo "FAILED to mirror:${FAILED}" >&2
  exit 1
fi
if [ -n "$VISIBILITY_FAILED" ]; then
  echo "FAILED to set public:${VISIBILITY_FAILED}" >&2
  exit 1
fi
if [ "$DRY_RUN" = true ]; then
  echo "Dry run complete — nothing copied."
elif [ "$VISIBILITY_ONLY" = true ]; then
  echo "Done. ${COUNT} packages set to public in ${TARGET}."
else
  echo "Done. ${COUNT} images mirrored to ${TARGET}."
  [ "$SET_PUBLIC" = true ] && echo "All packages set to public."
  echo "Point deployments at the mirror with: HULY_IMAGE_PREFIX=${TARGET}"
fi
