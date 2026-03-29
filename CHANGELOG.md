# Changelog

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
