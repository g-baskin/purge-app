# PRD-003: Local Development Signing and Helper Trust *(Retroactive)*

> **Status:** Shipped
> **Priority:** - *(retroactive - work is done)*
> **Effort:** M (3-8h) *(estimated after the fact)*
> **Schema changes:** None (one optional Info.plist key, local builds only)
> **Written:** October 2026
> **Retroactive:** Yes - this PRD was written after implementation.
> **Shipped in:** commits `456296e` (signing scripts + README) and `d9a5e7e` (helper trust + test-host change), both 2026-10-02. Fork-only.

---

## What was built

macOS ties Full Disk Access and background-item approval to an app's code signature. Without an Apple developer certificate every local build gets a fresh ad-hoc signature, so macOS treats each build as a new app and asks for permissions again. Separately, the privileged helper and the app only trusted the original developer's team (`BX83ZBV95B`), so a locally signed build could never remove admin-owned apps: the helper refused every request.

This feature gives a contributor's own Mac a private self-signed code-signing certificate, signs local builds with it so permissions persist, and lets the helper and app trust exactly that one certificate in local builds while release builds keep the team-only rule.

### Part A - Signing scripts (`456296e`)

- **`scripts/dev-signing-setup.sh`** (one-time, re-runnable; `--remove` undoes it). Creates `~/Library/Keychains/purge-dev-signing.keychain-db` holding a certificate "Purge Local Development" (LibreSSL `openssl req -x509 -newkey rsa:3072 -sha256 -days 3650`, line 151), stores the keychain's unlock password in the login keychain (service `io.getpurge.dev-signing`), and adds a per-user trust setting for code signing only (`security add-trusted-cert -r trustRoot -p codeSign`, line 51; macOS asks for the user's password).
- **`scripts/dev-sign.sh <Purge.app>`** (`--check` only verifies readiness). Sets `CFBundleVersion` to `99999` so the built-in updater never swaps the build for an official release (line 58); writes the certificate's SHA-1 into `PurgeLocalSigningCertificateSHA1` in `Contents/Info.plist` (line 60); temporarily adds the keychain to the search list and restores the list afterwards; signs inside-out, including the extra executables in `Contents/MacOS` (PurgeWatch, PurgeHelper) and anything in Frameworks/PlugIns, preserving identifier and entitlements with the hardened runtime **off** (lines 94-121); verifies with `codesign --verify --deep --strict` and fails if the designated requirement names a `cdhash` instead of the certificate (lines 126-134).
- **`scripts/dev-run.sh`** builds Debug into `build/dev` with an ad-hoc signature, signs with `dev-sign.sh`, refuses to proceed if another copy of Purge is running from elsewhere, and reopens the new build (`--no-open` builds only).
- **`scripts/dev-test.sh`** runs `build-for-testing`, signs the app, then `test-without-building`, forwarding extra arguments (e.g. `-only-testing:PurgeTests/RestoreServiceTests`) to `xcodebuild`.
- **README** section "Keep permissions between builds" (`README.md`, around line 283) documents the workflow and its risks.

### Part B - Helper trust (`d9a5e7e`)

- `PurgeHelperConstants.requirement(identifier:localCertificateSHA1:)` (`purge/PrivilegedHelper/PurgeHelperProtocol.swift:56-64`) returns the official requirement (`identifier ... and anchor apple generic and certificate leaf[subject.OU] = "BX83ZBV95B"`) and, only when a valid fingerprint is present, ORs in `identifier "<id>" and certificate leaf = H"<sha1>"`.
- `validatedFingerprint` (lines 68-74) accepts exactly 40 hex digits (lowercased); anything else is ignored so it can never widen the requirement or break its syntax.
- `bundledLocalCertificateSHA1()` (lines 78-87) reads the key from the Purge.app `Info.plist` two levels above the running executable (app and helper both live in `Purge.app/Contents/MacOS`); `localCertificateSHA1(infoPlist:)` (lines 90-98) also requires `CFBundleIdentifier == io.getpurge.app`. The plist is sealed by the signature, so editing it breaks the signature.
- Both ends use it: the helper on incoming connections (`PurgeHelper/HelperListenerDelegate.swift:18`, `clientRequirement`) and the app when dialling the helper (`purge/PrivilegedHelper/PrivilegedHelperManager.swift:87`, `helperRequirement`).
- **Release builds never carry the key** and keep the team-only requirement with no "or" clause.
- `purge/Services/AppBootstrapper.swift` now returns early under `TestHost.isActive()` before reconciling the helper, because the test host is a second copy of Purge.app and re-registering from it could move the approved root helper over to the test copy.

## Goals (met)

- Local builds keep macOS permissions across rebuilds.
- A locally signed build can use the privileged helper.
- Release trust is unchanged.

## Non-Goals

- Notarized or distributable local builds.
- Hardened runtime for self-signed builds.

---

## Acceptance criteria (verified by tests)

Tests: `PurgeTests/PrivilegedHelperRequirementTests.swift`. The scripts have no automated tests.

| ID | Criterion | Test |
|---|---|---|
| AC-1 | A release-shaped Info.plist yields the official requirements with no "or" clause and no certificate hash, and they compile. | `releaseBuildKeepsTheOfficialRequirement` |
| AC-2 | A local build's plist adds exactly its certificate, and the requirement compiles. | `localBuildAddsItsCertificate` |
| AC-3 | Another app's plist, a missing plist, or a garbage plist is ignored. | `otherAppsPlistIsIgnored`, `missingPlistIsIgnored` |
| AC-4 | Malformed fingerprints (wrong length, quote/injection attempts) are ignored. | `malformedFingerprintIsIgnored` (parameterised) |

---

## Known limits and risks

- The certificate's keychain is unlocked by builds without prompting, so any program running as the user could use it to sign code that claims Purge's permissions. The scripts and README say to set this up only on your own Mac.
- Local builds run without the hardened runtime (a self-signed certificate has no team ID, so library validation would stop the app loading its own libraries).
- macOS keeps permissions for one copy of an app at a time; only the `build/dev` copy should be used.
- A local build trusts any helper/app signed with that same certificate and the right identifier.
- Script behaviour was read, not executed, for this PRD.

---

## Related

- `README.md` - "Keep permissions between builds"
- `SECURITY.md`
- [IRD-002: Helper moves cannot be put back](../../../issues/backlog/ird-002-helper-moves-cannot-be-put-back/ird-002-helper-moves-cannot-be-put-back-index.md) - same helper, different gap.
