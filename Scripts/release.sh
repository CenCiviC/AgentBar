#!/usr/bin/env bash
# Build a release, tag it, and publish to GitHub Releases.
# Usage: ./Scripts/release.sh [--draft] [--notes "release notes"]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

# shellcheck source=../version.env
source version.env

APP_NAME="AgentBar"
REPO="CenCiviC/AgentBar"
TAG="v${VERSION}"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"

DRAFT=false
NOTES="Release ${TAG}"
while [[ $# -gt 0 ]]; do
    case $1 in
        --draft)  DRAFT=true; shift ;;
        --notes)  NOTES="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Preflight checks
if ! command -v gh &>/dev/null; then
    echo "error: gh CLI not found. Install with: brew install gh" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working directory is dirty — commit or stash changes first" >&2
    exit 1
fi
if git rev-parse "${TAG}" &>/dev/null; then
    echo "error: tag ${TAG} already exists" >&2
    exit 1
fi

# Build
echo "==> Building ${APP_NAME} ${VERSION} (build ${BUILD})"
"${SCRIPT_DIR}/build-app.sh"

# Zip
echo "==> Creating ${ZIP_NAME}"
cd build
zip -r --symlinks "${PROJECT_DIR}/${ZIP_NAME}" "${APP_NAME}.app"
cd "${PROJECT_DIR}"

# Tag & publish
echo "==> Creating GitHub release ${TAG}"
DRAFT_FLAG=""
${DRAFT} && DRAFT_FLAG="--draft"

# shellcheck disable=SC2086
gh release create "${TAG}" "${ZIP_NAME}" \
    --repo "${REPO}" \
    --title "${TAG}" \
    --notes "${NOTES}" \
    ${DRAFT_FLAG}

rm "${ZIP_NAME}"
echo "==> Done: https://github.com/${REPO}/releases/tag/${TAG}"
