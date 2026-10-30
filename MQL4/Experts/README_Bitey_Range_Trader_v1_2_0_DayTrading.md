# Bitey Range Trader v1.2.0 — Day Trading (Range + Breakout)

Independent MT4 Expert Advisor on a feature branch. It does not replace v1.1.0, alter the default branch, or modify Bitey SBT ensemble EAs.

## Operating profile
- Forex and broker-listed crypto/CFD symbols, subject to broker contract specifications.
- Range-edge rejection plus confirmed breakout continuation.
- All-day evaluation, with no London/New York session restriction. The EA evaluates when broker ticks arrive; it does not force trades.
- M15 range context; breakout requires the latest completed M5 candle to agree.
- Chart symbol only. Attach one instance per symbol; it does not scan Market Watch.

## Entry logic
- Range BUY on bullish rejection near lower edge; range SELL on bearish rejection near upper edge. Optional RSI filter applies to range entries.
- Breakout BUY/SELL when a completed M15 candle closes beyond a range boundary by the ATR buffer and the last completed M5 candle confirms direction.
- ATR width, spread, stop-level, daily-loss and trade-count guards apply. No signal means HOLD.

## Day-trading controls
- `EnableTrading=true` by default. The EA does not block entries based on account type: Strategy Tester, demo and real accounts use the same entry logic.
- There is no `IsDemo()` / `IsTesting()` account-type gate and no `AllowLiveTrading` switch. The terminal's AutoTrading permission, EA trading permission, broker permissions and the `EnableTrading` input must still allow trading.
- Real-account use carries financial risk. Validate the EA in Strategy Tester and demo before enabling it on a real account; the EA's risk guards do not guarantee a maximum realized loss.
- Risk 0.25% of balance per trade; lot volume rounds down, never up.
- Maximum 3 entries per symbol per broker-server day; one open position per symbol/Magic Number.
- Daily equity-drawdown guard 2% from a terminal-persistent start-of-day equity baseline, keyed by account, Magic Number and broker-server date. Floating P/L is included; the guard blocks new entries, it does not forcibly close positions.
- Maximum holding time 8 hours by default.
- Close positions 10 minutes before broker-server midnight by default (not local PC time).
- Net-profit lock activates at floating net P/L >= 1.00 account-currency unit and attempts to tighten SL to an estimated 0.20 net floor.
- No martingale, averaging down, or loss-based lot increases.

## Forex and crypto cautions
MT4 crypto symbols are broker-specific contracts/CFDs, not necessarily spot crypto. Tick value/size, lot step, minimum lot, trading hours, spread and commission vary. Validate each symbol. The 30-point spread default is not universal and may block crypto or some FX instruments; adjust only after measuring broker conditions.

## Installation and validation
1. Copy the EA into MQL4/Experts/.
2. Compile in MetaEditor and resolve all errors and warnings.
3. Run the Strategy Tester and inspect logs; confirm `trading=ON`.
4. Backtest each instrument separately with realistic variable spread, commission, swap and quality tick history. Verify tick value, tick size, minimum lot and lot step for every broker symbol.
5. Demo-test order sizing, stop distances, M5 confirmation, daily guard, holding/day-end exits and net lock.
6. Only after validation, decide whether to enable it on a real account. Compare out-of-sample results with v1.1.0. No profitability claim is made. Static code review is not a substitute for MetaEditor compilation and broker-specific demo validation.

## Known limitations
- This authoring step did not compile or backtest the EA.
- M5 confirmation is a simple directional filter, not proof of breakout continuation.
- False breakouts, news spikes, low liquidity and spread widening can cause losses.
- Strategy Tester deliberately captures a fresh daily baseline for each test run. On live/demo terminal instances, the persistent baseline is local to that MT4 terminal; deleting terminal Global Variables or changing the Magic Number creates a new baseline.
- Trade count depends on terminal-loaded account history.
- Day-end close can incur slippage, spread widening or broker rejection.
- Net lock is an estimate using the broker's current tick value/size and reported swap/commission; realized P/L can differ.
- The tick-value calculations assume the broker reports `MODE_TICKSIZE` in MT4 points, as specified by the MQL4 interface. Confirm unusual CFD/crypto contract specifications with the broker.
- Use distinct Magic Numbers for multiple instances on the same symbol.
