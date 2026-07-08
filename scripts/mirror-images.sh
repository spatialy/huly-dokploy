#!/bin/bash
# Mirror all images used by the huly-v7-pg blueprint to a registry you control.
#
# Why: the entire stack is pulled from the `hardcoreeng` Docker Hub org. With the
# hosted huly.app service winding down (July 2026), a mirror protects existing
# deployments against those images becoming unavailable — a redeploy or server
# move would otherwise fail at `docker pull`.
#
# Usage:
#   ./scripts/mirror-images.sh <target>                 # mirror everything
#   ./scripts/mirror-images.sh <target> --huly-only     # only hardcoreeng/* images
#   ./scripts/mirror-images.sh <target> --dry-run       # print the plan, copy nothing
#
#   <target> is a registry/namespace you own, e.g. ghcr.io/youruser/huly
#
# Authenticate first:
#   docker login ghcr.io        (or: skopeo login ghcr.io)
#   GHCR token needs the `write:packages` scope.
#
# Uses skopeo when available (copies all architectures without local disk),
# otherwise falls back to docker pull/tag/push.
#
# After mirroring, point a deployment at the mirror by setting:
#   HULY_IMAGE_PREFIX=ghcr.io/youruser/huly
# This switches all hardcoreeng/* images. Infra images (nginx, postgres, redis,
# elastic, minio, mongo, redpanda, livekit) are also mirrored for completeness,
# but switching those requires editing the image lines in the compose file.

set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:?Usage: $0 <target-registry/namespace> [--huly-only] [--dry-run]}"
shift
HULY_ONLY=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --huly-only) HULY_ONLY=true ;;
    --dry-run)   DRY_RUN=true ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

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
if command -v skopeo >/dev/null 2>&1; then
  USE_SKOPEO=true
  echo "Using skopeo (multi-arch copy, no local storage)."
elif [ "$DRY_RUN" = false ]; then
  command -v docker >/dev/null 2>&1 || { echo "Need skopeo or docker installed." >&2; exit 1; }
  echo "skopeo not found — falling back to docker pull/tag/push (host architecture only)."
fi
echo

FAILED=""
for src in $IMAGES; do
  # Target keeps only name:tag — hardcoreeng/account:v0.7.426 -> <target>/account:v0.7.426
  name_tag="${src##*/}"
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

  echo "==> ${src_ref}  ->  ${dst}"
  [ "$DRY_RUN" = true ] && continue

  if [ "$USE_SKOPEO" = true ]; then
    skopeo copy --all "docker://${src_ref}" "docker://${dst}" || FAILED="${FAILED} ${src}"
  else
    { docker pull "$src" && docker tag "$src" "$dst" && docker push "$dst"; } || FAILED="${FAILED} ${src}"
  fi
done

echo
if [ -n "$FAILED" ]; then
  echo "FAILED to mirror:${FAILED}" >&2
  exit 1
fi
if [ "$DRY_RUN" = true ]; then
  echo "Dry run complete — nothing copied."
else
  echo "Done. ${COUNT} images mirrored to ${TARGET}."
  echo "Point deployments at the mirror with: HULY_IMAGE_PREFIX=${TARGET}"
fi
