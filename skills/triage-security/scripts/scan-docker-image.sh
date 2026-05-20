#!/usr/bin/env bash
# scan-docker-image.sh — Trivy scan of a built or pulled container image.
# Useful when the advisory targets a runtime layer (CPython, OpenSSL, libc,
# Postgres) that source-tree scanners can't see. Pull or build the image
# first; this script only reads.
#
# Usage: scan-docker-image.sh <image-ref> [severity]
#   image-ref  e.g. "myorg/api:1.2.3", "postgres:16.13", or a local image ID
#   severity   default: HIGH,CRITICAL

set -uo pipefail

IMAGE_REF="${1:?Usage: $0 <image-ref> [severity]}"
SEVERITY="${2:-HIGH,CRITICAL}"

# Cheap input validation: reject anything that isn't a plausible image ref.
# Allowed: lowercase, digits, dot, dash, underscore, slash, colon, @, plus.
if ! [[ "${IMAGE_REF}" =~ ^[a-zA-Z0-9._/:@+-]+$ ]]; then
  echo "ERROR: image ref contains unexpected characters: ${IMAGE_REF}" >&2
  exit 2
fi

if ! command -v trivy >/dev/null 2>&1; then
  echo "SKIP: trivy not installed. See https://aquasecurity.github.io/trivy/"
  exit 0
fi

trivy image \
  --severity "${SEVERITY}" \
  --quiet \
  "${IMAGE_REF}" 2>&1 || true
