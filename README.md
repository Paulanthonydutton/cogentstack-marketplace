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

The Codex plugin is installed from the Git-backed `.agents/plugins/` marketplace and retains `$cogentstack` as the common invocation. On Windows its default helper selects the exact existing `surface=chatgpt` tab in Chrome or Edge through Windows accessibility, reuses that signed-in page's owning normal browser session, hides the ChatGPT/Codex sidebar, and puts a white backdrop at the bottom of the Windows work area. It temporarily removes the reused browser frame and positions its controls outside the work area so the CogentStack web document itself fills the complete right panel, then verifies an equal-width 50/50 workspace around a 24-pixel reserved divider that leaves visible white space after both window shadows. The panels retain full work-area height and aligned top edges. This reversible page-only layout does not use monitor-wide F11; Hide or Close restores the browser's original style and position. Only when no matching tab exists does it open the exact hosted URL once as a normal tab in the registered browser. It never launches a separate app-mode window, guesses a browser profile, reads or copies cookies, queues a native panel mount, or creates a duplicate after finding the existing tab.

The native in-Codex panel remains available only when the user explicitly asks to keep CogentStack inside Codex. That panel has an isolated browser session, cannot inherit Edge or Chrome login cookies, and uses the separate one-time Desktop authorization flow.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the submission process and `contracts/protocol/v0.1/` for the protocol schema.
