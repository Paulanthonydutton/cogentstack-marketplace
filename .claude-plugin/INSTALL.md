# Install CogentStack for Claude Code Desktop

CogentStack for Claude is currently a **desktop-only** integration. Claude Web will be delivered separately.

## Install from Claude Code Desktop

1. Update Claude Desktop to a version that includes the Code tab and plugin manager.
2. Open the **Code** tab.
3. Open **Plugins**, add this marketplace using:

   `Paulanthonydutton/cogentstack-marketplace`

4. Install `cogentstack@cogentstack` at user scope.
5. Reload plugins when Claude asks, or run `/reload-plugins`.
6. Enter `$cogentstack` in a Claude Code session.

Claude's native discoverable command is `/cogentstack:cogentstack`; `$cogentstack` is retained as CogentStack's common invocation across supported AI desktops.

The plugin downloads its versioned instructions and Windows companion-layout helper through Claude's marketplace. It does not require the separate CogentStack Desktop installer. On first use, Windows may ask for permission to let the local helper start an Edge app window and arrange it beside Claude.

## Trust boundary

The public plugin contains no Contract Packs, protected contracts, task blueprints, compatibility rules, licence-validation rules, subscriber credentials, or local project-generation logic. Those remain on CogentStack's protected service. Local project creation occurs only after the user approves the exact request and target in the hosted workspace.
