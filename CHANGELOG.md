# Changelog

## v2.2.0

### Added
- `clientspider` command wrapping the ZAP 2.16 browser-based crawler, plus `stop clientspider`, integrated into the existing scan / percentage-wait / stop pipeline (#50).
- `import` command with `--format openapi|soap|graphql|postman` to seed ZAP from API definitions given as files or URL lists, reusing passive-settle, report generation and `--fail-on` (#50).
- `policies` command to discover active-scan policy names per host, which makes `ascan --policy` usable without guessing (#50).
- `sitestree export|prune` command built on the ZAP 2.16 Sites Tree, for differential and incremental CI scans (#50).
- `--format` and `--target-url` flags, wired through the CLI, TOML config and the `MZAP_FORMAT` / `MZAP_TARGET_URL` environment variables (#50).
- Crystal 1.20 and 1.21.0 in the supported and tested versions.
- Homebrew tap distribution: releases now ship a prebuilt-binary formula (#49).

### Changed
- Requires zap.cr 0.2.0 for the ClientSpider and Postman import parameters (#50).
- Decomposed the client module and tidied option handling; environment-option application is centralized behind small helpers.
- Linux arm64 release binaries are built on a native ARM runner instead of under emulation.
- Container builds use the official `crystallang/crystal` image.

### Fixed
- Fibers no longer deadlock under concurrent scans.
- `--urls -` is accepted again for reading targets from stdin.
- SARIF `pluginId` is emitted robustly when ZAP omits or varies the plugin identifier.
- macOS release binaries are now shipped as portable `.tar.gz` archives with bundled OpenSSL libraries, instead of a bare executable linked against Homebrew `openssl@1.1` that failed to launch on clean machines (`dyld: libssl.1.1.dylib not found`).
- macOS release tarballs are re-signed ad hoc after `install_name_tool` rewrites their dylib load paths. The bundled OpenSSL dylibs were left with a stale signature, and Apple Silicon SIGKILLs any process that maps one, so the tarball died at launch with a bare `killed` and no diagnostic. Packaging now verifies every signature and runs the extracted tarball before publishing it. Nothing broken was ever published: the last release predates the tarball packaging (#54).

### Security
- The Snapcraft workflow can be dispatched manually so the snap can be rebuilt against Ubuntu security updates without cutting a new release (#53).

## v2.1.1

### Fixed
- Sync version across shard.yml, version.cr, and snapcraft.yaml

## v2.1.0

### Added
- Passive scan support with `mzap pscan` command
- JSON, Markdown, and SARIF report formats
- Concurrent scan execution with `--concurrency` flag
- Scan policy support for active scan
- ZAP context import support
- `--fail-on` flag for CI/CD quality gate
- Scan result summary output
- Environment variable support for configuration
- Support reading URLs from stdin
- Retry mechanism for scan and poll failures
- Snapcraft package and publish workflow

### Changed
- Improve Options struct and enforce named arguments across public API
- Refactor client: extract `with_zap_clients`, simplify string ops, narrow rescue types
- Refactor CLI and polling logic to reduce complexity
- Optimize target file deduplication during parsing
- Cache HTTP headers to prevent per-request allocations

### Fixed
- Fix stdin scope and `--fail-on` error handling
- Fix snapcraft summary exceeding 78-char limit
- Path traversal vulnerability in report generation

## v2.0.0

- Rewrite in Crystal

## v1.3.1

### Fixed
- Bug fixes and code improvements

## v1.3.0

### Added
- GitHub Actions support

## v1.2.0

### Added
- Support M1 and Windows ARM

## v1.1.4

### Added
- Support ARM(6/7/64) in Linux and BSD

## v1.1.3

### Added
- Banner

## v1.1.2

### Changed
- Multi-stage Docker build for image optimization
- Add network plugs for Snapcraft

## v1.1.1

### Fixed
- Snapcraft permission issue

## v1.1.0

### Added
- API key support

## v1.0.0

- Initial release
