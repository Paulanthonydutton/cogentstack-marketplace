---
name: cogentstack
description: Open the hosted CogentStack workspace. Use when the user invokes CogentStack, $cogentstack, or @cogentstack, or asks to open the CogentStack workspace.
---

# Use CogentStack

CogentStack's public plugin is deliberately limited to launching the hosted workspace. It does not distribute contracts, task blueprints, compatibility rules, project generators, subscriber authentication logic, or Git orchestration.

1. Installation and workspace browsing are public. Do not request a CogentStack account, licence key, activation code, or Desktop credential during installation or launch.
2. When the user invokes CogentStack or asks to open it, run `scripts/ensure-cogentstack.ps1`.
3. Read the script's compact JSON and open only the exact returned `https://cogentstack.app/stack` URL in the Codex app, placed on the right. Never fall back to `/app`, localhost, or a bundled web server.
4. On Windows, run `scripts/hide-codex-sidebar.ps1` after opening so the hosted workspace has room beside the conversation.
5. Authentication and licence validation begin only when the user chooses **Use [project type] contract** in the hosted workspace.
6. Treat the hosted workspace as authoritative. Do not infer, recreate, cache, or disclose proprietary contract content, project-generation rules, subscriber credentials, or protected service responses.
7. For filesystem, terminal, or Git work, use Codex's normal built-in capabilities only when the user explicitly requests that work. This launcher does not grant extra authority and must not imply that a hosted selection alone authorizes local changes.

After opening the workspace, display a brief welcome explaining that Project Types can be browsed freely and that sign-in or a licence is requested only when a contract is used.
