# Contributing a Community Guardrail Pack

CogentStack accepts declarative guardrail packs through reviewed Git pull requests.

## Submission process

1. Create a public Git repository for the pack or add a pack beneath `contracts/community/` during early protocol development.
2. Copy `contracts/examples/accessible-interface/guardrail-pack.json` as a starting point.
3. Use a globally unique pack ID, semantic version, recognised SPDX licence, and explicit publisher identity.
4. Define concrete requirements, controls, guidance, and acceptance evidence without including secrets or protected third-party material.
5. Keep `execution.mode` set to `declarative` and `execution.allowScripts` set to `false`.
6. Run `node scripts/validate-contract-marketplace.mjs`.
7. Submit the pack and a registry entry by pull request.

## Trust levels

- `community`: structurally valid and published by its named contributor.
- `verified`: independently reviewed against CogentStack engineering and safety criteria.
- `official`: authored and maintained by CogentStack.
- `example`: sanitised protocol demonstration only.

Trust level is assigned by the marketplace registry. A pack cannot award itself `verified` or `official` status.

## Prohibited content

Community packs must not contain executable scripts, binaries, credentials, private keys, malicious instructions, copied proprietary packs, hidden downloads, or claims that bypass normal testing and human approval.

