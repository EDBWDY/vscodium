# Electron 42.3.2 Windows build

This branch contains a reproducible Windows x64 build path for VSCodium based on VS Code 1.136.0 with Electron 42.3.2.

## Pinned baseline

- VS Code tag: `1.136.0`
- VS Code commit: `520fb30b2d3d324b4cb2342f6e88e2cd93751de1`
- Electron: `42.3.2`
- Node.js: `24.18.0`
- GitHub runner: `windows-2022`
- Architecture: `x64`

The authoritative CI entry point is `.github/workflows/electron-42.3.2-windows.yml`. A single workflow run now performs the full source build and installer packaging; it no longer depends on a portable artifact from an older workflow run.

## Build flow

1. Fetch the pinned VS Code commit from `upstream/stable.json`.
2. Apply VSCodium branding and the small set of patches that were explicitly validated against VS Code 1.136.0.
3. Pin Electron to 42.3.2 and replace VS Code's Electron checksum manifest with `build/electron/SHASUMS256-v42.3.2.txt`.
4. Apply the Electron 42 proxy-auth compatibility patch.
5. Explicitly restore VSCodium's extension policy: Marketplace extension signature verification is disabled.
6. Install dependencies using the upstream VS Code npm configuration rather than the older VSCodium release-line npmrc.
7. Build using VS Code's current Windows pipeline: `core-ci`, built-in Copilot packaging, policy generation, then `vscode-win32-x64-min-ci`.
8. Upload the raw portable directory artifact.
9. Fetch the Explorer context-menu DLL, build the context-menu APPX, build the Inno updater, then create the portable ZIP, System installer and User installer.
10. Upload the installer package artifact.

Expected artifacts:

- `VSCodium-win32-x64-electron-42.3.2`
- `VSCodium-win32-x64-electron-42.3.2-packages`

The package artifact contains the portable ZIP, System installer EXE and User installer EXE.

## Extension signature policy

VSCodium normally disables extension signature verification. The `VSCODIUM_LATEST_UPSTREAM=yes` path intentionally skips most revision-specific VSCodium patches, which originally caused VS Code 1.136.0 to keep Microsoft's signature-verification path enabled. With Microsoft Marketplace configured at runtime this produced repeated dialogs such as:

`Signature verification was not executed.`

This is not treated as a missing `@vscode/vsce-sign` dependency in this branch. Instead, `build/electron/apply-vscodium-signature-policy.sh` applies `patches/00-extension-disable-signature-verification.patch` and verifies that `extensionManagementService.ts` contains `verifySignature = false;` and no longer references `VerifyExtensionSignatureConfigKey`.

Do not add `@vscode/vsce-sign` or `@vscodium/vsce-sign` merely to suppress the dialog unless the desired product policy changes. That would diverge from the VSCodium behaviour preserved here.

## Known pitfalls

| Symptom | Root cause | Fix retained in this branch |
| --- | --- | --- |
| Older VSCodium patches fail or corrupt the VS Code 1.136 source tree | The VSCodium patch set is revision-specific | `VSCODIUM_LATEST_UPSTREAM=yes` applies only explicitly validated patches |
| VS Code 1.136 dependency installation fails with the repository `.nvmrc` | The older VSCodium base uses an older Node version | CI pins Node.js 24.18.0 |
| Native modules resolve against the wrong Electron ABI | npm configuration loses the Electron target | Keep the upstream VS Code `.npmrc` and the Electron 42.3.2 target |
| Electron download/checksum verification fails | VS Code's checksum file belongs to a different Electron release | Copy `SHASUMS256-v42.3.2.txt` to `vscode/build/checksums/electron.txt` |
| Type errors around proxy authentication | VS Code 1.136 was authored against a later Electron 42 API revision | Apply `01-electron-42-auth-compat.patch` |
| Built-in Copilot is missing or packaging fails | The latest VS Code Windows path requires the current Copilot packaging task | Run `compile-copilot-extension-build` before `min-ci` |
| Installer jobs fail after a successful portable build | Installer packaging requires the current VS Code gulp tasks and generated policy data | Use the current upstream Windows pipeline and policy generator |
| Explorer context menu installer input is missing | The portable tree does not yet contain the fetched Explorer DLL | Run `build/win32/explorer-dll-fetcher.ts` before APPX packaging |
| `makeappx` fails or behaves inconsistently from bash | Windows SDK tooling is PowerShell-oriented and quoting differs | Run the APPX packaging step under `pwsh` |
| `makeappx` rejects `AppxManifest.xml` version | APPX requires four integer components, each in `0..65535` | Parse and rewrite all four components before packing |
| Inno setup cannot find the context-menu APPX | The APPX must be produced before setup tasks | Build `code_x64.appx` before `vscode-win32-x64-inno-updater` and setup tasks |
| Signature warning appears for Microsoft Marketplace extensions | The latest-upstream path skipped VSCodium's signature-disable patch | Apply and verify the dedicated signature-policy script before compilation |
| A later packaging run silently uses an old portable build | The old workflow hard-coded workflow run `33760861645` | Current workflow builds and packages in one run; never hard-code historical run IDs |

## Historical successful runs

These are useful as diagnostic references only; they are not dependencies of the current workflow.

- Run #15, id `33760861645`: first known-good portable Windows build after fixing built-in Copilot packaging.
- Run #21, id `33786692730`: first known-good installer packaging run, using the portable artifact from run #15.

The current workflow intentionally replaces that two-run arrangement with one self-contained build-and-package run.

## Maintenance checklist

When moving to a different VS Code or Electron release, do not simply update one version string. Check all of the following together:

1. Update `upstream/stable.json` and confirm the exact VS Code commit.
2. Update the Electron target and `cgmanifest.json` patch.
3. Regenerate or replace the Electron checksum manifest for the exact release.
4. Re-test the Electron compatibility patch against the new Electron type definitions.
5. Re-test `00-extension-disable-signature-verification.patch`; the policy should be explicit rather than assumed.
6. Compare VS Code's current Windows CI/gulp tasks with `build.sh` and the workflow.
7. Verify built-in extension packaging, especially Copilot-related tasks.
8. Verify the Explorer context-menu DLL and APPX manifest layout.
9. Verify APPX version constraints and Windows SDK path/version.
10. Require both portable and installer artifacts to be non-empty before considering the run successful.

If any revision-specific VSCodium patch is reintroduced into `VSCODIUM_LATEST_UPSTREAM=yes`, validate it individually against the pinned VS Code source. Do not re-enable the complete older patch set as a shortcut.
