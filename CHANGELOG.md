# Changelog

All notable changes to this fork will be documented in this file. Releases of the
original project are listed on [jithin-sabu/purge-app's releases page](https://github.com/jithin-sabu/purge-app/releases);
this fork tracks it on the `upstream-main` branch.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Based on the original project's 1.7.0 (released 2026-10-01).

### Added

- Put Back: restore items Purge moved to the Trash, from Cleanup History. See PRD-001 in `library/requirements/completed/`.
- Saved folder sizes: sizes are remembered between launches and only folders that changed are measured again. See PRD-002.
- Scripts that sign local builds with a private certificate so macOS keeps Purge's permissions between builds (`scripts/dev-*.sh`). See PRD-003.
- The uninstall helper trusts a local build's own signing certificate, so local builds can remove admin-installed apps. Releases keep the original team-only check.
- Project documentation under `library/`: requirements, issue records, and design decisions.

### Fixed

- Folder sizing no longer hangs forever when many measurements run at once.
- Put Back text now uses the design system's font and colour tokens.

[Unreleased]: https://github.com/g-baskin/purge-app/compare/upstream-main...main
