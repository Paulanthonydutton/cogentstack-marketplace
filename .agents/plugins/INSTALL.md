# Install CogentStack for ChatGPT Desktop

Carry out these steps for the user. Do not ask the user to run technical checks or provide a CogentStack login, licence key, activation code, or Desktop credential during installation.

1. Verify that `https://cogentstack.app/stack` returns HTTP 200 and renders **What are you building?**. If it is unavailable, redirects, or returns an error, stop and explain that the CogentStack release is not ready. Do not fall back to `/app` or a localhost URL.
2. Add the Git-backed marketplace at `https://github.com/Paulanthonydutton/cogentstack-marketplace.git` using sparse paths `.agents/plugins` and `plugins/cogentstack`.
3. If the `cogentstack` marketplace is already registered, confirm its Git source and both sparse paths match this document. Refresh it before installation. If its registration differs, remove only that marketplace registration and add it again with the correct source and sparse paths.
4. Install `cogentstack@cogentstack`.
5. Verify that the plugin is installed and enabled, and that its installed version matches the version declared by the refreshed marketplace package.
6. Verify that the installed package contains only its manifest, brand assets, launcher skill, presentation metadata, `ensure-cogentstack.ps1`, `connect-cogentstack.ps1`, `fulfil-project.ps1`, and `hide-codex-sidebar.ps1`. The helpers may use Windows DPAPI for the current user's Desktop credential and may write a request-bound server-generated artifact to its explicitly approved target, verify it, test it, and create its initial Git baseline. They must not contain licence-validation rules, contracts, task blueprints, compatibility rules, or local project-generation logic.
7. Verify that the installed CogentStack launcher opens exactly `https://cogentstack.app/stack` and does not require first-install activation. Do not launch CogentStack as part of installation.

If any verification fails, stop and clearly explain the problem. Do not report a successful installation or substitute an older route or package.

When every check passes, display exactly:

**CogentStack is installed. Click New Chat in ChatGPT Desktop, then enter $cogentstack.**
