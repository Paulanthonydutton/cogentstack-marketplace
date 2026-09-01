# Contract Marketplace Security

Report marketplace security concerns privately to `accounts@cogentstack.app`. Do not include live credentials or sensitive customer data in a public issue.

Community Guardrail Packs are treated as untrusted input. Their files are declarative, their revisions are pinned before publication, and their marketplace trust level is assigned independently of the pack manifest.

The public protocol does not expose CogentStack's protected contracts, compatibility rules, compiler, executable Contract Packs, entitlement controls, or release engine.

The Claude Code Desktop plugin includes local PowerShell helpers and must therefore be treated as executable software. Its companion helper may open only the HTTPS `/stack` route on `cogentstack.app`, records only window handles and the previous Claude window bounds, and coordinates independent top-level windows without embedding or scraping Claude. Claude-specific device credentials are encrypted for the current Windows user with DPAPI and remain separate from ChatGPT Desktop credentials.
