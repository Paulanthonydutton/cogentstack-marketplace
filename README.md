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

The Claude plugin is installed from this Git marketplace and retains `$cogentstack` as the common CogentStack invocation. On Windows its default helpers hide the Claude sidebar when the accessible toggle is available, select an existing `surface=claude-desktop` CogentStack tab in normal Chrome or Edge, preserve that browser profile's visible login state, and arrange Claude and the page-only CogentStack panel at equal width over a white backdrop with a 12-pixel divider. It does not use browser F11, copy cookies, launch an app-mode browser window, embed, scrape, re-parent, or automate Claude's private interface. The CogentStack header X restores and maximizes the normal browser on the CogentStack home page. No separate CogentStack Desktop installer is required.

Claude Web is intentionally outside this package. It will use a separate remote-connector flow later.

## ChatGPT and Codex Desktop

The Codex plugin is installed from the Git-backed `.agents/plugins/` marketplace and retains `$cogentstack` as the common invocation. It resolves the current AI Project's isolated logical CogentStack context, starts or reuses one background Desktop Bridge for that context, and returns the matching CogentStack Web URL. It does not open or select browser tabs, inspect browser profiles, hide sidebars, resize windows, or embed CogentStack into every AI Project.

Desktop Bridge performs only explicitly approved local actions queued by CogentStack Web: project creation, deletion, preview generation, and repository operations. Qwen Desktop is an optional separate application and reuses the same Bridge; it does not install a second copy. ChatGPT and Claude remain their official independent desktop applications.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the submission process and `contracts/protocol/v0.1/` for the protocol schema.
