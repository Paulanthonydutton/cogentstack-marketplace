# Install CogentStack for ChatGPT Desktop

Carry out the installation for the user as one bounded operation. It must finish with either verified success or one precise failure within **30 seconds**. Do not perform broad filesystem searches, scan Codex sessions or memories, launch CogentStack, open browser tabs, download executable code with a shell HTTP command, or repeat successful checks.

The pasted request must include one opaque `Account-bound installation request: cgb_...` reference created by the signed-in CogentStack website after the user explicitly confirms the current Terms and EULA for this installation. Treat that reference as a private, short-lived, single-use handoff. Never print it, repeat it, log it, place it in a displayed command, or ask the user to reveal it again. Never collect legal acceptance, a login, licence key, activation code, or Desktop credential in ChatGPT or Codex; the website is the only acceptance and authorization surface.

1. Start a 30-second deadline before running any installation command.
2. Use only Codex's trusted plugin manager to prepare the official Git-backed marketplace. Inspect the `cogentstack` registration with `codex plugin marketplace list --json`. It must use `https://github.com/Paulanthonydutton/cogentstack-marketplace.git` with exactly the sparse paths `.agents/plugins` and `plugins/cogentstack`.
   - If it is absent, add it with `codex plugin marketplace add` and those two sparse paths.
   - If it already has that exact Git source and both sparse paths, upgrade it once with `codex plugin marketplace upgrade cogentstack`.
   - If the registration differs, remove only the marketplace registration named `cogentstack`, then add the exact source and sparse paths once.
   Do not use `Invoke-WebRequest`, `curl`, BITS, a raw GitHub download, a temporary downloaded script, or any other shell-level downloader.
3. Read the marketplace list once more, resolve the reported `cogentstack` root, and require the exact file `.agents/plugins/install-cogentstack.ps1` beneath that root. Do not search elsewhere or copy the installer to a temporary file.
4. Run that verified file exactly once with `-MarketplacePrepared`, `-InstallationRequest <the exact private cgb_ reference>`, and the seconds remaining before the original deadline. Do not display the command or its private argument. Clear the in-memory reference immediately afterward.
5. Read its single compact JSON result. Success requires `status: installed`, `connected: true`, `accountBound: true`, and `installationBound: true`. The installer verifies the prepared marketplace identity and sparse paths; verifies that `https://cogentstack.app/stack?surface=chatgpt` returns HTTP 200 with the required workspace markers; installs the plugin; verifies installed/enabled/version state; verifies the exact public-file allowlist and source hashes; checks the launcher and optional-panel contract; and performs the one permitted account-bound claim.
6. If marketplace preparation is blocked, the deadline expires, the installer is outside the prepared marketplace, or any verification fails, stop immediately and report one precise reason. If the request was not consumed, say so. Never substitute an older package, `/activate`, localhost, an embedded-panel login, or another installation attempt.

The installed package allowlist is the manifest, two brand assets, launcher skill, presentation metadata, `ensure-cogentstack.ps1`, `open-cogentstack-companion.ps1`, `connect-cogentstack.ps1`, `fulfil-project.ps1`, `generate-project-preview.ps1`, `delete-project.ps1`, `prepare-deployment.ps1`, `project-context.ps1`, `project-knowledge.ps1`, `native-command.ps1`, and `hide-codex-sidebar.ps1`. No contracts, task blueprints, licence-validation rules, compatibility rules, or local project-generation logic may be distributed.

When every check passes, display exactly:

**CogentStack is installed. Click New Chat in ChatGPT Desktop, then enter $cogentstack.**
