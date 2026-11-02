# Bitey Scalper MultiAsset v1.4.5.13 — Persistent Re-entry Protection

## Status

Experimental research branch. Based on v1.4.5.12. This version is **not approved for live deployment** until it compiles in MetaEditor and passes MT4 Strategy Tester plus demo forward checks.

- Branch: `research/v1-4-5-13-persistent-reentry-protection`
- EA: `Bitey_Scalper_MultiAsset_v1_4_5_13_PersistentReentryProtection.mq4`
- Parent branch: `research/v1-4-5-12-dynamic-net-progressive-exit`
- Parent EA: `Bitey_Scalper_MultiAsset_v1_4_5_12_DynamicNetProgressiveExit.mq4`

## New behavior

The EA checks re-entry only after a fresh candidate has passed `Analyze()` on closed bars. The protection is scoped by account, magic number, normalized asset key, and direction. It does not impose a global portfolio cooldown.

### Defaults

| Input | Default | Meaning |
|---|---:|---|
| `InpEnableReentryProtection` | `true` | Enable persistent protection |
| `InpReentryCooldownBars` | `6` | Block same asset and same direction for six fully completed signal bars after a qualifying loss |
| `InpFlipProtectionWindowBars` | `6` | Detect protected losing closes in both directions within six completed bars |
| `InpFlipLockoutBars` | `6` | If both directions were stopped/protectively closed within the window, block both sides for six fully completed bars after the latest close |

The existing `InpCooldownBars` remains a legacy diagnostic input and is no longer the entry-blocking control.

### What qualifies as a protected loss

A closed market order for this EA's magic number and exact broker symbol qualifies only when its realized net is negative (profit + commission + swap), and one of these is true:

1. Its historical close price is within a tolerance of the final recorded stop-loss price. This is classified from MT4 history by price matching and is probable rather than a broker-provided close-reason code.
2. The EA successfully closed it using `PROGRESSIVE_NET_LOSS_EXIT` or `NET_LOSS_MINUS_0_10`. A ticket-specific MT4 terminal Global Variable marks this EA-originated protective loss until the history record is indexed.

A profitable close does **not** activate a cooldown, including a profitable trailing-stop close. Normal TP, small-profit, daily recovery profit, time exits, manual closes not matching the SL, and other unclassified exits do not automatically trigger the protection.

## Entry decisions

1. **Same-side re-entry:** after a qualifying losing BUY, another BUY in the same asset is blocked for six fully completed signal bars. The same applies to SELL.
2. **Opposite-side signal:** the opposite direction is not automatically blocked after one protected loss. It is considered only after `Analyze()` has independently confirmed a valid closed-bar signal; it then continues through all existing spread, permission, portfolio, and risk checks.
3. **Weak or unconfirmed opposite signal:** it never becomes a candidate because `Analyze()` rejects it. The EA does not reverse solely because the previous position closed.
4. **Anti-flip protection:** if both BUY and SELL have qualifying losing protective closes within the configured flip window, both directions are blocked for the flip lockout period. This is intended to prevent repeated BUY → stop → SELL → stop → BUY oscillation.
5. **Asset isolation:** a protected loss on CADJPY does not block EURUSD, ZECUSDT, or another asset.

### Bar counting

Cooldown counts completed bars after the bar in which the protected close occurred. The current, still-forming bar is not counted. If the required bar index cannot be resolved from broker history, the entry gate fails closed for that asset until the bar data is available.

## Persistence

The latest qualifying close timestamp is stored in MT4 terminal Global Variables, with keys scoped by account, magic number, asset key, and side. EA-originated protective-close markers are ticket-specific. This allows the state to survive EA removal/re-attachment and terminal restart.

MT4 terminal Global Variables are local to that terminal installation. For reconstruction after terminal data loss, the account's MT4 Account History must include the relevant closed orders (preferably **All History**). The EA only sees history MT4 has loaded.

## Diagnostics

Experts log events:
- `REENTRY_BLOCKED`
- `OPPOSITE_SIGNAL_CHECK`
- `REENTRY_ALLOWED`
- `REENTRY_PROTECTION_CONFIG`

The lifecycle CSV receives matching `REENTRY_BLOCKED` and `REENTRY_ALLOWED` event rows with the symbol, side, close time, bars elapsed, remaining bars, and reason in the `extra` field. `OPPOSITE_SIGNAL_CHECK` is logged in Experts when a confirmed opposite-side candidate is allowed to continue through standard checks.

## Preserved v1.4.5.12 behavior and constraints

- Daily first-ten closed-trade selector and short-net recovery latch.
- Cost-aware progressive loss exit and existing small-profit behavior.
- Original broker SL is not widened, removed, or replaced by this feature.
- Adaptive SL tightening and favorable-progression TP extension.
- Existing commission, swap, spread, slippage reserve, and portfolio risk checks.
- USD 500 reference capital; 0.5% per trade; 2.5% aggregate risk; maximum five open positions.
- `InpEnableDailyLossBlock=false` remains unchanged. The daily loss threshold remains warning-only.
- No changes to BiteFixes, its website, or its database.

## Validation required before use

1. Compile in MetaEditor and resolve all errors and warnings.
2. In Strategy Tester, verify: losing BUY blocks BUY for six completed bars; losing SELL blocks SELL; opposite confirmed signal can pass; weak opposite signal cannot enter; profitable close does not block; two opposite protected losses trigger both-side lockout; unrelated symbols remain tradable.
3. Restart the EA and terminal between test cases to verify persistent Global Variable state.
4. Inspect Experts and lifecycle CSV for the expected events and bar counts.
5. Demo forward-test with broker-specific symbols, history loaded, commissions and swaps included.

Static source checks are not a substitute for MetaEditor compilation, Strategy Tester, or demo execution validation.
