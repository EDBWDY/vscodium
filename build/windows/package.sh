#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

if [[ "${CI_BUILD}" == "no" ]]; then
  exit 1
fi

tar -xzf ./vscode.tar.gz

cd vscode || { echo "'vscode' dir not found"; exit 1; }

for i in {1..5}; do # try 5 times
  npm ci && break
  if [[ $i == 5 ]]; then
    echo "Npm install failed too many times" >&2
    exit 1
  fi
  echo "Npm install failed $i, trying again..."
done

node build/azure-pipelines/distro/mixin-npm.ts

# delete native files built in the `compile` step
find .build/extensions -type f -name '*.node' -print -delete

. ../build/windows/rtf/make.sh

# generate Group Policy definitions
npm run copy-policy-dto --prefix build
node build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc win32

# node build/win32/explorer-dll-fetcher.ts .build/win32/appx

npm run gulp "vscode-win32-${VSCODE_ARCH}-min-packing"

# The Copilot SDK entrypoints are intentionally excluded from VS Code's
# generic extension stream by build/.moduleignore, but the built-in Copilot
# extension loads them directly at runtime.  Restore the complete SDK tree
# after the normal min-packing step, before the desktop and installer assets
# consume .build/extensions.
copilot_sdk_source='extensions/copilot/node_modules/@github/copilot/sdk'
copilot_sdk_output='.build/extensions/copilot/node_modules/@github/copilot/sdk'
test -f "${copilot_sdk_source}/index.js"
mkdir -p "$(dirname "${copilot_sdk_output}")"
rm -rf "${copilot_sdk_output}"
cp -a "${copilot_sdk_source}" "${copilot_sdk_output}"
test -f "${copilot_sdk_output}/index.js"

. ../build_cli.sh

if [[ "${VSCODE_ARCH}" == "x64" ]]; then
  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    echo "Building REH"
    npm run gulp minify-vscode-reh
    npm run gulp "vscode-reh-win32-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    echo "Building REH-web"
    npm run gulp minify-vscode-reh-web
    npm run gulp "vscode-reh-web-win32-${VSCODE_ARCH}-min-ci"
  fi
fi

cd ..
