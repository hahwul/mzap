# Spec Naming Conventions

Use the pattern `mzap_<component>_<area>_spec.cr` for test files.

## Current structure

- `mzap_banner_spec.cr`
- `mzap_options_spec.cr`
- `mzap_reporter_spec.cr`
- `mzap_client_scan_spec.cr`
- `mzap_client_wait_spec.cr`
- `mzap_client_report_spec.cr`
- `mzap_client_stop_spec.cr`
- `mzap_config_discovery_spec.cr`
- `mzap_config_parsing_spec.cr`
- `mzap_cli_help_spec.cr`
- `mzap_cli_commands_spec.cr`
- `mzap_cli_options_spec.cr`

## Rules

- Keep one dominant concern per file.
- Keep file names all lowercase with underscores.
- Keep files alphabetically ordered by name in directory listings.
- Put shared helpers only in `spec/support/` and load via `spec/spec_helper.cr`.
