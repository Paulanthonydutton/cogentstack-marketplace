# CogentStack Marketplace

This repository contains three separate Git marketplaces and release records:

- `.agents/plugins/` and `plugins/cogentstack/` distribute the thin CogentStack Codex plugin.
- `.claude-plugin/` and `claude-plugins/cogentstack/` distribute the desktop-only CogentStack plugin for Claude Code.
- `contracts/` publishes the open Community Guardrail Pack protocol and its Git-reviewed registry.

It also publishes the authoritative `desktop/marketplace.json` release record for CogentStack Desktop. Windows installers are attached to versioned GitHub Releases rather than committed to Git history. The web installer reads this record, verifies the published SHA-256, and keeps Launch visibly disabled until the installed local runtime is detected. Windows always retains the user's approval before executing a first-time installer.

Community Guardrail Packs are declarative. They can define requirements, controls, guidance, and acceptance evidence, but they cannot execute scripts or contain CogentStack's protected runtime rules. CogentStack's proprietary engine remains responsible for compatibility review, binding, execution, entitlement, and release decisions.

## Validate the contract marketplace

```bash
node scripts/validate-contract-marketplace.mjs
node scripts/validate-desktop-marketplace.mjs
node scripts/validate-claude-marketplace.mjs
```

## Claude Code Desktop

The Claude plugin is installed from this Git marketplace and retains `$cogentstack` as the common CogentStack invocation. Its bundled Windows helper opens the protected `surface=claude-desktop` workspace in an Edge app window and arranges that independent window beside Claude Code Desktop. It does not embed, scrape, re-parent, or automate Claude's private interface, and it does not require the separate CogentStack Desktop installer.

Claude Web is intentionally outside this package. It will use a separate remote-connector flow later.

## ChatGPT and Codex Desktop

The Codex plugin is installed from the Git-backed `.agents/plugins/` marketplace and retains `$cogentstack` as the common invocation. On Windows its default helper opens the protected `surface=chatgpt` workspace with the registered HTTPS browser—Chrome or Edge—and that browser's last-used normal profile, hides the ChatGPT/Codex sidebar, and uses visible-frame measurements to arrange a joined 50/50 workspace with no gutter and aligned top bars. This preserves the website login already held by that browser profile without copying cookies or credentials, and avoids queued native panel mounts and duplicate tabs.

The native in-Codex panel remains available only when the user explicitly asks to keep CogentStack inside Codex. That panel has an isolated browser session, cannot inherit Edge or Chrome login cookies, and uses the separate one-time Desktop authorization flow.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the submission process and `contracts/protocol/v0.1/` for the protocol schema.
