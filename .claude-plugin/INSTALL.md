# Install CogentSpec for Claude Code Desktop

CogentSpec for Claude is currently a **desktop-only** integration. Claude Web will be delivered separately.

## Install from Claude Code Desktop

1. Update Claude Desktop to a version that includes the Code tab and plugin manager.
2. Open the **Code** tab.
3. Open **Plugins**, add this marketplace using:

   `cogentspec/cogentspec-marketplace`

4. Install `cogentstack@cogentstack` at user scope.
5. Reload plugins when Claude asks, or run `/reload-plugins`.
6. Return to `https://cogentspec.com/claude`, copy the private account-bound connection request created after the fresh Terms and EULA confirmation, and paste it into the Claude Code session. Claude passes its opaque `cgb_...` value directly to the installed connection helper exactly once.
7. Enter `$cogentstack` in a Claude Code session.

Claude's native discoverable command is `/cogentstack:cogentstack`; `$cogentstack` is retained as CogentSpec's common invocation across supported AI desktops.

The plugin downloads its versioned instructions and Windows companion-layout helpers through Claude's marketplace. It does not require the separate CogentSpec Desktop installer. On first use, Windows may ask for permission to let the helpers arrange Claude beside an existing normal Chrome or Edge CogentSpec tab. The browser's own profile supplies the visible website login state; the plugin does not copy cookies or collect a CogentSpec login or licence during installation. Installing the public package does not activate protected actions: the private, short-lived and single-use installation request binds the signed-in website account's exact legal confirmation to this Windows installation. Its credentials are encrypted for the current Windows user and renew only while this remains the account's active Desktop installation.

## Trust boundary

The public plugin contains no Contract Packs, protected contracts, task blueprints, compatibility rules, licence-validation rules, subscriber credentials, or local project-generation logic. Those remain on CogentSpec's protected service. Local project creation occurs only after the user approves the exact request and target in the hosted workspace.
