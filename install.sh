#!/usr/bin/env bash
# Install or update AgentBar.
# Usage: curl -fsSL https://raw.githubusercontent.com/CenCiviC/AgentBar/main/install.sh | bash
set -euo pipefail

REPO="CenCiviC/AgentBar"
APP_NAME="AgentBar"
INSTALL_DIR="${HOME}/Applications"
APP_PATH="${INSTALL_DIR}/${APP_NAME}.app"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# ── helpers ──────────────────────────────────────────────────────────────────

need() {
    if ! command -v "$1" &>/dev/null; then
        echo "error: '$1' is required but not found" >&2
        exit 1
    fi
}

installed_version() {
    defaults read "${APP_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.0"
}

# ── preflight ────────────────────────────────────────────────────────────────

need curl
need unzip

# ── fetch latest release info ─────────────────────────────────────────────────

echo "==> Checking latest version..."
RELEASE_JSON=$(curl -fsSL "${API_URL}")
LATEST_TAG=$(echo "${RELEASE_JSON}" | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
LATEST_VERSION="${LATEST_TAG#v}"
ZIP_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${APP_NAME}-${LATEST_VERSION}.zip"

# ── version check ─────────────────────────────────────────────────────────────

if [[ -d "${APP_PATH}" ]]; then
    CURRENT=$(installed_version)
    if [[ "${CURRENT}" == "${LATEST_VERSION}" ]]; then
        echo "==> Already up to date (v${CURRENT})"
        exit 0
    fi
    echo "==> Updating ${APP_NAME}: v${CURRENT} → v${LATEST_VERSION}"
else
    echo "==> Installing ${APP_NAME} v${LATEST_VERSION}"
    mkdir -p "${INSTALL_DIR}"
fi

# ── download & install ────────────────────────────────────────────────────────

TMP_ZIP=$(mktemp /tmp/AgentBar.XXXXXX.zip)
TMP_DIR=$(mktemp -d /tmp/AgentBar.XXXXXX)

trap 'rm -rf "${TMP_ZIP}" "${TMP_DIR}"' EXIT

echo "==> Downloading..."
curl -fsSL --progress-bar "${ZIP_URL}" -o "${TMP_ZIP}"

echo "==> Installing to ${INSTALL_DIR}..."
unzip -q "${TMP_ZIP}" -d "${TMP_DIR}"
rm -rf "${APP_PATH}"
mv "${TMP_DIR}/${APP_NAME}.app" "${APP_PATH}"

# Remove Gatekeeper quarantine so the app opens without a warning dialog
xattr -dr com.apple.quarantine "${APP_PATH}" 2>/dev/null || true

# ── launch ───────────────────────────────────────────────────────────────────

echo "==> Done — v${LATEST_VERSION} installed at ${APP_PATH}"
open "${APP_PATH}"
