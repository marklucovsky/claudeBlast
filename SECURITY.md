# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Blaster, please report it privately rather than opening a public GitHub issue.

**Contact:** Open a [GitHub Security Advisory](https://github.com/marklucovsky/claudeBlast/security/advisories/new) or email the maintainer directly (see profile).

Please include a description of the issue, steps to reproduce, and any potential impact. We will respond within 72 hours and coordinate a fix before public disclosure.

## Scope

Blaster is designed with privacy as a core constraint:

- **No backend.** All user data stays on device. AI calls (OpenAI) are stateless — no conversation history or identifying information is transmitted.
- **No accounts.** No user accounts, no cloud sync beyond iCloud (planned).
- **API key storage.** Currently stored in `UserDefaults` (acceptable for alpha). Keychain migration is planned before App Store release.
- **Admin panel.** The admin/settings panel is not gated behind Face ID in this alpha build. This is a known gap and is planned for pre-release.

## Child Data

This app is intended for use by non-verbal children. We take that responsibility seriously. If you identify any issue that could expose, transmit, or misuse child data, please report it immediately via the private channel above.
