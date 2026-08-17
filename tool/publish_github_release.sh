#!/usr/bin/env bash

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
: "${RELEASE_NAME:?RELEASE_NAME is required}"
: "${RELEASE_PRERELEASE:?RELEASE_PRERELEASE is required}"

max_attempts="${RELEASE_MAX_ATTEMPTS:-7}"
retry_delay="${RELEASE_INITIAL_RETRY_DELAY:-15}"
max_retry_delay="${RELEASE_MAX_RETRY_DELAY:-120}"

if ! [[ "$max_attempts" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::RELEASE_MAX_ATTEMPTS must be a positive integer."
  exit 1
fi
if ! [[ "$retry_delay" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::RELEASE_INITIAL_RETRY_DELAY must be a positive integer."
  exit 1
fi
if ! [[ "$max_retry_delay" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::RELEASE_MAX_RETRY_DELAY must be a positive integer."
  exit 1
fi
if [[ ! -s release-notes.md ]]; then
  echo "::error::release-notes.md is missing or empty."
  exit 1
fi

next_retry_delay() {
  retry_delay=$((retry_delay * 2))
  if ((retry_delay > max_retry_delay)); then
    retry_delay="$max_retry_delay"
  fi
}

release_ready=false
for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  echo "Release metadata attempt $attempt of $max_attempts for $RELEASE_TAG"

  if gh release view "$RELEASE_TAG" \
    --repo "$GITHUB_REPOSITORY" > /dev/null 2>&1; then
    edit_args=(
      release edit "$RELEASE_TAG"
      --repo "$GITHUB_REPOSITORY"
      --title "$RELEASE_NAME"
      --notes-file release-notes.md
    )
    if [[ "$RELEASE_PRERELEASE" == "true" ]]; then
      edit_args+=(--prerelease)
    else
      edit_args+=(--prerelease=false)
    fi
    if gh "${edit_args[@]}"; then
      release_ready=true
      break
    fi
  else
    create_args=(
      release create "$RELEASE_TAG"
      --repo "$GITHUB_REPOSITORY"
      --title "$RELEASE_NAME"
      --notes-file release-notes.md
      --target "$GITHUB_SHA"
    )
    if [[ "$RELEASE_PRERELEASE" == "true" ]]; then
      create_args+=(--prerelease)
    fi
    if gh "${create_args[@]}"; then
      release_ready=true
      break
    fi
  fi

  if ((attempt < max_attempts)); then
    echo "::warning::GitHub Releases API is unavailable; retrying in ${retry_delay}s."
    sleep "$retry_delay"
    next_retry_delay
  fi
done

if [[ "$release_ready" != "true" ]]; then
  echo "::error::GitHub Releases API remained unavailable after $max_attempts attempts."
  exit 1
fi

mapfile -d '' release_assets < <(
  find release-assets -maxdepth 1 -type f -print0
)
if ((${#release_assets[@]} == 0)); then
  echo "::error::No release assets were found for the fallback upload."
  exit 1
fi

retry_delay="${RELEASE_INITIAL_RETRY_DELAY:-15}"
assets_uploaded=false
for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  echo "Release asset upload attempt $attempt of $max_attempts"
  if gh release upload "$RELEASE_TAG" "${release_assets[@]}" \
    --repo "$GITHUB_REPOSITORY" --clobber; then
    assets_uploaded=true
    break
  fi
  if ((attempt < max_attempts)); then
    echo "::warning::Release asset upload failed; retrying in ${retry_delay}s."
    sleep "$retry_delay"
    next_retry_delay
  fi
done

if [[ "$assets_uploaded" != "true" ]]; then
  echo "::error::Release assets could not be uploaded after $max_attempts attempts."
  exit 1
fi
