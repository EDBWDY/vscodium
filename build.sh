#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

. version.sh

if [[ "${SHOULD_BUILD}" == "yes" ]]; then
  echo "MS_COMMIT=\"${MS_COMMIT}\""

  . prepare_vscode.sh

  # The current-upstream path deliberately skips most revision-specific
  # VSCodium patches. Re-apply the small, policy-only signature patch here so
  # every current-upstream target keeps VSCodium's normal behaviour: extension
  # signature verification is not performed.
  if [[ "${VSCODIUM_LATEST_UPSTREAM}" == "yes" ]]; then
    ./build/electron/apply-vscodium-signature-policy.sh
  fi

  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  export NODE_OPTIONS="--max-old-space-size=8192"
  export VSCODE_PUBLISH_COUNTER=1

  # Keep the latest-upstream path aligned with VS Code's current Windows CI:
  # compile via core-ci before invoking the platform min-ci packaging task.
  npm run gulp core-ci

  # Latest VS Code is the build authority. In this mode VSCodium has already
  # applied its product branding in prepare_vscode.sh; do not run its legacy
  # CLI, remote-host, or secondary packaging stages.
  if [[ "${VSCODIUM_LATEST_UPSTREAM}" == "yes" && "${OS_NAME}" == "windows" ]]; then
    npm run gulp compile-copilot-extension-build

    # build/.moduleignore omits the Copilot SDK from the generic extension
    # stream, but the built-in desktop extension imports it at runtime.  The
    # Electron 42 Windows workflow packages directly from .build here, so the
    # SDK must be restored in this branch before min-ci consumes that tree.
    copilot_sdk_source='extensions/copilot/node_modules/@github/copilot'
    copilot_sdk_output='.build/extensions/copilot/node_modules/@github/copilot'
    test -f "${copilot_sdk_source}/sdk/index.js"
    test -s "${copilot_sdk_source}/package.json"
    mkdir -p "$(dirname "${copilot_sdk_output}")"
    rm -rf "${copilot_sdk_output}"
    cp -a "${copilot_sdk_source}" "${copilot_sdk_output}"
    test -f "${copilot_sdk_output}/sdk/index.js"
    node -e 'const p = require("./.build/extensions/copilot/node_modules/@github/copilot/package.json"); if (!p.version) process.exit(1)'

    # The copied extension package contains Mach-O/ELF native modules from
    # other platforms. VS Code's patchWin32DependenciesTask runs rcedit on
    # every packaged *.node, which requires a Windows PE (MZ) file.
    # Keep all Windows natives, and exclude only unusable non-PE modules.
    node - "$copilot_sdk_output" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const root = process.argv[2];
let removed = 0;
let kept = 0;
function visit(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const filename = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      visit(filename);
    } else if (entry.isFile() && entry.name.endsWith('.node')) {
      const fd = fs.openSync(filename, 'r');
      const signature = Buffer.alloc(2);
      try {
        fs.readSync(fd, signature, 0, 2, 0);
      } finally {
        fs.closeSync(fd);
      }
      if (signature.toString('ascii') === 'MZ') {
        kept++;
      } else {
        if (/win32/i.test(filename)) {
          throw new Error('Invalid Windows native Copilot module: ' + filename);
        }
        fs.rmSync(filename);
        console.log('Excluded non-Windows Copilot native module: ' + filename);
        removed++;
      }
    }
  }
}
visit(root);
console.log('Copilot native modules for Windows: kept=' + kept + ', excluded non-PE=' + removed);
NODE


    npm run copy-policy-dto --prefix build
    node build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc win32
    npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"
    cd ..
    exit 0
  fi

  if [[ "${OS_NAME}" == "osx" ]]; then
    # remove win32 node modules
    rm -f .build/extensions/ms-vscode.js-debug/src/win32-app-container-tokens.*.node

    # generate Group Policy definitions
    npm run copy-policy-dto --prefix build
    node build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc darwin

    npm run gulp "vscode-darwin-${VSCODE_ARCH}-min-packing"

    find "../VSCode-darwin-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

    . ../build_cli.sh

    VSCODE_PLATFORM="darwin"
  elif [[ "${OS_NAME}" == "windows" ]]; then
    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      . ../build/windows/rtf/make.sh

      # generate Group Policy definitions
      npm run copy-policy-dto --prefix build
      node build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc win32

      npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

      if [[ "${VSCODE_ARCH}" != "x64" ]]; then
        SHOULD_BUILD_REH="no"
        SHOULD_BUILD_REH_WEB="no"
      fi

      . ../build_cli.sh
    fi

    VSCODE_PLATFORM="win32"
  else # linux
    # remove win32 node modules
    rm -f .build/extensions/ms-vscode.js-debug/src/win32-app-container-tokens.*.node

    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      # generate Group Policy definitions
      npm run copy-policy-dto --prefix build
      node build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc linux

      npm run gulp "vscode-linux-${VSCODE_ARCH}-min-packing"

      find "../VSCode-linux-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

      . ../build_cli.sh
    fi

    VSCODE_PLATFORM="linux"
  fi

  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    npm run gulp minify-vscode-reh
    npm run gulp "vscode-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    npm run gulp minify-vscode-reh-web
    npm run gulp "vscode-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  cd ..
fi
