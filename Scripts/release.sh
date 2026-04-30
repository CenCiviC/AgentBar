#!/usr/bin/env bash
# Build a release, tag it, and publish to GitHub Releases.
#
# Usage:
#   ./Scripts/release.sh patch             # 1.0.0 → 1.0.1
#   ./Scripts/release.sh minor             # 1.0.0 → 1.1.0
#   ./Scripts/release.sh major             # 1.0.0 → 2.0.0
#   ./Scripts/release.sh patch --draft
#   ./Scripts/release.sh patch --notes "fixes a bug"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

# shellcheck source=../version.env
source version.env

APP_NAME="AgentBar"
REPO="CenCiviC/AgentBar"

# ── argument parsing ──────────────────────────────────────────────────────────

BUMP=""
DRAFT=false
NOTES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        major|minor|patch) BUMP="$1"; shift ;;
        --draft)           DRAFT=true; shift ;;
        --notes)           NOTES="$2"; shift 2 ;;
        *) echo "Usage: release.sh [major|minor|patch] [--draft] [--notes <msg>]" >&2; exit 1 ;;
    esac
done

# ── version bump ──────────────────────────────────────────────────────────────

if [[ -n "${BUMP}" ]]; then
    IFS='.' read -r MAJOR MINOR PATCH <<< "${VERSION}"
    case "${BUMP}" in
        major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
        minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
        patch) PATCH=$((PATCH + 1)) ;;
    esac
    VERSION="${MAJOR}.${MINOR}.${PATCH}"
    BUILD=$((BUILD + 1))

    printf 'VERSION=%s\nBUILD=%s\n' "${VERSION}" "${BUILD}" > version.env
    echo "==> Bumped to v${VERSION} (build ${BUILD})"
fi

TAG="v${VERSION}"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
[[ -z "${NOTES}" ]] && NOTES="Release ${TAG}"

# ── preflight ─────────────────────────────────────────────────────────────────

if ! command -v gh &>/dev/null; then
    echo "error: gh CLI not found — install with: brew install gh" >&2
    exit 1
fi

# Allow a dirty tree only when we just wrote version.env
DIRTY=$(git status --porcelain | grep -v '^.M version.env' || true)
if [[ -n "${DIRTY}" ]]; then
    echo "error: working directory is dirty — commit or stash changes first" >&2
    exit 1
fi

if git rev-parse "${TAG}" &>/dev/null; then
    echo "error: tag ${TAG} already exists" >&2
    exit 1
fi

# ── commit bumped version ─────────────────────────────────────────────────────

if [[ -n "${BUMP}" ]]; then
    git add version.env
    git commit -m "chore: bump version to ${VERSION}"
fi

# ── build ─────────────────────────────────────────────────────────────────────

echo "==> Building ${APP_NAME} ${VERSION} (build ${BUILD})"
"${SCRIPT_DIR}/build-app.sh"

# ── zip ───────────────────────────────────────────────────────────────────────

echo "==> Creating ${ZIP_NAME}"
cd build
zip -r --symlinks "${PROJECT_DIR}/${ZIP_NAME}" "${APP_NAME}.app"
cd "${PROJECT_DIR}"

# ── publish ───────────────────────────────────────────────────────────────────

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
