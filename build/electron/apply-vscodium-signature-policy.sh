#!/usr/bin/env bash
# Keep the VS Code 1.136 / Electron 42 path aligned with VSCodium's policy of
# not performing Marketplace extension signature verification.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VSCODE_DIR="${REPO_ROOT}/vscode"
PATCH_PATH="${REPO_ROOT}/patches/00-extension-disable-signature-verification.patch"
TARGET_FILE="${VSCODE_DIR}/src/vs/platform/extensionManagement/node/extensionManagementService.ts"

if [[ ! -d "${VSCODE_DIR}/.git" ]]; then
  echo "VS Code source tree is missing: ${VSCODE_DIR}" >&2
  exit 1
fi

if [[ ! -f "${PATCH_PATH}" ]]; then
  echo "Signature policy patch is missing: ${PATCH_PATH}" >&2
  exit 1
fi

if [[ ! -f "${TARGET_FILE}" ]]; then
  echo "Extension management source is missing: ${TARGET_FILE}" >&2
  exit 1
fi

# Idempotent for diagnostics/retries in the same working tree.
if grep -Fq 'verifySignature = false;' "${TARGET_FILE}"; then
  echo "VSCodium extension signature policy is already applied"
  exit 0
fi

(
  cd "${VSCODE_DIR}"
  git apply --check --ignore-whitespace "${PATCH_PATH}"
  git apply --ignore-whitespace "${PATCH_PATH}"
)

if ! grep -Fq 'verifySignature = false;' "${TARGET_FILE}"; then
  echo "Signature policy patch applied but expected verification-disable assignment was not found" >&2
  exit 1
fi

if grep -Fq 'VerifyExtensionSignatureConfigKey' "${TARGET_FILE}"; then
  echo "Signature policy patch left VerifyExtensionSignatureConfigKey in extensionManagementService.ts" >&2
  exit 1
fi

echo "VSCodium extension signature verification is explicitly disabled"
