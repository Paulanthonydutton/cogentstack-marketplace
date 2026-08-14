---
name: cogentstack
description: Open the hosted CogentStack workspace and securely authorize ChatGPT Desktop when requested. Use when the user invokes CogentStack, $cogentstack, or @cogentstack, asks to open the CogentStack workspace, or asks to sign in to CogentStack from Desktop.
---

# Use CogentStack

CogentStack's public plugin is deliberately limited to launching the hosted workspace and running the small Desktop device-authorization client. It does not distribute contracts, task blueprints, compatibility rules, project generators, licence validation logic, or Git orchestration.

1. Installation and workspace browsing are public. Do not request a CogentStack account, licence key, activation code, or Desktop credential during installation or launch.
2. When the user invokes CogentStack or asks to open it, run `scripts/ensure-cogentstack.ps1`.
3. Read the script's compact JSON and open only the exact returned `https://cogentstack.app/stack` URL in the Codex app, placed on the right. Never fall back to `/app`, localhost, or a bundled web server.
4. On Windows, run `scripts/hide-codex-sidebar.ps1` after opening so the hosted workspace has room beside the conversation.
5. Authentication and licence validation begin only when the user chooses **Use [project type] contract** in the hosted workspace.
6. Treat the hosted workspace as authoritative. Do not infer, recreate, cache, or disclose proprietary contract content, project-generation rules, subscriber credentials, or protected service responses.
7. Contract activation, validation, and next-action decisions are executed by CogentStack's protected server-side Contract Runtime. Never request or download a complete contract, task blueprint, acceptance map, or Contract Pack. Consume only the narrow result presented by the hosted workspace.
8. For filesystem, terminal, or Git work, use Codex's normal built-in capabilities only when the user explicitly requests that work. This launcher does not grant extra authority and must not imply that a hosted selection alone authorizes local changes.

## Sign in from ChatGPT Desktop

When the user explicitly asks to sign in, log in, connect their CogentStack account, or authorize Desktop:

1. Run `scripts/connect-cogentstack.ps1` with its default `start` mode. It requests a short-lived device authorization and opens the system default browser. It does not send a licence key or copy a browser cookie.
2. Tell the user to sign in and approve the displayed ChatGPT Desktop request in that browser. Show the returned user code so they can verify the browser is approving the same request.
3. Run `scripts/connect-cogentstack.ps1 -Mode complete` after the returned polling interval. While it returns `approval_pending`, wait for the polling interval and try again. Keep the user updated at least once per minute and stop when the request expires.
4. When it returns `authorized`, open only its exact `workspaceUrl` in the Codex app, placed on the right. The fragment contains a short-lived, one-use browser grant; never print it, copy it, log it, or place it in commentary.
5. Run `scripts/hide-codex-sidebar.ps1` after opening. The workspace consumes the one-use grant, removes the fragment, and refreshes the account and licence status.
6. The encrypted Desktop credential remains bound to the current Windows user through DPAPI. Never read, decrypt, display, or transmit it except through this script and CogentStack's protected API flow.

When the user explicitly asks to sign out or disconnect ChatGPT Desktop, run `scripts/connect-cogentstack.ps1 -Mode disconnect`. This revokes the server token before removing the encrypted local credential. Browser sessions remain separately controllable from the CogentStack account page.

After opening the workspace, display a brief welcome explaining that Project Types can be browsed freely and that sign-in or a licence is requested only when a contract is used.
