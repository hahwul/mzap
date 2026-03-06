# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.0.x   | :white_check_mark: |
| < 2.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in mzap, please report it responsibly.

1. **Do not** open a public GitHub issue for security vulnerabilities.
2. Email the maintainer at **hahwul@gmail.com** with:
   - A description of the vulnerability
   - Steps to reproduce the issue
   - Potential impact
3. You can expect an initial response within **72 hours**.
4. A fix will be prioritized and released as a patch version once confirmed.

## Scope

mzap is a CLI tool that communicates with OWASP ZAP API instances. Security concerns include:

- Command injection via crafted target URLs or configuration files
- Path traversal in report output paths
- Sensitive data exposure (API keys in logs or process arguments)

## Acknowledgments

We appreciate responsible disclosure and will credit reporters in release notes (unless anonymity is requested).
