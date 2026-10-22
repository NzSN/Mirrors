#!/usr/bin/env bash
# Publish only after the build job and isolated runtime smoke have succeeded.
set -euo pipefail

: "${RELEASE_TAG:?}" "${SOURCE_COMMIT:?}" "${GH_REPO:?}" "${GH_TOKEN:?}"
: "${HISTORICAL:?}" "${PRERELEASE:?}"
release_tools_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_assets_dir="${1:-artifacts}"

(cd "$release_assets_dir" && sha256sum --check SHA256SUMS)
python3 "$release_tools_dir/release.py" verify-remote --repository "$GH_REPO" \
  --tag "$RELEASE_TAG" --commit "$SOURCE_COMMIT"

if gh release view "$RELEASE_TAG" > /dev/null 2>&1; then
  echo "Release or draft already exists for $RELEASE_TAG; refusing to replace it." >&2
  exit 1
fi

publish_flags=(--latest)
if [[ "$HISTORICAL" == true || "$PRERELEASE" == true ]]; then
  publish_flags=(--latest=false)
fi
draft_flags=(--latest=false)
if [[ "$PRERELEASE" == true ]]; then
  publish_flags+=(--prerelease)
  draft_flags+=(--prerelease)
fi

# Upload failure leaves a draft, never a published release missing its assets.
gh release create "$RELEASE_TAG" \
  "$release_assets_dir/mirrors-$RELEASE_TAG-linux-x86_64.tar.gz" \
  "$release_assets_dir/mirrors-$RELEASE_TAG-linux-x86_64.build.json" \
  "$release_assets_dir/SHA256SUMS" \
  --verify-tag --draft --title "Mirrors $RELEASE_TAG" \
  --generate-notes --notes-file "$release_assets_dir/release-notes.txt" "${draft_flags[@]}"
python3 "$release_tools_dir/release.py" verify-remote --repository "$GH_REPO" \
  --tag "$RELEASE_TAG" --commit "$SOURCE_COMMIT"
gh release edit "$RELEASE_TAG" --draft=false "${publish_flags[@]}"
