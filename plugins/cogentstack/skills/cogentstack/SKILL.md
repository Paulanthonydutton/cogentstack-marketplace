---
name: cogentstack
description: Open the hosted CogentStack workspace, securely authorize ChatGPT Desktop, and turn a natural-language project brief into an explicitly approved project. Use when the user invokes CogentStack, $cogentstack, or @cogentstack, asks to open the CogentStack workspace, asks to sign in to CogentStack from Desktop, or describes a project they want CogentStack to create after approving its setup in the hosted workspace.
---

# Use CogentStack

CogentStack's public plugin launches the hosted workspace, runs the small Desktop device-authorization client, and fulfils approved project requests from natural-language briefs users write in the adjacent Codex composer. It does not distribute contracts, task blueprints, compatibility rules, licence validation logic, or a local project generator. The protected server produces a request-bound project artifact; Desktop verifies and writes only that artifact.

1. Installation and workspace browsing are public. Do not request a CogentStack account, licence key, activation code, or Desktop credential during installation or launch.
2. When the user invokes CogentStack or asks to open it, run `scripts/ensure-cogentstack.ps1`.
3. Read the script's compact JSON and open only the exact returned `https://cogentstack.app/stack` URL in the Codex app, placed on the right. Never fall back to `/app`, localhost, or a bundled web server.
4. On Windows, run `scripts/hide-codex-sidebar.ps1` after opening so the hosted workspace has room beside the conversation.
5. Authentication and licence validation begin only when the user chooses **Use [project type] contract** in the hosted workspace.
6. Treat the hosted workspace as authoritative. Do not infer, recreate, cache, or disclose proprietary contract content, project-generation rules, subscriber credentials, or protected service responses.
7. Contract activation, validation, project-artifact generation, and next-action decisions are executed by CogentStack's protected server-side Contract Runtime. Never request or download a complete contract, task blueprint, or Contract Pack. Consume only the narrow result presented by the hosted workspace or the request-bound generated files returned to the fulfilment helper.
8. A hosted selection alone does not authorize local changes. Local project creation is allowed only after the user approves the exact target directory and submits a project request in the hosted workspace, then describes what they want built in the adjacent Codex composer. That brief is the explicit fulfilment instruction. Do not require a new task or a fixed command.

## Sign in from ChatGPT Desktop

When the user explicitly asks to sign in, log in, connect their CogentStack account, or authorize Desktop:

1. Run `scripts/connect-cogentstack.ps1` with its default `start` mode. It requests a short-lived device authorization and opens the system default browser. It does not send a licence key or copy a browser cookie.
2. Tell the user to sign in and approve the displayed ChatGPT Desktop request in that browser. Show the returned user code so they can verify the browser is approving the same request.
3. Run `scripts/connect-cogentstack.ps1 -Mode complete` after the returned polling interval. While it returns `approval_pending`, wait for the polling interval and try again. Keep the user updated at least once per minute and stop when the request expires.
4. When it returns `authorized`, open only its exact `workspaceUrl` in the Codex app, placed on the right. The fragment contains a short-lived, one-use browser grant; never print it, copy it, log it, or place it in commentary.
5. Run `scripts/hide-codex-sidebar.ps1` after opening. The workspace consumes the one-use grant, removes the fragment, and refreshes the account and licence status.
6. The encrypted Desktop credential remains bound to the current Windows user through DPAPI. Never read, decrypt, display, or transmit it except through this script and CogentStack's protected API flow.

When the user explicitly asks to sign out or disconnect ChatGPT Desktop, run `scripts/connect-cogentstack.ps1 -Mode disconnect`. This revokes the server token before removing the encrypted local credential. Browser sessions remain separately controllable from the CogentStack account page.

## Create from the adjacent composer brief

When the user describes the project they want after recording an approved creation request in the hosted workspace:

1. Run `scripts/fulfil-project.ps1 -Mode inspect`. It uses the current user's DPAPI-protected Desktop credential internally and returns only narrow project-request summaries.
2. Match an available request by an exact project name stated in the brief. If exactly one request is available, use it. If no request is available, explain that the user must finish and approve Step 2 in the hosted workspace. If more than one request is available and the brief does not identify one, show the project names and exact target paths and ask which request the brief belongs to.
3. Run `scripts/fulfil-project.ps1 -Mode create -RequestId <approved UUID>` for the one selected request. When there is exactly one request, `-RequestId` may be omitted.
4. The helper must keep the Desktop token, execution grant, and raw server artifact private. Never print, summarize, cache, or reproduce them. Do not substitute local templates, infer missing contract content, or bypass artifact checks.
5. The helper writes only beneath the server-returned target path, verifies every file and the whole artifact, installs dependencies, runs the generated acceptance tests, creates the initial Git baseline, and reports completion to the server. If it fails, do not delete the partial target; report its path and the failure clearly.
6. On success, report the exact target path, passed tests, and baseline commit. Then continue in the same task by treating the user's composer text as the project brief. Work only inside the created target, follow its generated repository instructions and acceptance checks, and verify the requested work. Do not push, deploy, commit beyond the generated baseline, or change any other repository unless the user explicitly asks.

After opening the workspace, display a brief welcome explaining that Project Types can be browsed freely, sign-in or a licence is requested only when a contract is used, and the user can stay in the same task and write their project brief in the adjacent composer after approving Step 2.
