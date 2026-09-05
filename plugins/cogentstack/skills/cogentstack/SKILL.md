---
name: cogentstack
description: Open the hosted CogentStack workspace as a signed-in Edge companion beside ChatGPT or Codex on Windows, optionally keep it inside Codex with separate Desktop authorization, turn a natural-language project brief into an explicitly approved project, prepare an explicitly approved independent deployment handoff, and execute a project deletion explicitly approved in the hosted workspace. Use when the user invokes CogentStack, $cogentstack, or @cogentstack, asks to open the CogentStack workspace, asks to sign in to CogentStack from Desktop, describes a project they want CogentStack to create after approving its setup, asks to prepare an approved Deployment Pack, or asks to delete the currently requested CogentStack project and its folder.
---

# Use CogentStack

CogentStack's public plugin opens the hosted workspace in a Microsoft Edge app window arranged beside ChatGPT or Codex on Windows, and fulfils approved project requests from natural-language briefs users write in the adjacent composer. Because the companion uses the user's normal Edge profile, an existing CogentStack login in that Edge profile appears immediately. It does not distribute contracts, task blueprints, compatibility rules, licence validation logic, or a local project generator. The protected server produces a request-bound project artifact; Desktop verifies and writes only that artifact.

1. Installation and workspace browsing are public. Do not request a CogentStack account, licence key, activation code, or Desktop credential during installation or launch.
2. Treat `$cogentstack`, `@cogentstack`, a CogentStack plugin mention, or a natural-language request to open CogentStack as the same launch request. Every invocation must run this complete sequence; do not stop after checking backend readiness.
3. Run `scripts/ensure-cogentstack.ps1 -Mode Companion` exactly once. Read its compact JSON and require `status: ready`, `mode: companion`, and the official `https://cogentstack.app/stack?surface=chatgpt` URL. Never remove the surface marker or fall back to `/app`, localhost, a bundled web server, or a manually created browser tab.
4. On Windows, run `scripts/hide-codex-sidebar.ps1` exactly once before arranging the windows. Treat `hidden` or `already_hidden` as success. If the helper reports that the ChatGPT/Codex window is unavailable or ambiguous, state that the sidebar could not be hidden automatically, then continue the companion launch without claiming a complete visual match.
5. Immediately run `scripts/open-cogentstack-companion.ps1 -Mode Open -Url <exact returned URL>` exactly once. This opens CogentStack with Edge's `--app` window and uses visible-frame measurements to arrange an exact 50/50 split: ChatGPT or Codex on the left, CogentStack on the right, no gutter, joined inner edges, and a DPI-scaled top offset that aligns the bottom of the two title bars. Treat `arranged` as fully positioned and `opened_unarranged` as opened but not safely positionable. If it returns `browser_unavailable`, explain that Microsoft Edge must be installed for the companion flow. Do not silently fall back to an embedded Codex panel.
6. The default companion uses the normal Edge profile. If that Edge profile is already signed into CogentStack, the workspace must show that logged-in state immediately. It cannot inherit a login held only by Chrome or another browser profile; in that case the user signs in normally in the Edge companion once.
7. Do not call `codex_app__open_in_codex` and do not create or retry browser tabs during the default companion launch. This keeps queued panel mounts and duplicate tabs out of the normal flow.
8. Treat the hosted workspace as authoritative. Do not infer, recreate, cache, or disclose proprietary contract content, project-generation rules, subscriber credentials, or protected service responses.
9. Contract activation, validation, project-artifact generation, and next-action decisions are executed by CogentStack's protected server-side Contract Runtime. Never request or download a complete contract, task blueprint, or Contract Pack. Consume only the narrow result presented by the hosted workspace or the request-bound generated files returned to the fulfilment helper.
10. A hosted selection alone does not authorize local changes. Local project creation is allowed only after the user approves the exact target directory and submits a project request in the hosted workspace, then describes what they want built in the adjacent composer. That brief is the explicit fulfilment instruction. Do not require a new task or a fixed command.

When the user asks to hide or close the companion, run `scripts/open-cogentstack-companion.ps1 -Mode Hide` or `-Mode Close`. Closing restores the remembered ChatGPT or Codex window position and removes only the companion layout record.

## Keep the workspace inside Codex

Use the embedded mode only when the user explicitly asks to keep CogentStack inside Codex or requests the native right panel. Explain first that this panel has an isolated browser session: it does not inherit the user's Edge, Chrome, or system-browser CogentStack login and therefore needs a separate one-time Desktop authorization.

1. Run `scripts/ensure-cogentstack.ps1 -Mode Embedded` exactly once and read its compact JSON.
2. When it returns `status: ready`, call `codex_app__open_in_codex` exactly once with its exact returned URL as `target.url`, `target.type` set to `browser`, and `placement` set to `right`. The URL may contain a short-lived `#desktop=` fragment when a prior Desktop authorization was refreshed; never print, copy, log, alter, or remove that fragment.
3. Treat either `opened` or `queued` as an accepted host mount request. Do not create browser tabs, pass `tabId`, open a blank tab, or retry the panel call.
4. Run `scripts/hide-codex-sidebar.ps1` only after the host accepts the embedded open request.
5. If `authenticated` is false, state that the panel is public/signed out until the one-time Desktop authorization below is completed. Never describe it as inheriting the normal browser login.

## Authorize the isolated in-Codex panel

When the user explicitly asks to authorize or sign in to the embedded Codex panel:

1. Run `scripts/connect-cogentstack.ps1` with its default `start` mode. It opens the official CogentStack website in the system default browser. It does not send a licence key or copy a browser cookie.
2. Do not show, describe, or ask the user to enter an authorization code. If the browser is already signed in, ask the user only to select **Continue to ChatGPT Desktop**. Otherwise, ask them to sign in normally and then select that button.
3. Run `scripts/connect-cogentstack.ps1 -Mode complete` after the returned polling interval. While it returns `approval_pending`, wait for the polling interval and try again. Keep the user updated at least once per minute and stop when the request expires.
4. When it returns `authorized`, call `codex_app__open_in_codex` exactly once with its exact `workspaceUrl` as `target.url`, `target.type` set to `browser`, and `placement` set to `right`. Never expose the short-lived fragment.
5. Treat either `opened` or `queued` as accepted, do not create or retry browser tabs, and then run `scripts/hide-codex-sidebar.ps1`.
6. The encrypted Desktop credential remains bound to the current Windows user through DPAPI. Never read, decrypt, display, or transmit it except through this script and CogentStack's protected API flow.

When the user explicitly asks to sign out or disconnect the embedded Codex panel, run `scripts/connect-cogentstack.ps1 -Mode disconnect`. This revokes the server token before removing the encrypted local credential. The Edge companion's normal website session remains separately controllable from the CogentStack account page.

## Create from the adjacent composer brief

When the user describes the project they want after recording an approved creation request in the hosted workspace:

1. Run `scripts/fulfil-project.ps1 -Mode inspect`. It uses the current user's DPAPI-protected Desktop credential internally and returns only narrow project-request summaries.
2. The hosted workspace returns only its current authoritative request. If exactly one request is available, use it for the adjacent composer brief without asking the user to identify or repeat the project name. If no request is available, explain that the user must finish and approve Step 2 in the hosted workspace. If more than one request is ever returned, report a CogentStack service-state error; never ask the user to choose among stale requests.
3. Run `scripts/fulfil-project.ps1 -Mode create -RequestId <approved UUID>` for the one selected request. When there is exactly one request, `-RequestId` may be omitted.
4. The helper must keep the Desktop token, execution grant, and raw server artifact private. Never print, summarize, cache, or reproduce them. Do not substitute local templates, infer missing contract content, or bypass artifact checks.
5. The helper writes only beneath the server-returned target path, verifies every file and the whole artifact, installs dependencies, runs the generated acceptance tests, creates the initial Git baseline, and reports completion to the server. If it fails, do not delete the partial target; report its path and the failure clearly.
6. On success, report the exact target path, passed tests, and baseline commit. Then continue in the same task by treating the user's composer text as the project brief. Work only inside the created target, follow its generated repository instructions and acceptance checks, and verify the requested work. Do not push, deploy, commit beyond the generated baseline, or change any other repository unless the user explicitly asks.

After opening the workspace, display a brief welcome explaining that the Edge companion uses the normal Edge account session, Project Types can be browsed freely, sign-in or a licence is requested only when a contract is used, and the user can stay in the same task and write their project brief in the adjacent composer after approving Step 2.

## Delete an approved project and folder

When the user explicitly asks to delete a project after typing its exact name and approving deletion in the hosted **Open project** page:

1. Run `scripts/delete-project.ps1 -Mode inspect`. It returns only the current authoritative deletion request.
2. If no request is available, explain that the user must approve deletion on the **Open project** page first. If more than one request is ever returned, report a CogentStack service-state error; never choose among deletion requests.
3. Run `scripts/delete-project.ps1 -Mode delete -RequestId <approved UUID>` for the sole request. When exactly one request exists, `-RequestId` may be omitted.
4. Never delete the path manually or substitute a path from conversation context. The helper accepts only matching server-returned deletion and project IDs, the exact registered child path, approved parent directory, project slug, and short-lived execution grant. It refuses drive roots, temporary validation paths, files, reparse points at the parent, target, or nested levels, and mismatched parents or folder names.
5. Treat success as proven only when the helper returns `status:deleted`. On failure, report the requested target, `folderRemoved`, `registrationFinalized`, and whether a partial folder remains. If the folder was removed before server acknowledgement failed, say that the filesystem deletion is already permanent even though registration was not finalized. Do not retry without a fresh hosted approval.
6. On success, report the exact deleted target and `folderRemoved`. If it is false, say that the folder was already absent; never claim it was removed. State that the registration deletion is permanent and unrecoverable.

## Prepare an independent deployment handoff

Use this flow only after the user selects a completed project in the hosted **Hosting** tab and presses **Generate Deployment Pack**.

1. Inspect the approved request with `scripts/prepare-deployment.ps1 -Mode inspect`.
2. Prepare the fixed handoff files with `scripts/prepare-deployment.ps1 -Mode prepare -RequestId "<request-id>"`.
3. Report the exact project folder, the generated `DEPLOYMENT.md` and `deployment.manifest.json` files, and the approved non-secret repository/host target recorded in them.
4. Do not push or connect during pack preparation. A destination recorded in the manifest is not permission to use it.
5. If the user subsequently and explicitly asks to deploy to that target, read the local manifest, show the exact repository, branch, host, port, deployment directory, health URL and planned local actions, then obtain confirmation that those exact targets are approved.
6. Use only the local machine's existing Git credential helper, SSH configuration and SSH agent. Never request, print, store, copy into the manifest, or transmit passwords, access tokens, private keys or agent material.
7. Before the first SSH connection, compare the live host key with the approved fingerprint. Stop on a missing or mismatched fingerprint unless the user independently verifies and explicitly approves the new key.
8. Keep execution bounded by the manifest: push only the approved branch and repository; connect only to the approved host and port; write only beneath the approved deployment directory; run the documented build, health and release checks; produce rollback instructions and record the deployed source revision.
9. Direct the user to the hosted **Changes** tab for ordinary source-history actions that are not part of the explicitly approved deployment.
