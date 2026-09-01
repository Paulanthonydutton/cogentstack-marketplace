---
name: cogentstack
description: Open CogentStack beside Claude Code Desktop, securely authorize this desktop, turn a natural-language brief into an explicitly approved project, prepare an approved deployment handoff, or execute a project deletion explicitly approved in CogentStack. Use when the user invokes CogentStack, $cogentstack, or asks to open, hide, close, connect, or use the CogentStack companion panel. This integration is for Claude Code Desktop; do not substitute a Claude Web flow.
---

# Use CogentStack with Claude Code Desktop

CogentStack's public Claude plugin opens the protected hosted workspace in an Edge app window beside the active Claude Code Desktop window. The bundled Windows helper coordinates two independent application windows; it does not embed, scrape, re-parent, or automate Claude's private interface. No separate CogentStack Desktop installer is required for this companion layout.

The plugin does not distribute contracts, task blueprints, compatibility rules, licence-validation logic, or a local project generator. CogentStack's protected server produces request-bound artifacts, and the local helper verifies and writes only an artifact the user explicitly approved.

Use `${CLAUDE_PLUGIN_ROOT}` for every bundled script path. Never assume the marketplace checkout or plugin cache location.

## Open, hide, or close the companion

Treat `$cogentstack`, a direct invocation of this skill, or a natural-language request to open CogentStack as the same desktop launch request.

1. Run this readiness check exactly once:

   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\skills\cogentstack\scripts\ensure-cogentstack.ps1"`

2. Parse its compact JSON. Continue only when `status` is `ready`, `surface` is `claude-desktop`, and the returned URL is an HTTPS `/stack` URL on `cogentstack.app`.
3. Run the companion helper exactly once, passing the exact returned URL:

   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\skills\cogentstack\scripts\open-cogentstack-panel.ps1" -Mode Open -Url "<exact returned URL>"`

4. Treat `arranged` and `opened_unarranged` as successful opens. If the helper reports `opened_unarranged`, explain that CogentStack opened but Windows could not safely identify both windows; the user can place it beside Claude manually.
5. Do not retry an accepted open, open another browser window, use computer control to move the windows, or start the separate CogentStack Desktop application.

When the user asks to hide the panel, run the same helper with `-Mode Hide`. When the user asks to close the panel, run it with `-Mode Close`. Both restore Claude to its recorded pre-companion bounds when that window is still available.

Workspace browsing is public. Sign-in and entitlement checks begin only when the user asks to connect Claude Desktop or chooses a protected contract action.

## Connect Claude Code Desktop

When the user explicitly asks to sign in, connect, or authorize Claude Desktop:

1. Run `connect-cogentstack.ps1` with its default `start` mode from this skill's scripts directory.
2. Tell the user to sign in and approve the displayed **Claude Code Desktop on Windows** request in the browser. Show the returned user code so they can compare it with the browser.
3. Run the helper with `-Mode complete` after the returned polling interval. While it reports `approval_pending`, wait for that interval and try again. Stop when it expires.
4. When it returns `authorized`, keep its one-use workspace fragment private and pass the complete `workspaceUrl` directly to `open-cogentstack-panel.ps1 -Mode Open -Url "<workspaceUrl>"`.
5. Never print, copy, log, summarize, or persist the one-use fragment outside the helper invocation.
6. The encrypted Claude credential is bound to the current Windows user through DPAPI. Never read, decrypt, display, or transmit it except through the bundled helpers and CogentStack's protected API flow.

When the user explicitly asks to disconnect Claude Desktop, run `connect-cogentstack.ps1 -Mode disconnect`. It revokes the server token before deleting the Claude-specific encrypted credential.

## Create the approved project from this conversation

After the user approves the exact project setup and target in the hosted CogentStack panel and then describes what they want built in this Claude conversation:

1. Run `fulfil-project.ps1 -Mode inspect` from this skill's scripts directory.
2. Use only the current authoritative request returned by CogentStack. If none exists, tell the user to complete and approve the project request in the panel. If more than one is ever returned, report a service-state error; never ask the user to choose among stale requests.
3. Run `fulfil-project.ps1 -Mode create -RequestId <approved UUID>` for the sole current request.
4. Keep the Desktop token, execution grant, and raw server artifact private. Never print, reproduce, cache, or infer them.
5. On success, report the exact target path, passed tests, and initial Git baseline. Continue in the same Claude session using the user's conversation text as the project brief.
6. Work only inside the created project, follow its repository instructions and acceptance checks, and do not push, deploy, or create another commit unless the user explicitly asks.

## Delete an explicitly approved project and folder

Only after the user types the exact project name and approves deletion in CogentStack:

1. Run `delete-project.ps1 -Mode inspect`.
2. Continue only for its sole current authoritative deletion request.
3. Run `delete-project.ps1 -Mode delete -RequestId <approved UUID>`.
4. Never delete a conversationally supplied path or bypass the helper. Treat success as proven only by `status: deleted` and report the exact target and `folderRemoved` value.
5. State clearly that an acknowledged registration deletion is permanent and unrecoverable.

## Prepare an independent deployment handoff

Only after the user generates a Deployment Pack from CogentStack's Hosting view:

1. Inspect with `prepare-deployment.ps1 -Mode inspect`.
2. Prepare with `prepare-deployment.ps1 -Mode prepare -RequestId "<request-id>"`.
3. Report the exact project folder and generated `DEPLOYMENT.md` and `deployment.manifest.json` paths.
4. Do not connect, push, or deploy during preparation. A destination recorded in the manifest is not execution permission.
5. If the user later asks to deploy, present the exact repository, branch, host, port, deployment directory, health URL, and planned local actions before obtaining confirmation of those exact targets.

## Desktop-only boundary

Do not implement, imply, or silently fall back to a Claude Web connector. Do not iframe Claude, re-parent the Claude application window, scrape its conversation, copy browser cookies, or use computer control merely to create the companion layout. Claude Web support is a separate future release.
