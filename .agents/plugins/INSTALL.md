# Install CogentStack for ChatGPT Desktop

Carry out the installation for the user as one bounded operation. It must finish with either verified success or one precise failure within **30 seconds**. Do not perform broad filesystem searches, scan Codex sessions or memories, launch CogentStack, open browser tabs, or repeat successful checks.

The pasted request must include one opaque `Account-bound installation request: cgb_...` reference created by the signed-in CogentStack website after the user explicitly confirms the current Terms and EULA for this installation. Treat that reference as a private, short-lived, single-use handoff. Never print it, repeat it, log it, place it in a displayed command, or ask the user to reveal it again. Never collect legal acceptance, a login, licence key, activation code, or Desktop credential in ChatGPT or Codex; the website is the only acceptance and authorization surface.

1. Start a 30-second deadline before downloading or running anything.
2. Download the official bounded installer from `https://raw.githubusercontent.com/Paulanthonydutton/cogentstack-marketplace/main/.agents/plugins/install-cogentstack.ps1` to a uniquely named temporary file. Limit this download to five seconds. Do not display the temporary file contents or the command containing the private installation reference.
3. Run that file exactly once with `-InstallationRequest <the exact private cgb_ reference>` and the seconds remaining before the original deadline. Always remove the temporary file and clear the in-memory reference afterward.
4. Read its single compact JSON result. Success requires `status: installed`, `connected: true`, `accountBound: true`, and `installationBound: true`. The installer performs the HTTP marker check; exact Git source and sparse-path reconciliation; marketplace refresh; plugin installation; installed/enabled/version verification; exact public-file allowlist and source-hash verification; launcher and optional-panel contract checks; and the one permitted account-bound claim.
5. If the result is `failed`, report only its precise `reason`. If the request was not consumed, the result says so. Never substitute an older route, `/activate`, localhost, an embedded-panel login, or another installation attempt.

The bounded installer may add or repair only the marketplace registration named `cogentstack`. It must use `https://github.com/Paulanthonydutton/cogentstack-marketplace.git` with sparse paths `.agents/plugins` and `plugins/cogentstack`, and install only `cogentstack@cogentstack`. The installed package allowlist is the manifest, two brand assets, launcher skill, presentation metadata, `ensure-cogentstack.ps1`, `open-cogentstack-companion.ps1`, `connect-cogentstack.ps1`, `fulfil-project.ps1`, `generate-project-preview.ps1`, `delete-project.ps1`, `prepare-deployment.ps1`, `native-command.ps1`, and `hide-codex-sidebar.ps1`. No contracts, task blueprints, licence-validation rules, compatibility rules, or local project-generation logic may be distributed.

If the raw installer cannot be downloaded, the deadline expires, or any verification fails, stop immediately and explain the returned failure. Do not consume the account request after the deadline and do not report a successful installation.

When every check passes, display exactly:

**CogentStack is installed. Click New Chat in ChatGPT Desktop, then enter $cogentstack.**
