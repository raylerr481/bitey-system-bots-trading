# Code versioning policy — Bitey SBT

Effective workflow for code created or modified in this repository:

1. Save every material code version to GitHub with a clear versioned filename or a dedicated branch/commit.
2. Preserve prior versions as immutable snapshots under `versions/<project>/` when a newer version replaces them.
3. For sensitive or trading-related changes, update a separate backup copy where appropriate.
4. Record the commit SHA and direct GitHub links in the response.
5. Never overwrite the original EA or merge to `main` without explicit authorization.
6. Do not claim compilation, backtests, or runtime validation unless actually performed.
7. Preserve risk guards; do not remove limits or force minimum lots to make a strategy trade.

## Infinity Impulse snapshots

- `versions/infinity-impulse/Infinity_Impulse_MultiAsset_Adaptive_v1_10.mq4`: source snapshot supplied by the user (v1.10).
- `Infinity_Impulse_MultiAsset_Adaptive_v1.mq4`: active development candidate (v1.11 on the development branch).
- `backups/infinity-impulse/Infinity_Impulse_MultiAsset_Adaptive_v1_backup.mq4`: synchronized backup candidate.
