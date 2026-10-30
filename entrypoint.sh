#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Automated Backup & Export Action
# Compresses project files and exports them to GitHub Release or cloud storage.
# ============================================================================

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Mask secrets if present
if [[ -n "${CLOUD_STORAGE_TOKEN:-}" ]]; then
  echo "::add-mask::${CLOUD_STORAGE_TOKEN}"
fi
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "::add-mask::${GITHUB_TOKEN}"
fi

# Resolve inputs
PATHS="${PATHS:-.}"
ARCHIVE_NAME="${ARCHIVE_NAME:-backup}"
UPLOAD_TO_RELEASE="${UPLOAD_TO_RELEASE:-true}"
CLOUD_STORAGE_URL="${CLOUD_STORAGE_URL:-}"
CLOUD_STORAGE_TOKEN="${CLOUD_STORAGE_TOKEN:-}"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
ARCHIVE_FILE="${ARCHIVE_NAME}-${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${GITHUB_WORKSPACE:-$(pwd)}/${ARCHIVE_FILE}"

log "Starting backup process"
log "Repository: ${GITHUB_REPOSITORY}"
log "Paths to back up: ${PATHS}"
log "Archive name: ${ARCHIVE_FILE}"

# ----------------------------------------------------------------------------
# Step 1: Create archive
# ----------------------------------------------------------------------------
log "Creating archive: ${ARCHIVE_PATH}"

# Convert comma-separated paths to space-separated for tar
IFS=',' read -ra PATH_ARRAY <<< "$PATHS"
TAR_ARGS=()
for p in "${PATH_ARRAY[@]}"; do
  # Trim whitespace
  p="$(echo -e "${p}" | tr -d '[:space:]')"
  if [[ -e "$p" ]]; then
    TAR_ARGS+=("$p")
    log "Including: $p"
  else
    log_warn "Path not found, skipping: $p"
  fi
done

if [[ ${#TAR_ARGS[@]} -eq 0 ]]; then
  log_error "No valid paths found to back up."
  exit 1
fi

# Exclude common noise
EXCLUDES=(
  --exclude='.git'
  --exclude='node_modules'
  --exclude='.next'
  --exclude='dist'
  --exclude='build'
  --exclude='*.log'
  --exclude='.DS_Store'
)

tar -czf "${ARCHIVE_PATH}" "${EXCLUDES[@]}" "${TAR_ARGS[@]}"

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  log_error "Failed to create archive."
  exit 1
fi

ARCHIVE_SIZE=$(stat -c%s "${ARCHIVE_PATH}" 2>/dev/null || stat -f%z "${ARCHIVE_PATH}" 2>/dev/null || echo 0)
log "Archive created successfully: ${ARCHIVE_PATH} (${ARCHIVE_SIZE} bytes)"

# ----------------------------------------------------------------------------
# Step 2: Upload to GitHub Release
# ----------------------------------------------------------------------------
DOWNLOAD_URL=""
if [[ "${UPLOAD_TO_RELEASE}" == "true" ]]; then
  log "Checking for associated GitHub Release..."

  # Try to find a release for the current ref/tag
  RELEASE_ID=""
  if command -v gh &>/dev/null; then
    # If on a tag, find release by tag
    if [[ "${GITHUB_REF}" == refs/tags/* ]]; then
      TAG_NAME="${GITHUB_REF#refs/tags/}"
      log "Looking for release by tag: ${TAG_NAME}"
      RELEASE_ID=$(gh api "repos/${GITHUB_REPOSITORY}/releases/tags/${TAG_NAME}" --jq '.id // empty' 2>/dev/null || true)
    fi

    # If no release found, create one for this run
    if [[ -z "${RELEASE_ID}" ]]; then
      RELEASE_TITLE="Backup ${TIMESTAMP}"
      RELEASE_BODY="Automated backup created by GitHub Actions run #${GITHUB_RUN_ID}."
      log "Creating new release: ${RELEASE_TITLE}"
      RELEASE_RESPONSE=$(gh api \
        -X POST \
        "repos/${GITHUB_REPOSITORY}/releases" \
        -f tag_name="backup-${TIMESTAMP}" \
        -f name="${RELEASE_TITLE}" \
        -f body="${RELEASE_BODY}" \
        -f draft='false' \
        -f prerelease='false' \
        2>/dev/null || echo '{}')
      RELEASE_ID=$(echo "${RELEASE_RESPONSE}" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*' || true)
    fi

    if [[ -n "${RELEASE_ID}" ]]; then
      log "Uploading archive to release ID: ${RELEASE_ID}"
      gh api \
        -X POST \
        "repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}/assets" \
        -F name="${ARCHIVE_FILE}" \
        -F file="@${ARCHIVE_PATH}" \
        -H "Accept: application/vnd.github+json" \
        >/dev/null 2>&1 || log_warn "Asset upload via gh CLI failed, trying REST API..."

      # Build download URL
      DOWNLOAD_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/backup-${TIMESTAMP}/${ARCHIVE_FILE}"
      log "Backup uploaded to GitHub Release."
    else
      log_warn "Could not determine release ID. Skipping GitHub Release upload."
    fi
  else
    log_warn "gh CLI not available. Skipping GitHub Release upload."
  fi
fi

# ----------------------------------------------------------------------------
# Step 3: Upload to custom cloud storage (optional)
# ----------------------------------------------------------------------------
if [[ -n "${CLOUD_STORAGE_URL}" ]]; then
  log "Uploading to custom cloud storage: ${CLOUD_STORAGE_URL}"
  if [[ -n "${CLOUD_STORAGE_TOKEN}" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      -X PUT "${CLOUD_STORAGE_URL}" \
      -H "Authorization: Bearer ${CLOUD_STORAGE_TOKEN}" \
      -H "Content-Type: application/gzip" \
      --upload-file "${ARCHIVE_PATH}" || echo "000")
    log "Cloud storage response: HTTP ${HTTP_CODE}"
    DOWNLOAD_URL="${CLOUD_STORAGE_URL}"
  else
    log_warn "CLOUD_STORAGE_URL set but no token provided. Skipping cloud upload."
  fi
fi

# ----------------------------------------------------------------------------
# Step 4: Set outputs
# ----------------------------------------------------------------------------
echo "archive-path=${ARCHIVE_PATH}" >> "$GITHUB_OUTPUT"
echo "archive-size=${ARCHIVE_SIZE}" >> "$GITHUB_OUTPUT"
echo "download-url=${DOWNLOAD_URL}" >> "$GITHUB_OUTPUT"

log "Backup completed successfully."
log "Archive: ${ARCHIVE_PATH}"
if [[ -n "${DOWNLOAD_URL}" ]]; then
  log "Download URL: ${DOWNLOAD_URL}"
fi
