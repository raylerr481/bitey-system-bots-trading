# Infinity Impulse — Code Backup

Backup snapshot created 2026-10-21.

- `Infinity_Impulse_XAUUSD_original_backup.mq4`: copy of the original single-symbol source from `main`. The original file on `main` is not modified.
- `Infinity_Impulse_MultiAsset_Adaptive_v1_backup.mq4`: copy of the adaptive multi-asset candidate from `feature/infinity-impulse-multiasset-v1`.

Important: the adaptive candidate has not been compiled in MetaEditor or backtested here. Review and test in Strategy Tester/demo before any live use. High spreads are not hard-rejected by a fixed spread ceiling, but widened SL/TP and risk-based lot sizing do not guarantee profitable execution or acceptance by the broker.
