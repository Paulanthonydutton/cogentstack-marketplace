---
name: cogentstack
description: Open the hosted CogentStack workspace as a signed-in browser companion beside Claude Code Desktop on Windows, claim an account-bound installation request, renew that installation securely, turn a natural-language brief into an explicitly approved project, prepare an approved deployment handoff, or execute a project deletion explicitly approved in CogentStack. Use when the user invokes CogentStack, $cogentstack, or asks to open, hide, close, connect, or use the CogentStack companion panel. This integration is for Claude Code Desktop; do not substitute a Claude Web flow.
---

# Use CogentStack with Claude Code Desktop

CogentStack's public Claude plugin reuses a normal Google Chrome or Microsoft Edge window that already contains the CogentStack workspace or home page, navigates that same tab to the hosted workspace when needed, and then arranges that browser beside the active Claude Code Desktop window. The launcher first resolves the remembered, previously verified workspace window. With no usable remembered state, Windows accessibility inventories tab titles without selecting them, accepts only the exact CogentStack workspace or home titles, activates at most one chosen candidate, and verifies that candidate's address. It never uses a generic title-contains-CogentStack match, never cycles through unrelated Claude, ChatGPT, installation, account, or legal tabs, and restores the originally selected tab if address verification fails. Reusing the normal browser profile lets an existing CogentStack website login remain visible without copying cookies or pretending that Claude inherits the browser session. Concurrent launch requests are serialized before this resolution, so a repeated invocation observes the shared workspace tab instead of racing to create another one. Only when no exact CogentStack workspace or home candidate exists may the helper open the workspace URL once as a normal tab. The bundled Windows helpers coordinate two independent application windows; they do not embed, scrape, re-parent, or automate Claude's private conversation interface. No separate CogentStack Desktop installer is required.

The companion layout hides Claude's sidebar when its accessible toggle can be identified, places Claude and the CogentStack page at equal width over a white backdrop, places a passive 12-pixel white divider with matching two-pixel neutral-grey rules at the desktop and CogentStack edges separated by eight pixels of white space in the ordinary desktop z-order only while the split geometry remains verified, and clips ordinary browser controls so the right side reads as a page-only working panel. The browser-chrome height measured before cropping remains authoritative if accessibility briefly reports the scroll region instead of the whole document, preventing the CogentStack banner from being cut off. The visible `CogentStack home` header anchor is part of layout acceptance, and Resume rebuilds a disturbed split or clipped header. The divider is anchored behind the CogentStack browser so it stays visible in the gutter when a screenshot tool has focus while other windows cover it naturally. It verifies that both panels remain above the backdrop; if the backdrop would cover either panel, it rejects the split and restores the ordinary layout. It hides immediately if either panel is maximized, moved, or otherwise leaves the verified geometry. It never uses browser F11 fullscreen. The CogentStack surface supplies the sticky header, contextual sponsored strip, visible account state, and an X control that returns the browser to the CogentStack home page in a maximized normal window. If another action navigates the reserved companion tab away from `cogentstack.app`, the exit watcher immediately removes the crop and divider and restores that page in an ordinary maximized browser window.

The plugin does not distribute contracts, task blueprints, compatibility rules, licence-validation logic, or a local project generator. CogentStack's protected server produces request-bound artifacts, and the local helper verifies and writes only an artifact the user explicitly approved. The public package does not activate protected access. The installation page must authenticate the CogentStack account and record an explicit acceptance of the current versioned Terms and EULA for that installation before it creates an opaque `cgb_...` installation request. That reference is the only permitted handoff into Claude: it is private, short-lived, single-use, and binds the website account and confirmation to the Windows installation. Never collect assent, login details, licence details, or Desktop credentials in Claude. The resulting DPAPI-protected installation credential may renew without another legal confirmation while it remains the account's one active ChatGPT or Claude Desktop installation.

Use `${CLAUDE_PLUGIN_ROOT}` for every bundled script path. Never assume the marketplace checkout or plugin cache location.

## Open, hide, or close the companion

Treat `$cogentstack`, a direct invocation of this skill, or a natural-language request to open CogentStack as the same desktop launch request.

1. Run this readiness check exactly once:

   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\skills\cogentstack\scripts\ensure-cogentstack.ps1"`

2. Parse its compact JSON. Continue only when `status` is `ready`, `surface` is `claude-desktop`, and the returned URL is exactly `https://cogentstack.app/stack?surface=claude-desktop`.
3. Run the sidebar helper exactly once:

   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\skills\cogentstack\scripts\hide-claude-sidebar.ps1"`

   Treat `hidden` and `already_hidden` as confirmation. If it reports `unavailable`, `ambiguous`, or `failed`, continue with the companion open but do not claim that the Claude sidebar was hidden.
4. Run the companion helper exactly once, passing the exact returned URL. It must serialize concurrent launches and resolve the remembered verified workspace first. If remembered state is unavailable, it must inventory exact workspace and home titles without selecting tabs, activate at most one candidate, and verify that candidate's CogentStack address. It must ignore and never select, close, or repurpose installation, account, legal, ChatGPT, Claude, and other unrelated tabs. If candidate verification fails, it must restore the original tab and open nothing else. Only when no exact workspace or home candidate exists may it open the exact workspace URL once:

   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\skills\cogentstack\scripts\open-cogentstack-panel.ps1" -Mode Open -Url "<exact returned URL>"`

5. Treat `arranged` with `layoutVerified: true` as the fully positioned result. For reuse, require `tabResolution: remembered-workspace` or `tabResolution: exact-title-inventory` and require `candidateTabsActivated` to be at most `1`. When a home-page tab was reused, also require `reusedExistingTab: true`, `reusedExistingHomeTab: true`, and `openedNewTab: false`. `opened_unarranged` means CogentStack opened but Windows could not safely identify both application windows; report that limitation and do not claim 50/50 alignment.
6. Use only the helper's `accountState` field as login evidence. `signed_in` proves that the reused browser tab visibly reports the account; `signed_out` proves a visible signed-out state; `unknown` must be reported as unverified. Never infer login from browser launch success.
7. Do not retry an accepted open, create a duplicate tab or browser app window, pass `--app` or `--new-window`, use browser F11, use computer control to move the windows, or start the separate CogentStack Desktop application.

When the user asks to hide, suspend, resume, toggle, or close the panel, run the same helper once with the corresponding `-Mode`. Hide preserves fast-resume state without maximizing; Suspend removes the crop, restores Claude, maximizes the ordinary browser, and preserves the exact local state required for `Resume`; Close performs that recovery and clears the state. The companion header presents **−**, **+**, and **X** in that order. Minus navigates to `companion=suspend` and collapses the split while keeping the watcher alive; plus navigates to `companion=resume` and the watcher directly rebuilds the verified split from the same page; X fully exits. Navigation to any non-empty address outside `cogentstack.app` also triggers Suspend automatically. A normal launch installs **CogentStack Work Mode (Claude)** in the Windows Start menu only as a fallback. Missing windows or a missing workspace tab produce `cold_start_required`; the helper never guesses, creates a replacement tab, or closes the user's browser.

When the user clicks the CogentStack header X, the watcher returns the reused tab to `https://cogentstack.app/`, clears the page-only crop, restores the ordinary browser frame, maximizes that browser window using the Windows maximize state rather than F11, restores Claude, removes the white backdrop, and deletes the saved companion state.

Workspace browsing is public. Sign-in and entitlement checks begin only when the user asks to connect Claude Desktop or chooses a protected contract action.

### Companion layout acceptance

The crop's top edge must remain at the real browser-window top while the controls stay physically above the work area. Require `browserTopCropRemoved: true`; this prevents later Chrome accessibility reflow from clipping the CogentStack banner or X control. If banner, crop, divider, or split acceptance fails, require `layout_rejected` or `resume_rejected` and confirm that the ordinary maximized browser and Claude layout were restored rather than leaving an unverified companion active.

## Claim the account-bound Claude Code Desktop installation

When the user pastes the private installation message created by `https://cogentstack.app/claude`:

1. Extract the sole `Account-bound installation request: cgb_...` value from the user's pasted installation message. Treat it as private input. Never print, quote, summarize, log, or ask the user to reveal it again.
2. Run the installed helper exactly once with `-Mode claim -InstallationRequest "<private cgb reference>"` from this skill's scripts directory. Do not run the legacy `start` or `complete` modes and do not open `/activate`.
3. Require `status: connected`, `accountBound: true`, and `installationBound: true`. If the request is expired, malformed, already used, not bound to the signed-in account's current legal confirmation, or lacks an active subscription, stop and report the narrow reason without exposing the reference.
4. The claim may explicitly replace another active ChatGPT or Claude Desktop installation for the same account. Report `replacedExistingDevice` without exposing an account identity or credential.
5. The encrypted Claude access and renewal credentials are bound to the current Windows user through DPAPI. Never read, decrypt, display, or transmit them except through the bundled helpers and CogentStack's protected API flow.

When the user explicitly asks to disconnect Claude Desktop, run `connect-cogentstack.ps1 -Mode disconnect`. It revokes the server token before deleting the Claude-specific encrypted credential.

## Create the approved project from this conversation

After the user approves the exact project setup and target in the hosted CogentStack panel and then describes what they want built in this Claude conversation:

1. Run `fulfil-project.ps1 -Mode inspect` from this skill's scripts directory.
2. If inspection returns `desktop_authorization_required`, the approved hosted request is preserved. Do not tell the user to repeat sign-in, licence activation, Project Type selection, contract setup, directory approval, Step 2, or legal acceptance. Run `connect-cogentstack.ps1 -Mode status` once. If it reports `connected`, the same installation renewed its private credential; retry inspection immediately.
3. If status remains `signed_out`, do not run the legacy `start` or `complete` modes and do not open `/activate`. Explain whether the returned reason identifies a legacy connection, a replaced or revoked installation, an inactive subscription, or updated legal documents. Direct the user to `https://cogentstack.app/claude` only in that case. That deliberately new installation path requires a fresh tick and produces a new account-bound request; the existing approved project request remains saved and must not be recreated or altered.
4. Use only the current authoritative request returned by CogentStack. If none exists, tell the user to complete and approve the project request in the panel. If more than one is ever returned, report a service-state error; never ask the user to choose among stale requests.
5. Run `fulfil-project.ps1 -Mode create -RequestId <approved UUID>` for the sole current request.
6. Keep the Desktop token, execution grant, and raw server artifact private. Never print, reproduce, cache, or infer them.
7. On success, report the exact target path, passed tests, and initial Git baseline. Continue in the same Claude session using the user's conversation text as the project brief.
8. Work only inside the created project, follow its repository instructions and acceptance checks, and do not push, deploy, or create another commit unless the user explicitly asks.

## Delete an explicitly approved project and folder

Typing the exact project name and selecting **Delete project and folder** in CogentStack is the single explicit confirmation. In companion mode, the page signals the authenticated local watcher, which normalizes Chrome or Edge address-bar text even when accessibility omits the `https://` scheme and processes the approved deletion before any layout monitoring. It runs `delete-project.ps1 -Mode delete` against the sole server-authoritative request without requiring a second Claude command. A manual deletion request is a recovery path only when that automatic handoff was unavailable.

When recovering an already approved deletion from Claude:

1. Run `delete-project.ps1 -Mode inspect`.
2. Continue only for its sole current authoritative deletion request.
3. Run `delete-project.ps1 -Mode delete -RequestId <approved UUID>`.
4. Never delete a conversationally supplied path or bypass the helper. Treat success as proven only by `status: deleted` and report the exact target and `folderRemoved` value.
5. State clearly that the folder, preview watcher, project registration, active-project selection, runtime and Git snapshots and requests, Deployment Packs, contract-compilation measurements, project-bound Contract Runtime session, and the deletion request itself are permanently removed and unrecoverable.

## Prepare an independent deployment handoff

Only after the user generates a Deployment Pack from CogentStack's Hosting view:

1. Inspect with `prepare-deployment.ps1 -Mode inspect`.
2. Prepare with `prepare-deployment.ps1 -Mode prepare -RequestId "<request-id>"`.
3. Report the exact project folder and generated `DEPLOYMENT.md` and `deployment.manifest.json` paths.
4. Do not connect, push, or deploy during preparation. A destination recorded in the manifest is not execution permission.
5. If the user later asks to deploy, present the exact repository, branch, host, port, deployment directory, health URL, and planned local actions before obtaining confirmation of those exact targets.

## Desktop-only boundary

Do not implement, imply, or silently fall back to a Claude Web connector. Do not iframe Claude, re-parent the Claude application window, scrape its conversation, copy browser cookies, or use computer control merely to create the companion layout. Reusing and arranging a normal Chrome or Edge window through the bundled Windows helper is the supported boundary. Claude Web support is a separate future release.
