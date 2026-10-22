#!/usr/bin/env bash
# Print the latest stable OpenVPN release tag (vX.Y.Z) on stdout.
# usage: latest-openvpn-version.sh [series]   e.g. latest-openvpn-version.sh 2.6
# Reports on stderr whether the repository already has a patch for it.

set -euo pipefail

series="${1:-}"
if [[ -n "$series" && ! "$series" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 [series]   e.g. 2.7" >&2
  exit 1
fi

if [[ -n "$series" ]]; then
  pattern="^v${series//./\\.}\\.[0-9]+$"
else
  pattern='^v[0-9]+\.[0-9]+\.[0-9]+$'
fi

latest="$(git ls-remote --tags --refs https://github.com/OpenVPN/openvpn |
  sed -E 's#.*refs/tags/##' | { grep -E "$pattern" || true; } | sort -V | tail -n1)"

if [[ -z "$latest" ]]; then
  echo "No stable OpenVPN release found${series:+ for series $series}" >&2
  exit 1
fi

patch="$(dirname "$0")/openvpn-${latest}-aws.patch"
if [[ -f "$patch" ]]; then
  echo "$(basename "$patch") exists" >&2
else
  echo "$(basename "$patch") is missing: write the patch for ${latest}" >&2
fi

echo "$latest"
