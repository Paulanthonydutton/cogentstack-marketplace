# CogentStack Marketplace

This repository contains two separate Git marketplaces:

- `.agents/plugins/` and `plugins/cogentstack/` distribute the thin CogentStack Codex plugin.
- `contracts/` publishes the open Community Guardrail Pack protocol and its Git-reviewed registry.

Community Guardrail Packs are declarative. They can define requirements, controls, guidance, and acceptance evidence, but they cannot execute scripts or contain CogentStack's protected runtime rules. CogentStack's proprietary engine remains responsible for compatibility review, binding, execution, entitlement, and release decisions.

## Validate the contract marketplace

```bash
node scripts/validate-contract-marketplace.mjs
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the submission process and `contracts/protocol/v0.1/` for the protocol schema.

