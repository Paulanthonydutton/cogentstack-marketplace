---
name: cogentstack
description: Open the hosted CogentStack workspace as a signed-in browser companion beside Claude Code Desktop on Windows, securely authorize this desktop when explicitly requested, turn a natural-language brief into an explicitly approved project, prepare an approved deployment handoff, or execute a project deletion explicitly approved in CogentStack. Use when the user invokes CogentStack, $cogentstack, or asks to open, hide, close, connect, or use the CogentStack companion panel. This integration is for Claude Code Desktop; do not substitute a Claude Web flow.
---

# Use CogentStack with Claude Code Desktop

CogentStack's public Claude plugin reuses the normal Google Chrome or Microsoft Edge window that already contains the hosted CogentStack workspace, then arranges that browser beside the active Claude Code Desktop window. Reusing the normal browser profile lets an existing CogentStack website login remain visible without copying cookies or pretending that Claude inherits the browser session. The bundled Windows helpers coordinate two independent application windows; they do not embed, scrape, re-parent, or automate Claude's private conversation interface. No separate CogentStack Desktop installer is required.

The companion layout hides Claude's sidebar when its accessible toggle can be identified, places Claude and the CogentStack page at equal width over a white backdrop, leaves a 12-pixel vertical divider, and clips ordinary browser controls so the right side reads as a page-only working panel. It never uses browser F11 fullscreen. The CogentStack surface supplies the sticky header, contextual sponsored strip, visible account state, and an X control that returns the browser to the CogentStack home page in a maximized normal window.

The plugin does not distribute contracts, task blueprints, compatibility rules, licence-validation logic, or a local project generator. CogentStack's protected server produces request-bound artifacts, and the local helper verifies and writes only an artifact the user explicitly approved. The public package does not activate protected access: CogentStack's website must authenticate the account and record that account's acceptance of the current versioned Terms and EULA before the service may issue a Desktop credential. Never collect assent, credentials, or licence details in Claude.

Use `${CLAUDE_PLUGIN_ROOT}` for every bundled script path. Never assume the marketplace checkout or plugin cache location.

## Open, hide, or close the companion

Treat `$cogentstack`, a direct invocation of this skill, or a natural-language request to open CogentStack as the same desktop launch request.

1. Run this readiness check exactly once:

   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\skills\cogentstack\scripts\ensure-cogentstack.ps1"`

2. Parse its compact JSON. Continue only when `status` is `ready`, `surface` is `claude-desktop`, and the returned URL is exactly `https://cogentstack.app/stack?surface=claude-desktop`.
3. Run the sidebar helper exactly once:

   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\skills\cogentstack\scripts\hide-claude-sidebar.ps1"`

   Treat `hidden` and `already_hidden` as confirmation. If it reports `unavailable`, `ambiguous`, or `failed`, continue with the companion open but do not claim that the Claude sidebar was hidden.
4. Run the companion helper exactly once, passing the exact returned URL:

   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\skills\cogentstack\scripts\open-cogentstack-panel.ps1" -Mode Open -Url "<exact returned URL>"`

5. Treat `arranged` with `layoutVerified: true` as the fully positioned result. `opened_unarranged` means CogentStack opened but Windows could not safely identify both application windows; report that limitation and do not claim 50/50 alignment.
6. Use only the helper's `accountState` field as login evidence. `signed_in` proves that the reused browser tab visibly reports the account; `signed_out` proves a visible signed-out state; `unknown` must be reported as unverified. Never infer login from browser launch success.
7. Do not retry an accepted open, create a duplicate tab or browser app window, pass `--app` or `--new-window`, use browser F11, use computer control to move the windows, or start the separate CogentStack Desktop application.

When the user asks to hide the panel, run the same helper with `-Mode Hide`. When the user asks to close the panel, run it with `-Mode Close`. Both restore Claude and the reused normal browser window to their recorded pre-companion state when those windows are still available; neither closes the user's browser.

When the user clicks the CogentStack header X, the watcher returns the reused tab to `https://cogentstack.app/`, clears the page-only crop, restores the ordinary browser frame, maximizes that browser window using the Windows maximize state rather than F11, restores Claude, removes the white backdrop, and deletes the saved companion state.

Workspace browsing is public. Sign-in and entitlement checks begin only when the user asks to connect Claude Desktop or chooses a protected contract action.

## Connect Claude Code Desktop

When the user explicitly asks to sign in, connect, or authorize Claude Desktop:

1. Run `connect-cogentstack.ps1` with its default `start` mode from this skill's scripts directory. It opens the official CogentStack website in the system default browser.
2. Do not show, describe, or ask the user to enter an authorization code. If the browser is already signed in, ask the user to review and accept the current Terms and EULA if the website requires it, then select **Continue to Claude Desktop**. Otherwise, ask them to sign in normally, complete that website acceptance, and then select that button. Never record assent on the user's behalf. This familiar browser confirmation prevents another local application or a deceptive link from silently authorizing itself.
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

Do not implement, imply, or silently fall back to a Claude Web connector. Do not iframe Claude, re-parent the Claude application window, scrape its conversation, copy browser cookies, or use computer control merely to create the companion layout. Reusing and arranging a normal Chrome or Edge window through the bundled Windows helper is the supported boundary. Claude Web support is a separate future release.
