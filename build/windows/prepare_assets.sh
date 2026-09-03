#!/usr/bin/env bash

set -ex

cd vscode || { echo "'vscode' dir not found"; exit 1; }

echo "==> installer stage: inno updater"
npm run gulp "vscode-win32-${VSCODE_ARCH}-inno-updater"

# . ../build/windows/appx/build.sh

if [[ "${SHOULD_BUILD_ZIP}" != "no" ]]; then
  echo "==> installer stage: portable zip"
  7z.exe a -tzip "../assets/${APP_NAME}-win32-${VSCODE_ARCH}-${RELEASE_VERSION}.zip" -x!CodeSignSummary*.md -x!tools "../VSCode-win32-${VSCODE_ARCH}/*" -r
fi

if [[ "${SHOULD_BUILD_EXE_SYS}" != "no" ]]; then
  echo "==> installer stage: system setup"
  npm run gulp "vscode-win32-${VSCODE_ARCH}-system-setup"
fi

if [[ "${SHOULD_BUILD_EXE_USR}" != "no" ]]; then
  echo "==> installer stage: user setup"
  npm run gulp "vscode-win32-${VSCODE_ARCH}-user-setup"
fi

if [[ "${VSCODE_ARCH}" == "ia32" || "${VSCODE_ARCH}" == "x64" ]]; then
  if [[ "${SHOULD_BUILD_MSI}" != "no" ]]; then
    echo "==> installer stage: MSI"
    . ../build/windows/msi/build.sh
  fi

  if [[ "${SHOULD_BUILD_MSI_NOUP}" != "no" ]]; then
    echo "==> installer stage: MSI updates-disabled"
    . ../build/windows/msi/build-updates-disabled.sh
  fi
fi

cd ..

if [[ "${SHOULD_BUILD_EXE_SYS}" != "no" ]]; then
  echo "Moving System EXE"
  mv "vscode\\.build\\win32-${VSCODE_ARCH}\\system-setup\\VSCodeSetup.exe" "assets\\${APP_NAME}Setup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
fi

if [[ "${SHOULD_BUILD_EXE_USR}" != "no" ]]; then
  echo "Moving User EXE"
  mv "vscode\\.build\\win32-${VSCODE_ARCH}\\user-setup\\VSCodeSetup.exe" "assets\\${APP_NAME}UserSetup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
fi

if [[ "${VSCODE_ARCH}" == "ia32" || "${VSCODE_ARCH}" == "x64" ]]; then
  if [[ "${SHOULD_BUILD_MSI}" != "no" ]]; then
    echo "Moving MSI"
    mv "build\\windows\\msi\\releasedir\\${APP_NAME}-${VSCODE_ARCH}-${RELEASE_VERSION}.msi" assets/
  fi

  if [[ "${SHOULD_BUILD_MSI_NOUP}" != "no" ]]; then
    echo "Moving MSI with disabled updates"
    mv "build\\windows\\msi\\releasedir\\${APP_NAME}-${VSCODE_ARCH}-updates-disabled-${RELEASE_VERSION}.msi" assets/
  fi
fi
