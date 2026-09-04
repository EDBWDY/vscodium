# Electron 42.3.2 Linux x64 REH

This branch also carries a reproducible Linux x64 Remote Extension Host (REH) build that matches the Windows VSCodium client built from the same VS Code source revision.

## Pinned baseline

- VS Code tag: `1.136.0`
- VS Code commit: `520fb30b2d3d324b4cb2342f6e88e2cd93751de1`
- Windows client Electron: `42.3.2`
- CI Node.js: `24.18.0`
- Remote Node target: taken from the pinned VS Code `remote/.npmrc` during REH packaging
- Linux architecture: `x64`
- glibc compatibility check: `2.28`
- libstdc++ compatibility check: `GLIBCXX_3.4.26`

Electron itself does not run on the remote Linux host. The important compatibility boundary is that the Windows client and Linux REH are built from the same pinned VS Code commit/product baseline. The branch name keeps `electron-42.3.2` because that is the client build this REH accompanies.

## Workflow

The authoritative workflow is:

`.github/workflows/electron-42.3.2-linux-reh.yml`

It is available through `workflow_dispatch` and also runs on relevant pushes to `electron-42.3.2`.

The workflow has two jobs:

1. `compile`
   - checks out this branch;
   - uses GCC 10, Node.js 24.18.0 and Python 3.11;
   - fetches and verifies the pinned VS Code 1.136.0 commit;
   - runs the current-upstream `core-ci` compile path;
   - verifies the VSCodium no-extension-signature-verification policy;
   - archives the compiled VS Code tree as a one-day intermediate artifact.

2. `reh-linux-x64`
   - downloads the compiled tree from the same workflow run;
   - reuses `build/linux/package_reh.sh` with `VSCODE_ARCH=x64`;
   - builds only the native Linux Remote Extension Host, not REH-web;
   - runs the existing glibc/libstdc++ requirement checks;
   - archives the server and generates SHA-256/SHA-1 checksum files;
   - uploads the final REH artifact for 14 days.

Expected final GitHub Actions artifact:

`VSCodium-reh-linux-x64-vscode-1.136-electron-42.3.2`

Expected archive inside the artifact:

`vscodium-reh-linux-x64-<release-version>.tar.gz`

plus `.sha256` and `.sha1` files.

## Signature policy

`VSCODIUM_LATEST_UPSTREAM=yes` intentionally skips the old revision-specific VSCodium patch set. `build.sh` therefore applies `build/electron/apply-vscodium-signature-policy.sh` for every current-upstream target, not only Windows. This keeps both the Windows client and Linux REH aligned with VSCodium's policy of not performing Marketplace extension signature verification.

Do not add `@vscode/vsce-sign` merely for the remote build. If the product policy changes later, change it explicitly and test both client and REH together.

## Remote Node version

The existing VSCodium REH packager contains compatibility logic for older release lines. For this VS Code 1.136.0 build, `remote/.npmrc` already pins the current remote Node runtime, so the older `sed` rule targeting Node 22 does not rewrite it. This is intentional: the pinned upstream source remains the authority for the server runtime target.

When updating VS Code, verify `remote/.npmrc` rather than assuming the old hard-coded fallback in `build/linux/package_reh.sh` is still authoritative.

## Known pitfalls

| Symptom | Cause | Rule for this branch |
| --- | --- | --- |
| Client connects to a server built from a different VS Code revision | REH protocol/product files are revision-sensitive | Build client and REH from the same `MS_COMMIT` |
| Linux compile re-enables extension signature verification | The current-upstream path skipped VSCodium's normal signature patch | Apply and verify the dedicated signature-policy script before `core-ci` |
| REH native modules target the wrong runtime | Confusing desktop Electron ABI with remote Node ABI | Let REH packaging use the pinned VS Code remote Node configuration |
| Server does not run on older Linux | Native dependencies require a newer glibc/libstdc++ | Keep `verify-glibc-requirements.sh` enabled and fail the workflow on mismatch |
| A later REH job uses source from an older workflow run | Historical artifacts were referenced explicitly | Intermediate source artifact must come from the same workflow run via `needs: compile` |
| REH-web is built unnecessarily | Generic upstream jobs can build both server variants | Set `SHOULD_BUILD_REH=yes` and `SHOULD_BUILD_REH_WEB=no` |

## Update checklist

When moving beyond VS Code 1.136.0:

1. Update `upstream/stable.json` and verify the exact commit.
2. Update the workflow's pinned-tag/commit assertions.
3. Check the Node version required to run the build.
4. Inspect `vscode/remote/.npmrc` for the remote Node target.
5. Re-test `build/linux/package_reh.sh` against the new upstream layout.
6. Re-test the signature-policy patch before compilation.
7. Keep the glibc and libstdc++ verification step enabled.
8. Confirm the final REH archive is non-empty and internally readable with `tar -tzf`.
9. Test a Windows client from the same source commit against the newly built REH before treating the update as stable.
