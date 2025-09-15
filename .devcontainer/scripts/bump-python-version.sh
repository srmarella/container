#!/usr/bin/env bash
set -euo pipefail

# "Dumb it down" purpose:
# This script updates the Python version in the Dockerfile (both builder & runtime ARGs).
# It no longer edits devcontainer.json (single source of truth is Dockerfile now).
# It DOES NOT automatically fetch the SHA256. Supply it manually with -s if you want integrity checking.
#
# Usage:
#   ./bump-python-version.sh -v 3.12.4
#   ./bump-python-version.sh -v 3.12.4 -s <sha256sum>
# After running, rebuild the container (Dev Containers: Rebuild) to apply.

VERSION=""
SHA256=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)
      VERSION="$2"; shift 2;;
    -s|--sha256)
      SHA256="$2"; shift 2;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# //'; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "ERROR: Provide -v <version> (e.g. 3.12.4)" >&2
  exit 1
fi

DOCKERFILE="$(dirname "$0")/../Dockerfile"

echo "[*] Updating Python version to $VERSION"

# Update Dockerfile ARG (builder + runtime stage) - simplistic sed replace.
sed -i.bak -E "0,/ARG PYTHON_VERSION=/s/ARG PYTHON_VERSION=[0-9.]+/ARG PYTHON_VERSION=${VERSION}/" "$DOCKERFILE"
sed -i.bak -E "s/ARG PYTHON_VERSION=[0-9.]+/ARG PYTHON_VERSION=${VERSION}/g" "$DOCKERFILE"

if [[ -n "$SHA256" ]]; then
  echo "[info] Remember to pass --build-arg PYTHON_SHA256=${SHA256} during rebuild to enable verification." >&2
fi

rm -f "$DOCKERFILE".bak

echo "[+] Done. Now rebuild the dev container to compile Python ${VERSION}."
