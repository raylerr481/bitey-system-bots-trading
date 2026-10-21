# Initial source and dependency audit

**Audit status:** initial repository metadata and entry-point inspection only. Not a full source/security audit.

## Upstream inspected

- Repository: https://github.com/EA31337/EA31337-Libre
- MT4 entry point: `src/EA31337-Libre.mq4`
- MT4 entry point blob SHA observed: `b9197986f7ce6d83e3abf0e9de8095067bcfffca`
- Shared source: `src/EA31337-Libre.mq5`
- Shared source blob SHA observed: `99abdeadf351682d24ec787f4d70e4b11092cbcb`
- `.gitmodules` blob SHA observed: `dee9382486fdd4800b513ae79ee12e9487c6dc01`

## Findings

1. The `.mq4` entry point includes `EA31337-Libre.mq5`; this is a shared MQL4/MQL5 source architecture, not a self-contained single-file EA.
2. The upstream declares two git submodules:
   - `src/include/classes` → https://github.com/EA31337/EA31337-classes
   - `src/include/strategies` → https://github.com/EA31337/EA31337-strategies
3. The shared entry point includes `include/ea.h`; the full include tree and both submodules must be present at compatible revisions to build.
4. The shared entry point creates `EALibre`, sets the `EA_Risk_MarginMax` parameter, and forwards ticks to the EA. This initial inspection does not establish that all strategy code, order handling, or symbol-specific risk calculations are correct.
5. Upstream source contains GPL licensing language. Preserve copyright and license notices, document modifications, and comply with GPL-3.0 distribution requirements.

## Not verified

- Full dependency tree and compatible pinned revisions.
- Compilation in MetaEditor or any MQL4 compiler.
- Runtime behavior on the user's broker.
- EURUSD or XAUUSD profitability.
- Real-account or independently audited performance.
- Correct risk sizing for broker-specific contract sizes, tick values, account currency, minimum lots, stop levels, and execution slippage.

## References

- https://github.com/EA31337/EA31337-Libre
- https://github.com/EA31337/EA31337-Libre/blob/master/src/EA31337-Libre.mq4
- https://github.com/EA31337/EA31337-Libre/blob/master/src/EA31337-Libre.mq5
- https://github.com/EA31337/EA31337-Libre/blob/master/.gitmodules
- https://github.com/EA31337/EA31337-Libre/blob/master/LICENSE
