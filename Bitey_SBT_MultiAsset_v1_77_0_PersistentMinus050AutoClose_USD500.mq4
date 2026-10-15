#property strict
#property version   "1.770"
#property description "Bitey SBT Multi-Asset v1.77.0 - persistent -USD0.50 auto-close after 60s, fixed USD500"

// ============================================================================
// BITEY SBT v1.73.0 — AUTHORITATIVE RISK / POSITION MANAGEMENT RULES
// These comments document intended safeguards; runtime enforcement and broker
// acceptance must still be verified in MetaEditor, Strategy Tester and demo.
// 1) FIXED STRATEGY CAPITAL: USD 500 maximum reference allocation. Never scale
//    this value from MT4 balance/equity. Account currency must be USD.
// 2) PER-POSITION STOP RISK: maximum calculated stop risk is USD25 (5% of fixed USD500).
//    Evidence may adapt the requested budget up to this cap, never beyond it. Validate tick
//    size/value, lot size, contract specs, costs and SL readback; fail closed if unknown.
//    Never widen an SL to fit a lot.
// 3) EXISTING POSITIONS: re-audit open positions under this EA's magic across
//    symbols. Try to tighten an over-risk SL. If the cap cannot be enforced or
//    confirmed by broker readback, attempt an emergency market close and log
//    the result/error. A close attempt is NOT a guarantee the broker will fill.
// 4) PORTFOLIO PRIORITY: target capacity is seven simultaneous positions, exactly
//    one per canonical asset (broker aliases count as the same asset). Do NOT reduce
//    the slot count because of campaign profit/loss tiers. Entry is still blocked
//    whenever aggregate calculated open stop-risk headroom is insufficient. Aggregate
//    ceiling USD100, per-position ceiling USD25; actual lots must fit the selected
//    symbol's tick value, contract size, spread, commission/swap estimate, SL distance,
//    margin and remaining portfolio headroom. Seven slots are capacity, not a forced quota.
// 5) DAILY LOSS: at -USD25 net for the trading day, block new entries while
//    continuing protective management of existing positions.
// 6) COST-AWARE ADAPTIVE SL/TP: manage all open symbols for this magic. Include
//    floating profit, swap and commission in the net-profit trigger; calculate break-even
//    and profit-lock levels against the symbol's tick size/value and entry price, while
//    accounting for spread and known trade costs where broker metadata permits. Require
//    three favorable fully closed management candles before ordinary adaptive changes.
//    SL may only tighten; never widen risk. TP may extend only in the favorable direction
//    when price progression and cost-adjusted profit conditions pass. Validate stop/freeze
//    levels and broker readback after every modification. Unknown cost metadata fails closed.
// 7) ENTRY QUALITY / EXECUTION: market data, spread, quote freshness, lot,
//    margin, symbol specification, evidence/holdout, duplicate-entry, daily
//    loss, position-count and aggregate-risk gates remain mandatory. Ranking
//    an asset alone is not authorization to trade.
// 8) CONTROL / SAFETY: MT4 remains the execution authority; telemetry and
//    Q-learning reports must not authorize or bypass an order. No martingale,
//    no stop-loss bypass, no automatic account switching.
// 9) LIMITATION: configured adaptive risk is a calculated stop-risk ceiling, not a guarantee of
//    realized loss. Gaps, slippage, spread changes, conversion/tick-value
//    differences, requotes, rejected modifications or failed closes can cause
//    a larger loss. Log every breach and failed protective action explicitly.
// ============================================================================

// RECONSTRUCTION NOTE: rebuilt from Library v1.49.7 plus available 2026-10-12 diagnostics; exact v1.51.4 source was not found.
// v1.62: carries forward the broker symbol-to-canonical-asset validation immediately before each OrderSend; order comments identify the canonical asset.
// v1.60: rate-limits successful adaptive SL/TP changes to at most one per ticket per newly closed management-timeframe candle.
// v1.51.5: separates training from chronological holdout metrics, logs threshold failures, verifies opened-order SL/TP by readback, and audits managed positions.
// v1.51.7: supervises all symbols sharing this magic, per-ticket cooldown, and rate-limited idle-decision audit. v1.51.9 blocks same-direction stacking in the chart execution path so one canonical asset can hold at most one live position. v1.57.0 added the strict net-profit gate. v1.58.0 adds the configurable loss/profit USD risk ladder; v1.58.1 corrects virtual capital so it remains fixed at USD500 independently of account equity and requires three favorable closed candles before adaptive SL/TP changes. Reconstructed from v1.49.7 + available diagnostics; not an exact patch of missing v1.51.4.
// IMPORTANT
// - AUTO_EXECUTION is the default; account classification is reported but never gates orders.
// - The EA uses a fixed virtual strategy allocation of USD 500, not the whole account balance.
// - Campaign net P/L <= -USD 50 switches the engine to STRICT mode, not a permanent stop.
// - Campaign net P/L >= +USD 100 enables limited evidence flexibility.
// - Campaign net P/L >= +USD 200 activates the legacy profit-protect evidence mode; the separate adaptive USD ladder still controls per-trade risk after sustained-profit confirmation.
// - Hard risk, daily loss, spread, open-position, and evidence gates remain active; no daily profit target or entry quota.
// - Historical evidence is an in-sample diagnostic, not proof of future profitability.
// v1.73.0: prioritizes the seven-asset portfolio objective: up to seven distinct canonical assets concurrently, exactly one position per asset, no profit-tier slot throttling, and candidate evaluation in descending evidence-adjusted rank. Each candidate must pass the asset-scoped local ensemble and independent chronological train/holdout evidence, quote freshness, spread, lot, margin, cost-aware SL/TP, duplicate-asset, daily-loss and aggregate-risk gates. Fixed strategy capital USD500. Portfolio risk ceiling USD100; per-position ceiling USD25; daily loss cutoff USD25. Capacity never forces a trade. NOTE: this source currently implements 16 local model families per asset plus 16 cross-asset proxy families; it does not silently disable two local families. v1.70.0: corrects higher-timeframe look-ahead by using only the last fully closed HTF candle for live and historical signals; aligns Market Watch alias selection/history sufficiency to InpCrossAssetTimeframe; updates runtime identity and audit messages. All 16 local model families are evaluated independently on each candidate symbol, with per-model evidence and cross-asset chronological train/holdout gates. USD500 capital, adaptive risk and portfolio protections remain mandatory.
// v1.66.0: all 16 local model families accept explicit symbol/timeframe parameters. Cross-asset candidates must pass the independent local 16-model direction consensus and per-model historical evidence gate on that candidate symbol before any order sizing/send. Existing cross-asset train/chronological-holdout gates, USD500 virtual capital, adaptive risk and portfolio protections remain mandatory.
// v1.64.1: fails closed on unknown per-position risk metadata or invalid cap distance by attempting emergency close; portfolio risk remains unknown and blocks new entries until verified.
// v1.64.0: based on v1.63.8; adds profit-aware dynamic capacity from 1 to 7 simultaneous canonical assets.
// Slots 1-3 are the defensive/base range; slots 4-7 unlock only as campaign net profit grows. Losses scale capacity down.
// Maximum remains seven because one position per canonical asset is mandatory; there is no infinite position count.
// Every candidate must still pass the existing 16-model ensemble/evidence, holdout, quote, spread, lot, SLTP,
// adaptive per-position risk, daily-loss, duplicate-asset and portfolio-risk gates.
// v1.41: corrects tick-size conversion after live log revealed a 1000x risk/cost overestimate; permits up to three simultaneous positions only on distinct symbols; target risk remains USD1.25 per position, aggregate stop-risk cap USD3.75, hard per-position risk <= USD1.25 and daily loss cap USD10. Each chart instance must independently pass its closed-bar model evidence and trade gates. Existing portfolio positions are audited for symbol duplication, stop-defined risk, floating P/L and crypto concentration before another entry. v1.43 adds a chronological recent holdout segment to each per-symbol directional history proxy and requires the holdout to pass independently; v1.44 adds current-bar near-miss diagnostics only; v1.45 adds per-model BUY/SELL subcondition audits and richer incumbent-versus-candidate comparison logs without changing entry/evidence/risk gates; v1.46 adds a compact no-raw-signal diagnosis and explicit audit provenance. v1.47 adds symbol-specific evidence-gated cross-asset orders; v1.48 ranks cross-assets with 14 model-family proxies; v1.49 restricts the universe to EURUSD, USDJPY, SOLUSD(T), NEARUSD(T), BTCUSD(T), XAUUSD and ETHUSD(T), expands to 16 model-family proxies, scans/ranks all seven, caps allocation at USD500, limits new entries to 7/day, per-trade target risk to USD1.25 (hard cap USD2), daily loss to USD4.50 and daily net-profit entry stop to USD30, with up to 3 concurrent positions and USD3.75 aggregate stop risk. v1.49.3 deduplicates broker aliases so only one best-qualified symbol per canonical asset is ranked and scanned. v1.49.4 attempts at most one new cross-asset entry per evaluation pass, trying candidates in descending evidence-adjusted priority and moving to the next only when a higher-ranked candidate fails a live execution/risk gate. v1.49.5 resolves a directional conflict when the winning side has at least one currently-signalled evidence-qualified model and its best reliability-adjusted expected-R score exceeds the opposing side by max(0.02R, 15% of the larger absolute score); non-conflicted entries still require the configured vote threshold. No model evidence, execution, or portfolio-risk gate is bypassed. v1.49.6 adds incumbent remaining SL/TP reward/risk versus fresh same-direction entry cost diagnostics; v1.49.7 permits up to three concurrent positions while retaining aggregate risk gates; v1.63.8 hardens per-position risk to USD1.25, aggregate risk to USD3.75, and attempts emergency close if the stop cap cannot be confirmed. Historical proxy is not a guarantee; execution requires broker quote/specification, cost, stop, lot, daily loss, trade-count and aggregate-risk gates.

enum EngineMode { OBSERVE_ONLY=0, AUTO_EXECUTION=1 };
enum AccountTypeReport { ACCOUNT_REPORT_AUTO=0, ACCOUNT_REPORT_DEMO_CONFIRMED=1, ACCOUNT_REPORT_REAL_CONFIRMED=2 };
enum ModelId { MODEL_TREND=0, MODEL_MOMENTUM=1, MODEL_DONCHIAN=2, MODEL_MEANREV=3, MODEL_STRICT_RANGE=4, MODEL_ATR_BREAKOUT=5, MODEL_SESSION_BIAS=6, MODEL_RSI_DIVERGENCE=7, MODEL_HTF_TREND=8, MODEL_VWAP_DEVIATION=9, MODEL_BREAK_RETEST=10, MODEL_FIB_PULLBACK=11, MODEL_VOL_SQUEEZE=12, MODEL_LINEAR_REGRESSION=13, MODEL_MACD_CONFIRM=14, MODEL_BOLLINGER_EXPANSION=15 };
enum TestOrderDirection { TEST_ORDER_SELL=-1, TEST_ORDER_BUY=1 };

input EngineMode InpMode = AUTO_EXECUTION;
input int      InpMagic = 10102027;
// AUTO reports the terminal-detected classification; terminal IsDemo() remains the factual diagnostic.
input AccountTypeReport InpAccountTypeReport = ACCOUNT_REPORT_AUTO; // Requested configuration; does NOT falsify terminal IsDemo().
input bool     InpBlockOnAccountTypeMismatch = false; // Compatibility only; DEMO/REAL mismatch never gates orders.
input double   InpOperatingCapitalUSD = 500.0;
input double   InpRoundTurnCommissionPerLotUSD = -1.0; // UNKNOWN by default: set actual round-turn commission per 1.00 lot; use 0 only if broker is commission-free. Negative value blocks new entries.
input double   InpExpectedSwapCostPerLotUSD = -1.0; // UNKNOWN by default: set a conservative holding swap cost per 1.00 lot; use 0 only if verified not applicable. Negative value blocks new entries.
input double   InpRiskPerTradeUSD = 5.00; // Baseline only; evidence may raise it within configured and remaining risk headroom.
input double   InpHardRiskCapUSD = 25.00; // Hard per-position stop-risk ceiling: USD25 (5% of fixed USD500), further bounded by headroom.
input int      InpMaxPositionsPerAsset = 1; // Exactly one open position per canonical asset, including broker aliases.
input double   InpDailyLossLimitUSD = 25.00; // USD500 capital: block new entries at -USD25 (5%); continue protective management.
input double   InpDailyProfitTargetUSD = 0.00; // Deprecated compatibility input; daily profit targets never block new entries.
input int      InpMaxTradesPerDay = 0; // Deprecated compatibility input; no daily entry quota is enforced.
input int      InpMaxOpenTrades = 7; // Active portfolio capacity: up to seven distinct canonical assets; risk gates may still block entries.
input string   InpAllowedSymbols = "*"; // "*" admits every symbol visible in MT4 Market Watch; explicit lists can restrict it.
input bool     InpMarketWatchScannerEnabled = true; // Discovers active instruments in Market Watch; discovery alone never authorizes an order.
input int      InpMarketWatchScanIntervalSeconds = 60; // Periodic quote/history/specification scan.
input bool     InpCrossAssetRankingEnabled = true; // Rank discovered symbols using independent H1 trend/momentum/RSI/ADX checks; ranking does not itself authorize orders.
input int      InpCrossAssetTimeframe = PERIOD_H1; // Cross-asset ranking timeframe.
input int      InpCrossAssetTopLogCount = 7; // Number of highest-ranked eligible symbols to report.
input bool     InpCrossAssetAutoExecutionEnabled = true; // Master switch for cross-symbol execution; additional evidence gate below applies.
input double   InpCrossAssetMinTechnicalScore = 58.0; // Minimum technical ranking score; not proof of profitability.
input int      InpCrossAssetMinHistorySamples = 12; // Minimum non-overlapping historical directional samples before an asset can be evidence-qualified.
input double   InpCrossAssetMinHistoryWinRate = 0.42; // Historical proxy win-rate floor; not a guarantee.
input double   InpCrossAssetMinHistoryAvgR = 0.02; // Cost-adjusted ATR-normalized return proxy floor; not actual trade R.
input int      InpCrossAssetMinHoldoutSamples = 6; // Minimum recent chronological holdout samples; fail closed if not available.
input double   InpCrossAssetMinHoldoutWinRate = 0.40; // Holdout proxy win-rate floor.
input double   InpCrossAssetMinHoldoutAvgR = 0.00; // Holdout proxy average net R must be positive.
input bool     InpAllowTechnicalOnlyCrossAssetExecution = true; // Legacy-compatible execution switch; train AND holdout evidence are still mandatory; technical-only candidates are never ranked for execution.
input int      InpCrossAssetMaxCryptoPositions = 7; // Up to seven distinct crypto assets permitted; aggregate USD100 and per-position USD25 risk caps still apply.
input int      InpCrossAssetMaxQuoteAgeSeconds = 120; // Reject stale cross-symbol quotes.
input bool     InpAutoAllowDetectedCryptoOnChart = false; // Legacy compatibility only; strict seven-asset allowlist always applies.
input double   InpPortfolioOpenRiskCapUSD = 100.00; // Aggregate calculated open stop-risk ceiling: USD100 (20% of fixed USD500), required headroom for up to seven qualified assets.
input bool     InpAdaptiveRiskLadderEnabled = true; // Adapt maximum USD risk per new trade to sustained portfolio P/L.
input double   InpLossRiskConfirmedUSD = 1.25; // Conservative adaptive budget after loss confirmation; absolute per-position cap remains USD25.
input double   InpLossRiskPersistentUSD = 0.75; // Reduce risk during persistent losses.
input double   InpLossRiskSevereUSD = 0.35; // Reduce risk during severe/prolonged losses.
input double   InpSeverePortfolioLossTriggerUSD = 5.00; // Immediate severe state when campaign net P/L reaches -USD5.
input int      InpLossConfirmMinutes = 5; // Negative net portfolio result must persist this long before confirmed-loss state.
input int      InpPersistentLossMinutes = 15; // Persistent negative result steps risk down to USD2.
input int      InpSevereLossMinutes = 60; // Long-running loss also steps risk down to USD1.
input double   InpProfitActivationThresholdUSD = 0.50; // Portfolio net P/L must exceed this value to start profit persistence timer.
input int      InpProfitSustainMinutes = 60; // Positive net portfolio result must persist this long before risk can rise to USD5+.
input double   InpProfitRiskStepUSD = 5.00; // Each additional USD5 of campaign net profit advances the risk budget by USD1.
input double   InpAdaptiveRiskMaximumUSD = 25.00; // Adaptive per-position ceiling: USD25; headroom remains authoritative.
input double   InpMaxRiskPerTradeCapitalPct = 5.00; // Absolute per-position ceiling: 5% of fixed USD500 = USD25.
input int      InpMaxSpreadSOLPoints = 100;
input int      InpMaxSpreadEURPoints = 30;
input int      InpMaxSpreadUSDJPYPoints = 35;
input int      InpMaxSpreadNEARPoints = 100;
input int      InpMaxSpreadBTCPoints = 200;
input int      InpMaxSpreadXAUPoints = 80;
input int      InpMaxSpreadETHPoints = 150;
input int      InpMaxSpreadOtherCryptoPoints = 150; // Applies only to ETH/BTC/NEAR/SOL members of the fixed universe; verify broker point scale.
// Conservative replacement: require a validated alternative and confirm its entry before closing the incumbent.
input bool     InpEnablePositionReplacement = false;
input bool     InpPositionReplacementAuditOnly = false; // Replacement still requires safe prechecks and a confirmed alternative order.
input int      InpPositionMonitorSeconds = 5;  // Monitor open position/risk on a short timer.
input int      InpSignalRecheckSeconds = 30;   // Re-evaluate models periodically; entries remain anti-duplicate per bar.
input double   InpReplacementMinExpectedRScore = 0.30; // Reliability-adjusted score threshold; not a profit guarantee.
input double   InpReplacementMinScoreAdvantage = 0.10; // Candidate must materially outrank the incumbent direction.
input double   InpReplacementMinFloatingLossUSD = 0.10; // Legacy input retained for .set compatibility; v1.28 no longer requires a floating loss to reverse.
input int      InpMaxSpreadPoints = 100; // Legacy .set compatibility only; v1.30 uses per-symbol spread ceilings below.
// OFF by default. When enabled, attempts one test order on either demo or real accounts.
// This can place a REAL order. It bypasses signal/evidence selection only; all trading, spread, capital, lot, SL/TP and loss gates remain active.
input bool     InpOneShotTestMode = false; // Continuous signal/evidence mode by default; no forced one-shot order.
input TestOrderDirection InpTestOrderDirection = TEST_ORDER_BUY;
input double   InpCampaignLossStopUSD = 50.00; // At -$50, switch to STRICT; not a permanent stop.
input double   InpStrictLossThresholdUSD = 50.00;
input double   InpProfitFlexThresholdUSD = 100.00; // +$100 campaign P/L means $600 equivalent from the $500 reference.
input double   InpProfitProtectThresholdUSD = 200.00;
input int      InpResetGovernorToken = 0; // Legacy compatibility only; no longer needed to clear a campaign-loss lock.
input int      InpSlippagePoints = 10;
input bool     InpWriteCSV = true;
input bool     InpPrintDiagnostics = true;

// Optional reporting to the SBT Worker. Add the workers.dev origin to MT4 Tools > Options > Expert Advisors > Allow WebRequest. Reporting is read-only and never controls execution.
input bool     InpSbtTelemetryEnabled = true;
input string   InpSbtTelemetryURL = "https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/mt4/bitey-report";
input string   InpSbtToken = "";
input int      InpSbtTelemetryTimeoutMs = 5000; // More tolerance for transient Worker/network latency; telemetry never decides whether an order is allowed.
input bool     InpSbtClosedTradeReportsEnabled = true;
input string   InpSbtClosedTradeURL = "https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/mt4/trade-closed";
input bool     InpQlearningExperienceEnabled = true; // Sends realized transitions; SBT backend owns learning updates.

// Fixed virtual strategy allocation. It deliberately does NOT change with broker balance/equity.
// This is a strategy sizing reference, not a segregated account or a promise that the broker
// account can absorb the resulting loss. Actual margin, free-margin, symbol and order checks
// remain mandatory before sending any order. Account currency must be USD.
double EffectiveOperatingCapitalUSD()
{
   if(AccountCurrency()!="USD" || InpOperatingCapitalUSD<=0.0) return 0.0;
   return MathMin(500.0,InpOperatingCapitalUSD);
}

double EffectiveDailyLossLimitUSD()
{
   double capital=EffectiveOperatingCapitalUSD();
   if(capital<=0.0) return 0.0;
   return MathMin(25.0,MathMin(MathAbs(InpDailyLossLimitUSD),capital*0.05));
}


// Seven-slot portfolio capacity is fixed by configuration up to the hard ceiling of seven.
// Prototypes are required because the gates call these helpers throughout the EA.
int EffectiveMaxOpenTrades();
double EffectivePortfolioRiskCapUSD();


// Portfolio objective: keep all seven distinct-asset slots available regardless of campaign P/L tiers.
// Adaptive risk may reduce order size during losses, but never silently reduces slot capacity.
// USD100 aggregate calculated stop-risk, USD25 per-position, and USD25 daily-loss gates remain authoritative.
int EffectiveMaxOpenTrades()
{
   double net = CampaignNetProfitUSD();
   g_campaignNetUSD = net;
   return (int)MathMax(1, MathMin(7, InpMaxOpenTrades));
}

// Aggregate stop-risk budget is capped at USD100; per-position risk is capped at USD25 and remaining headroom.
// This does not guarantee realized losses due to gaps, slippage, spread, or execution failures.
double EffectivePortfolioRiskCapUSD()
{
   int slots = EffectiveMaxOpenTrades();
   double perPositionCap = MathMin(25.0,MathMin(EffectiveOperatingCapitalUSD()*MathMax(0.01,InpMaxRiskPerTradeCapitalPct)/100.0, MathMin(InpAdaptiveRiskMaximumUSD, InpHardRiskCapUSD)));
   if(slots < 1 || perPositionCap <= 0.0) return 0.0;
   return MathMin(100.0,MathMin(MathAbs(InpPortfolioOpenRiskCapUSD), slots * perPositionCap));
}

// Raise the base risk budget only when both chronological training and holdout evidence exceed their pass floors.
// This is a bounded sizing multiplier, not a claim that the strategy can predict or maximize future profit.
double EvidenceAdaptiveRiskBudget(double baseRisk,double trainWR,double trainAvgR,double holdoutWR,double holdoutAvgR)
{
   double capital=EffectiveOperatingCapitalUSD();
   if(baseRisk<=0.0 || capital<=0.0) return 0.0;
   double cap=MathMin(InpHardRiskCapUSD,MathMin(InpAdaptiveRiskMaximumUSD,capital*InpMaxRiskPerTradeCapitalPct/100.0));
   double wrFloor=InpCrossAssetMinHistoryWinRate, rFloor=InpCrossAssetMinHistoryAvgR;
   double hwrFloor=InpCrossAssetMinHoldoutWinRate, hrFloor=InpCrossAssetMinHoldoutAvgR;
   if(trainWR<wrFloor || trainAvgR<=rFloor || holdoutWR<hwrFloor || holdoutAvgR<=hrFloor) return MathMin(baseRisk,cap);
   // Each evidence component contributes a modest, bounded increment; all four must pass first.
   double strength=MathMax(0.0,MathMin(1.0,(trainWR-wrFloor)/0.20))
                 +MathMax(0.0,MathMin(1.0,(trainAvgR-rFloor)/0.10))
                 +MathMax(0.0,MathMin(1.0,(holdoutWR-hwrFloor)/0.20))
                 +MathMax(0.0,MathMin(1.0,(holdoutAvgR-hrFloor)/0.10));
   double multiplier=1.0+0.25*strength; // 1.0x to 2.0x base risk only on passing train AND holdout.
   double result=MathMin(cap,baseRisk*multiplier);
   Print("EVIDENCE_ADAPTIVE_RISK | baseUSD=",DoubleToString(baseRisk,2),
         " multiplier=",DoubleToString(multiplier,2)," trainWR=",DoubleToString(trainWR,3),
         " trainAvgR=",DoubleToString(trainAvgR,3)," holdoutWR=",DoubleToString(holdoutWR,3),
         " holdoutAvgR=",DoubleToString(holdoutAvgR,3)," capUSD=",DoubleToString(cap,2),
         " selectedRiskUSD=",DoubleToString(result,2)," note=historical proxy not a profit guarantee");
   return result;
}

double EffectiveRiskBudgetUSD()
{
   double capital=EffectiveOperatingCapitalUSD();
   if(capital<=0.0) return 0.0;

   double risk=MathMax(0.0,InpRiskPerTradeUSD);
   string profitSinceKey=GovernorKey("ADAPTIVE_PROFIT_SINCE");
   string lossSinceKey=GovernorKey("ADAPTIVE_LOSS_SINCE");
   string lastLevelKey=GovernorKey("ADAPTIVE_RISK_LAST_LEVEL");
   string lastStateKey=GovernorKey("ADAPTIVE_RISK_LAST_STATE");
   int stateCode=0;
   double net=CampaignNetProfitUSD();
   g_campaignNetUSD=net;
   datetime now=TimeCurrent();
   double profitSince=(GlobalVariableCheck(profitSinceKey)?GlobalVariableGet(profitSinceKey):0.0);
   double lossSince=(GlobalVariableCheck(lossSinceKey)?GlobalVariableGet(lossSinceKey):0.0);
   string state="NEUTRAL_BASELINE";

   if(!InpAdaptiveRiskLadderEnabled)
   {
      risk=MathMin(InpRiskPerTradeUSD,capital);
      state="ADAPTIVE_LADDER_DISABLED";
      stateCode=0;
   }
   else if(net < 0.0)
   {
      if(profitSince>0.0) GlobalVariableDel(profitSinceKey);
      if(lossSince<=0.0)
      {
         lossSince=(double)now;
         GlobalVariableSet(lossSinceKey,lossSince);
      }
      int lossMinutes=(int)MathMax(0,(now-(datetime)lossSince)/60);
      if(net<=-MathAbs(InpSeverePortfolioLossTriggerUSD) || lossMinutes>=InpSevereLossMinutes)
      {
         risk=InpLossRiskSevereUSD;
         state="LOSS_SEVERE_1USD";
         stateCode=1;
      }
      else if(lossMinutes>=InpPersistentLossMinutes)
      {
         risk=InpLossRiskPersistentUSD;
         state="LOSS_PERSISTENT_2USD";
         stateCode=2;
      }
      else if(lossMinutes>=InpLossConfirmMinutes)
      {
         risk=InpLossRiskConfirmedUSD;
         state="LOSS_CONFIRMED_3USD";
         stateCode=3;
      }
      else
      {
         risk=InpLossRiskConfirmedUSD;
         state="LOSS_CONFIRMATION_PENDING_CONSERVATIVE_3USD";
         stateCode=4;
      }
   }
   else if(net>MathMax(0.0,InpProfitActivationThresholdUSD))
   {
      if(lossSince>0.0) GlobalVariableDel(lossSinceKey);
      if(profitSince<=0.0)
      {
         profitSince=(double)now;
         GlobalVariableSet(profitSinceKey,profitSince);
      }
      int profitMinutes=(int)MathMax(0,(now-(datetime)profitSince)/60);
      if(profitMinutes>=MathMax(1,InpProfitSustainMinutes))
      {
         double excessProfit=MathMax(0.0,net-MathMax(0.0,InpProfitActivationThresholdUSD));
         int profitSteps=(InpProfitRiskStepUSD>0.0?(int)MathFloor(excessProfit/InpProfitRiskStepUSD):0);
         risk=5.0+profitSteps;
         risk=MathMin(risk,MathMax(InpRiskPerTradeUSD,InpAdaptiveRiskMaximumUSD));
         state="SUSTAINED_PROFIT_RISK_"+DoubleToString(risk,0)+"USD";
         stateCode=10+(int)MathRound(risk);
      }
      else
      {
         risk=InpRiskPerTradeUSD;
         state="PROFIT_PERSISTENCE_PENDING_BASELINE";
         stateCode=5;
      }
   }
   else
   {
      if(profitSince>0.0) GlobalVariableDel(profitSinceKey);
      if(lossSince>0.0) GlobalVariableDel(lossSinceKey);
      risk=InpRiskPerTradeUSD;
      state="NEUTRAL_BASELINE_ADAPTIVE_CAP";
      stateCode=6;
   }

   risk=MathMin(risk,MathMin(25.0,MathMin(capital*MathMax(0.01,InpMaxRiskPerTradeCapitalPct)/100.0,MathMin(InpHardRiskCapUSD,MathMax(0.01,InpAdaptiveRiskMaximumUSD)))));
   // Provisional model evidence remains deliberately half-risk; never increase risk for weak evidence.
   if(g_currentProvisionalEntry) risk=MathMin(risk,InpLossRiskConfirmedUSD*0.50);
   risk=MathMin(risk,MathMin(25.0,MathMin(capital*MathMax(0.01,InpMaxRiskPerTradeCapitalPct)/100.0,InpHardRiskCapUSD))); // Fixed USD25 hard cap.
   // Dynamic risk is bounded by remaining daily-loss and aggregate portfolio risk.
   double openRiskNow=PortfolioOpenRiskUSD();
   double dailyNetNow=TodayNetProfit();
   double dailyLossHeadroom=EffectiveDailyLossLimitUSD()+dailyNetNow;
   double portfolioRiskHeadroom=(openRiskNow>=0.0?EffectivePortfolioRiskCapUSD()-openRiskNow:0.0);
   if(openRiskNow<0.0)
   {
      Print("DYNAMIC RISK BLOCK | reason=UNKNOWN_EXISTING_PORTFOLIO_STOP_RISK action=NO_NEW_ENTRY");
      risk=0.0;
   }
   else
   {
      if(dailyLossHeadroom<0.0) dailyLossHeadroom=0.0;
      if(portfolioRiskHeadroom<0.0) portfolioRiskHeadroom=0.0;
      risk=MathMin(risk,MathMin(dailyLossHeadroom,portfolioRiskHeadroom));
   }

   risk=MathMin(risk,MathMin(25.0,MathMin(InpHardRiskCapUSD,capital*MathMax(0.01,InpMaxRiskPerTradeCapitalPct)/100.0))); // Final fixed USD25 hard cap.
    double previousLevel=(GlobalVariableCheck(lastLevelKey)?GlobalVariableGet(lastLevelKey):-999.0);
   double previousState=(GlobalVariableCheck(lastStateKey)?GlobalVariableGet(lastStateKey):-999.0);
   if(MathAbs(previousLevel-risk)>0.001 || previousState!=(double)stateCode)
   {
      Print("ADAPTIVE RISK LADDER | state=",state,
            " campaignNetUSD=",DoubleToString(net,2),
            " profitSustainMinutes=",(profitSince>0.0?(int)MathMax(0,(now-(datetime)profitSince)/60):0),
            " lossPersistMinutes=",(lossSince>0.0?(int)MathMax(0,(now-(datetime)lossSince)/60):0),
            " riskBudgetUSD=",DoubleToString(risk,2),
            " dailyLossHeadroomUSD=",DoubleToString(MathMax(0.0,dailyLossHeadroom),2),
            " portfolioRiskHeadroomUSD=",DoubleToString(MathMax(0.0,portfolioRiskHeadroom),2),
            " legacyPerTradeCapFieldUSD=",DoubleToString(InpHardRiskCapUSD,2),
            " aggregateRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),2),
            " note=MAXIMUM_NOT_REQUIRED; aggregate_gate_still_authoritative");
      GlobalVariableSet(lastLevelKey,risk);
      GlobalVariableSet(lastStateKey,(double)stateCode);
      GlobalVariablesFlush();
   }
   return MathMax(0.0,risk);
}

input int      InpATRPeriod = 14;
input double   InpStopATR = 1.30;
input double   InpTargetATR = 2.60;
// Adaptive exit management (v1.59: three-candle, profit-only adaptive SL/TP)
input bool     InpAdaptiveSLTPEnabled = true;
input double   InpAdaptiveSLTPMinNetProfitUSD = 0.05; // Do not adapt SL/TP unless floating net P/L (profit+swap+commission) exceeds this USD threshold.
input ENUM_TIMEFRAMES InpAdaptiveSLTPTimeframe = PERIOD_H1; // Timeframe used to confirm three consecutive favorable closed candles on every managed asset.
input double   InpBreakEvenTriggerATR = 0.80; // Start profit lock after favorable move reaches this ATR multiple.
input double   InpBreakEvenLockATR = 0.10; // Lock a small price-distance gain beyond entry; costs/slippage still apply.
input double   InpTrailTriggerATR = 1.20; // Begin ATR trailing after a larger favorable move.
input double   InpTrailDistanceATR = 1.00; // Keep room for ordinary pullbacks while tightening monotonically.
input double   InpTPExtendTriggerATR = 1.00; // Extend TP only after price has advanced this far in favor.
input double   InpTPExtendDistanceATR = 2.00; // New TP target distance from current price when trend continuation is confirmed.
input double   InpSLTPMinChangeATR = 0.15; // Ignore tiny price changes to avoid repeated 0.01 modifications.
input int      InpSLTPModifyCooldownSeconds = 15; // Minimum delay between modify attempts on this EA instance.

input int      InpMaxHoldBars = 6;
input int      InpFastEMA = 8;
input int      InpSlowEMA = 21;
input int      InpTrendEMA = 200;
input int      InpRSIPeriod = 14;
input int      InpADXPeriod = 14;
input double   InpTrendADXMin = 18.0;
input int      InpDonchianPeriod = 20;
input int      InpMomentumLookback = 3;
input double   InpMomentumATRThreshold = 0.50; // Broader momentum trigger; evidence is recalculated with this exact rule.
input bool     InpMomentumTrendContinuation = true; // Adds a trend-aligned continuation signal; historical evidence still gates entry.
input double   InpContinuationBuyRSIMax = 75.0; // Avoid buying at an extreme RSI reading.
input double   InpContinuationSellRSIMin = 25.0; // Avoid selling at an extreme RSI reading.
input double   InpMeanRevADXMax = 22.0; // Candidate range regime; evidence gate still decides eligibility.
input double   InpMeanRevRSIBuy = 42.0; // Wider candidate band; historical evidence gate still decides eligibility.
input double   InpMeanRevRSISell = 58.0;
input double   InpStrictRangeADXMax = 20.0;
input int      InpStrictRangeLookback = 10;
input double   InpStrictRangeEdgeATR = 0.45;
input double   InpStrictRangeEMAGapATR = 0.75;
input double   InpStrictRangeBuyRSI = 45.0;
input double   InpStrictRangeSellRSI = 55.0;
input double   InpPullbackMaxGapATR = 0.35;
input double   InpBreakoutBufferATR = 0.02; // Earlier closed-bar Donchian confirmation; historical evidence uses the same buffer.
input int      InpVWAPLookback = 24;
input double   InpVWAPDeviationATR = 0.80;
input int      InpRetestLookback = 12;
input double   InpRetestToleranceATR = 0.20;
input int      InpFibLookback = 30;
input double   InpSqueezeWidthFactor = 0.80;
input int      InpRegressionLookback = 12;
input double   InpRegressionSlopeATR = 0.08;
input bool     InpUseRegimeAwareSelection = true;
input bool     InpUseMarkovRegimeContext = true; // Experimental regime-transition context; never bypasses evidence gates.


input int      InpEvidenceLookbackBars = 240;
input int      InpSignalAuditBars = 500; // Count each model's BUY/SELL triggers over recent closed bars; diagnostics only.
input int      InpForwardHorizonBars = 6;
input int      InpMinEvidenceSamples = 12;
input double   InpMinEvidenceWinRate = 0.42;
input double   InpMinEvidenceAvgR = 0.02;
input int      InpMinModelVotes = 2; // Require two independently evidence-qualified models by default.

#define MODEL_COUNT 16 // Sixteen live asset-scoped model families are evaluated independently for each candidate asset.
// Portfolio-selection contract: compare qualified candidates across assets using the ranked cross-asset ensemble;
// for every asset, retain the complete local family evaluation and its own chronological evidence. No asset inherits
// another symbol's signals or evidence. User requested 14 local models; this reconstruction preserves all 16 existing
// local families rather than silently dropping MACD/Bollinger logic without MetaEditor/Strategy Tester validation.
#define CROSS_ASSET_MODEL_COUNT 16 // Cross-asset proxy ensemble adds MACD and Bollinger expansion.
string   g_modelNames[MODEL_COUNT] = {"TREND","MOMENTUM","DONCHIAN","MEANREV","STRICT_RANGE","ATR_VOLATILITY_BREAKOUT","SESSION_BIAS","RSI_DIVERGENCE","HTF_TREND_CONFIRM","VWAP_DEVIATION","BREAK_RETEST","FIBONACCI_PULLBACK","VOLATILITY_SQUEEZE","LINEAR_REGRESSION","MACD_CONFIRM","BOLLINGER_EXPANSION"};
datetime g_lastBarTime = 0;
datetime g_lastTimerSignalEvaluation = 0;
datetime g_lastEntryAttemptBarTime = 0;
string g_lastEntryAttemptResult = "NO_PREVIOUS_ATTEMPT";
int g_lastEntryAttemptStatus = 0; // 0 none/unknown, 1 attempt in progress, 2 order opened, 3 attempt rejected/failed. Persisted numeric status only.
datetime g_lastStatusLogTime = 0;
datetime g_lastMarketWatchScanTime = 0;
string g_lastMarketWatchScanSignature = "";
string g_lastCrossAssetRankingSignature = "";
datetime g_lastCrossAssetExecutionTime = 0;
// Global work arrays: static storage avoids MetaEditor false-positive warnings
// about local scores[] initialization when the variable-bound summary loop runs.
string g_crossAssetRankNames[100];
double g_crossAssetRankScores[100];
double g_crossAssetRankPriority[100];
string g_crossAssetRankDirs[100];
int g_crossAssetRankSamples[100];
double g_crossAssetRankWinRates[100];
double g_crossAssetRankAvgR[100];
int g_crossAssetRankHoldoutSamples[100];
double g_crossAssetRankHoldoutWinRates[100];
double g_crossAssetRankHoldoutAvgR[100];
int g_serverLocalOffsetSeconds = 0; // Estimated at initialization for quote-age checks in OnTimer.
int      g_lastBarsGateLogged = -1;
string   g_currentBestStrategy = "NONE";
double   g_currentExpectedR = 0.0; // Reliability-adjusted historical expected R used by the global positive-net-expectancy gate.
int      g_currentStateId = 0;
double   g_currentRiskBudgetUSD = 0.0;
bool     g_currentProvisionalEntry = false; // True only for strong but sub-minimum-sample evidence; halves risk.
string   g_lastExecutionResult = "NOT_ATTEMPTED";
// Money-based governor. State values: 0 NORMAL, 1 STRICT, 2 PROFIT_FLEX, 3 PROFIT_PROTECT.
// Legacy state 4 is not used to block entries.
int      g_governorState = 0;
double   g_campaignStartTime = 0.0;
double   g_campaignNetUSD = 0.0;
string   g_governorBaseKey = "";

string GovernorKey(string suffix)
{
   return "BiteyRG_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+"_PORTFOLIO_"+suffix;
}

bool AccountTypeMismatch()
{
   // Detect disagreement between user-confirmed account mode and terminal classification.
   if(IsTesting()) return false;
   if(InpAccountTypeReport==ACCOUNT_REPORT_DEMO_CONFIRMED && !IsDemo()) return true;
   if(InpAccountTypeReport==ACCOUNT_REPORT_REAL_CONFIRMED && IsDemo()) return true;
   return false;
}

string ReportedAccountMode()
{
   if(IsTesting()) return "TESTER";
   if(InpAccountTypeReport==ACCOUNT_REPORT_DEMO_CONFIRMED) return "DEMO_CONFIGURED_BY_USER";
   if(InpAccountTypeReport==ACCOUNT_REPORT_REAL_CONFIRMED) return "REAL_CONFIRMED_BY_USER";
   return (IsDemo()?"DEMO_DETECTED_BY_TERMINAL":"REAL_OR_UNCLASSIFIED_BY_TERMINAL");
}

double CampaignNetProfitUSD()
{
   if(g_campaignStartTime<=0.0) return 0.0;
   double net=0.0;
   datetime start=(datetime)g_campaignStartTime;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()>=start) net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()==OP_BUY || OrderType()==OP_SELL)
         net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return net;
}

string GovernorStateName(int state)
{
   if(state==1) return "STRICT";
   if(state==2) return "PROFIT_FLEX";
   if(state==3) return "PROFIT_PROTECT";
   return "NORMAL";
}

void UpdateRiskGovernor()
{
   if(g_campaignStartTime<=0.0)
   {
      string startKey=GovernorKey("START");
      if(GlobalVariableCheck(startKey)) g_campaignStartTime=GlobalVariableGet(startKey);
      else { g_campaignStartTime=(double)TimeCurrent(); GlobalVariableSet(startKey,g_campaignStartTime); }
   }

   // Deliberately ignore any legacy STOP global variable from earlier versions.
   // A campaign loss of USD 50 changes strategy strictness; it does not permanently stop entries.
   g_campaignNetUSD=CampaignNetProfitUSD();
   int nextState=0;
   double strictThreshold=MathMax(MathAbs(InpCampaignLossStopUSD),MathAbs(InpStrictLossThresholdUSD));
   if(g_campaignNetUSD<=-strictThreshold) nextState=1;
   else if(g_campaignNetUSD>=MathAbs(InpProfitProtectThresholdUSD)) nextState=3;
   else if(g_campaignNetUSD>=MathAbs(InpProfitFlexThresholdUSD)) nextState=2;

   if(nextState!=g_governorState)
   {
      g_governorState=nextState;
      Print("RISK GOVERNOR STATE | ",GovernorStateName(g_governorState),
            " | campaignNetUSD=",DoubleToString(g_campaignNetUSD,2),
            " | strictAt=-",DoubleToString(strictThreshold,2),
            " | flexAt=+",DoubleToString(MathAbs(InpProfitFlexThresholdUSD),2),
            " | protectAt=+",DoubleToString(MathAbs(InpProfitProtectThresholdUSD),2),
            " | account classification is informational only.");
   }
   GlobalVariableSet(GovernorKey("STATE"),(double)g_governorState);
}

int RequiredModelVotes()
{
   if(g_governorState==1) return MathMax(2,InpMinModelVotes);
   return InpMinModelVotes;
}


struct DirectionEvidence
{
   int samples;
   int wins;
   double sumR;
   double winRate;
   double avgR;
};

void ResetEvidence(DirectionEvidence &e)
{
   e.samples=0; e.wins=0; e.sumR=0.0; e.winRate=0.0; e.avgR=0.0;
}

void FinalizeEvidence(DirectionEvidence &e)
{
   if(e.samples>0)
   {
      e.winRate=(double)e.wins/(double)e.samples;
      e.avgR=e.sumR/(double)e.samples;
   }
   else { e.winRate=0.0; e.avgR=0.0; }
}

string CanonicalAssetKey(string sym)
{
   StringToUpper(sym);
   // Normalize known aliases; other Market Watch instruments use their broker symbol as the canonical key.
   if(StringLen(sym)>=2 && StringSubstr(sym,0,2)=="M.") sym=StringSubstr(sym,2);
   if(StringLen(sym)>=1 && StringSubstr(sym,0,1)=="#") sym=StringSubstr(sym,1);
   if(StringFind(sym,"EURUSD")==0) return "EURUSD";
   if(StringFind(sym,"USDJPY")==0) return "USDJPY";
   if(StringFind(sym,"XAUUSD")==0) return "XAUUSD";
   if(StringFind(sym,"SOLUSDT")==0 || StringFind(sym,"SOLUSD")==0) return "SOLUSDT";
   if(StringFind(sym,"NEARUSDT")==0 || StringFind(sym,"NEARUSD")==0) return "NEARUSD";
   if(StringFind(sym,"BTCUSDT")==0 || StringFind(sym,"BTCUSD")==0 || StringFind(sym,"XBTUSD")==0) return "BTCUSDT";
   if(StringFind(sym,"ETHUSDT")==0 || StringFind(sym,"ETHUSD")==0) return "ETHUSD";
   // Other visible instruments use their normalized broker symbol as their asset key.
   return sym;
}

// Fail closed unless the requested broker symbol resolves to one approved canonical asset
// and has a live, internally consistent quote/specification. This guard does not rename symbols.
bool ValidateExecutionAssetSymbol(string sym,string expectedCanonical,string &reason)
{
   reason="";
   if(StringLen(sym)<=0) { reason="EMPTY_SYMBOL"; return false; }
   string actualCanonical=CanonicalAssetKey(sym);
   if(actualCanonical=="") { reason="SYMBOL_NOT_IN_APPROVED_ASSET_UNIVERSE"; return false; }
   if(expectedCanonical!="" && actualCanonical!=expectedCanonical)
   { reason="CANONICAL_ASSET_MISMATCH expected="+expectedCanonical+" actual="+actualCanonical; return false; }
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
   double point=MarketInfo(sym,MODE_POINT);
   if(bid<=0.0 || ask<bid || point<=0.0) { reason="INVALID_SYMBOL_QUOTE_OR_POINT"; return false; }
   if(MarketInfo(sym,MODE_TRADEALLOWED)==0) { reason="SYMBOL_TRADE_NOT_ALLOWED"; return false; }
   return true;
}

bool IsAllowedMultiAssetSymbol()
{
   string key=CanonicalAssetKey(Symbol());
   string list=InpAllowedSymbols;
   StringToUpper(list);
   StringReplace(list," ","");
   string padded=","+list+",";
   if(key!="" && (list=="*" || StringFind(padded,","+key+",")>=0)) return true;
   return false;
}

int MaxSpreadForCurrentSymbol()
{
   string key=CanonicalAssetKey(Symbol());
   if(key=="SOLUSDT") return InpMaxSpreadSOLPoints;
   if(key=="EURUSD") return InpMaxSpreadEURPoints;
   if(key=="USDJPY") return InpMaxSpreadUSDJPYPoints;
   if(key=="NEARUSD") return InpMaxSpreadNEARPoints;
   if(key=="BTCUSDT") return InpMaxSpreadBTCPoints;
   if(key=="XAUUSD") return InpMaxSpreadXAUPoints;
   if(key=="ETHUSD") return InpMaxSpreadETHPoints;
   if(key!="") return (LooksLikeCryptoSymbol(key)?InpMaxSpreadOtherCryptoPoints:InpMaxSpreadPoints);
   return 0;
}

// Cross-asset technical ranking. v1.33 can submit ranked cross-symbol candidates through a
// separate symbol-scoped execution path with strict portfolio gates. This score is technical
// consensus only and must not be interpreted as validated historical strategy evidence.
bool SymbolLocalLiveConsensus(string sym,int tf,string &dirOut,int &votesOut);

double CrossAssetTechnicalScore(string sym, int tf, string &direction, string &reason, int &barsOut)
{
   direction="NONE"; reason="NO_SIGNAL"; barsOut=iBars(sym,tf);
   int need=MathMax(InpTrendEMA,InpFibLookback)+InpDonchianPeriod+InpForwardHorizonBars+20;
   if(barsOut<need) { reason="INSUFFICIENT_HISTORY"; return -1.0; }
   // Cross-symbol ensemble: 16 model-family proxies, evaluated on CLOSED candles for the
   // candidate symbol/timeframe. They are explicitly separated from the chart-local live
   // model evidence and must still pass the independent directional history + holdout gates.
   double c=iClose(sym,tf,1), prev=iClose(sym,tf,2), c4=iClose(sym,tf,4);
   double o=iOpen(sym,tf,1), h=iHigh(sym,tf,1), l=iLow(sym,tf,1);
   double ef=iMA(sym,tf,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double es=iMA(sym,tf,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double et=iMA(sym,tf,InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double rsi=iRSI(sym,tf,InpRSIPeriod,PRICE_CLOSE,1);
   double rsi2=iRSI(sym,tf,InpRSIPeriod,PRICE_CLOSE,2);
   double adx=iADX(sym,tf,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
   double atr=iATR(sym,tf,InpATRPeriod,1);
   if(c<=0 || prev<=0 || c4<=0 || ef<=0 || es<=0 || et<=0 || atr<=0 || rsi<0 || rsi2<0 || adx<0)
   { reason="INVALID_INDICATOR_DATA"; return -1.0; }

   int buy=0,sell=0;
   double momentum=(c-c4)/atr;
   double fastGap=(ef-es)/atr;
   double candleBody=(c-o)/atr;
   double priorHigh=-1.0e100,priorLow=1.0e100;
   for(int k=2;k<=InpDonchianPeriod+1;k++)
   {
      double kh=iHigh(sym,tf,k), kl=iLow(sym,tf,k);
      if(kh>priorHigh) priorHigh=kh;
      if(kl<priorLow) priorLow=kl;
   }
   // 1 TREND
   if(c>et && ef>es) buy++; else if(c<et && ef<es) sell++;
   // 2 MOMENTUM
   if(momentum>=InpMomentumATRThreshold) buy++; else if(momentum<=-InpMomentumATRThreshold) sell++;
   // 3 DONCHIAN breakout
   if(c>priorHigh+InpBreakoutBufferATR*atr) buy++; else if(c<priorLow-InpBreakoutBufferATR*atr) sell++;
   // 4 MEANREV (range-aware RSI extremes)
   if(adx<=InpMeanRevADXMax && rsi<=InpMeanRevRSIBuy) buy++; else if(adx<=InpMeanRevADXMax && rsi>=InpMeanRevRSISell) sell++;
   // 5 STRICT_RANGE (edge location with range regime)
   double rangeHigh=-1.0e100,rangeLow=1.0e100;
   for(int r=2;r<2+InpStrictRangeLookback;r++) { rangeHigh=MathMax(rangeHigh,iHigh(sym,tf,r)); rangeLow=MathMin(rangeLow,iLow(sym,tf,r)); }
   if(adx<=InpStrictRangeADXMax && c<=rangeLow+InpStrictRangeEdgeATR*atr && rsi<=InpStrictRangeBuyRSI) buy++;
   else if(adx<=InpStrictRangeADXMax && c>=rangeHigh-InpStrictRangeEdgeATR*atr && rsi>=InpStrictRangeSellRSI) sell++;
   // 6 ATR volatility breakout
   if(MathAbs(c-prev)>=0.65*atr && candleBody>0.20) buy++; else if(MathAbs(c-prev)>=0.65*atr && candleBody< -0.20) sell++;
   // 7 SESSION_BIAS proxy: use candle direction only when trend is aligned
   if(c>o && c>et) buy++; else if(c<o && c<et) sell++;
   // 8 RSI_DIVERGENCE proxy: price/RSI reversal on adjacent closed bars
   if(c<prev && rsi>rsi2 && rsi<45.0) buy++; else if(c>prev && rsi<rsi2 && rsi>55.0) sell++;
   // 9 HTF_TREND_CONFIRM using the next higher timeframe where supported
   int htf=(tf==PERIOD_M15?PERIOD_H1:(tf==PERIOD_M30?PERIOD_H4:(tf==PERIOD_H1?PERIOD_H4:PERIOD_D1)));
   int htfContainingShift=iBarShift(sym,htf,iTime(sym,tf,1),false);
   int htfClosedShift=(htfContainingShift>=0?htfContainingShift+1:-1);
   double htfClose=(htfClosedShift>=1?iClose(sym,htf,htfClosedShift):0.0);
   double htfEma=(htfClosedShift>=1?iMA(sym,htf,InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,htfClosedShift):0.0);
   if(htfClose>0 && htfEma>0 && c>et && htfClose>htfEma) buy++;
   else if(htfClose>0 && htfEma>0 && c<et && htfClose<htfEma) sell++;
   // 10 VWAP_DEVIATION proxy: typical-price mean over a bounded recent window
   double mean=0.0; int meanN=MathMin(InpVWAPLookback,barsOut-2);
   for(int v=1;v<=meanN;v++) mean+=(iHigh(sym,tf,v)+iLow(sym,tf,v)+iClose(sym,tf,v))/3.0;
   if(meanN>0) mean/=meanN;
   if(mean>0 && c<mean-InpVWAPDeviationATR*atr) buy++; else if(mean>0 && c>mean+InpVWAPDeviationATR*atr) sell++;
   // 11 BREAK_RETEST proxy
   double prevHigh=iHigh(sym,tf,2), prevLow=iLow(sym,tf,2);
   if(c>prevHigh && l<=prevHigh+InpRetestToleranceATR*atr && c>o) buy++;
   else if(c<prevLow && h>=prevLow-InpRetestToleranceATR*atr && c<o) sell++;
   // 12 FIBONACCI_PULLBACK proxy using recent swing midpoint zone
   double swingH=-1.0e100,swingL=1.0e100;
   for(int f=2;f<2+InpFibLookback;f++) { swingH=MathMax(swingH,iHigh(sym,tf,f)); swingL=MathMin(swingL,iLow(sym,tf,f)); }
   double swingRange=swingH-swingL;
   if(swingRange>0 && ef>es && c>=swingL+0.382*swingRange && c<=swingL+0.618*swingRange && c>o) buy++;
   else if(swingRange>0 && ef<es && c<=swingH-0.382*swingRange && c>=swingH-0.618*swingRange && c<o) sell++;
   // 13 VOLATILITY_SQUEEZE proxy: compressed recent range then directional expansion
   double atrOld=iATR(sym,tf,InpATRPeriod,5);
   if(atrOld>0 && atr<InpSqueezeWidthFactor*atrOld && c>o && c>ef) buy++;
   else if(atrOld>0 && atr<InpSqueezeWidthFactor*atrOld && c<o && c<ef) sell++;
   // 14 LINEAR_REGRESSION slope proxy
   double oldClose=iClose(sym,tf,1+InpRegressionLookback);
   double slope=(oldClose>0?(c-oldClose)/atr/InpRegressionLookback:0.0);
   if(slope>=InpRegressionSlopeATR) buy++; else if(slope<=-InpRegressionSlopeATR) sell++;
   // Cross-asset proxy 15 MACD_CONFIRM: main/signal line alignment on the closed candle.
   double macdMain=iMACD(sym,tf,12,26,9,PRICE_CLOSE,MODE_MAIN,1);
   double macdSignal=iMACD(sym,tf,12,26,9,PRICE_CLOSE,MODE_SIGNAL,1);
   if(macdMain>macdSignal && macdMain>0.0) buy++; else if(macdMain<macdSignal && macdMain<0.0) sell++;
   // 16 BOLLINGER_EXPANSION proxy: close outside the prior bands with directional candle.
   double upper=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_UPPER,2);
   double lower=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_LOWER,2);
   if(upper>0.0 && c>upper && c>o) buy++; else if(lower>0.0 && c<lower && c<o) sell++;

   int directional=buy+sell, winning=MathMax(buy,sell);
   Print("CROSS-ASSET 16-MODEL ENSEMBLE | symbol=",sym," timeframe=",tf,
         " modelFamilies=16 buyVotes=",buy," sellVotes=",sell," directionalVotes=",directional,
         " adx=",DoubleToString(adx,1)," momentumATR=",DoubleToString(momentum,3),
         " rsi=",DoubleToString(rsi,1)," fastSlowGapATR=",DoubleToString(fastGap,3),
         " | cross-symbol model-family proxies; directional history and holdout remain mandatory.");
   if(adx<10.0 || directional<5 || buy==sell || winning<5)
   { reason="SIXTEEN_MODEL_ENSEMBLE_NO_CLEAR_CONSENSUS"; return 0.0; }
   direction=(buy>sell?"BUY":"SELL");
   double agreement=(double)winning/(double)MathMax(1,directional);
   double trendStrength=MathMin(1.0,MathAbs(fastGap));
   double momentumStrength=MathMin(1.0,MathAbs(momentum));
   double adxStrength=MathMin(1.0,adx/40.0);
   double coverage=(double)directional/(double)CROSS_ASSET_MODEL_COUNT;
   double score=100.0*(0.55*agreement+0.20*trendStrength+0.15*momentumStrength+0.10*adxStrength)*MathMin(1.0,0.65+0.35*coverage);
   reason="SIXTEEN_MODEL_FAMILY_PROXY_CONSENSUS_NOT_EVIDENCE_VALIDATED";
   return score;
}

// Per-symbol directional historical bar study using the same 16 model-family proxy votes
// as the live cross-asset candidate selector. Uses non-overlapping closed-bar samples,
// fixed 1.5 ATR normalization and a current-spread cost proxy. It remains a HISTORICAL_PROXY:
// it does not simulate stop/target intrabar paths, slippage or broker fills.
bool CrossAssetHistoricalEvidence(string sym,int tf,string candidateDirection,int &samplesOut,double &winRateOut,double &avgROut,string &reasonOut,
                                  int &holdoutSamplesOut,double &holdoutWinRateOut,double &holdoutAvgROut)
{
   samplesOut=0; winRateOut=0.0; avgROut=-999.0; reasonOut="NOT_EVALUATED";
   holdoutSamplesOut=0; holdoutWinRateOut=0.0; holdoutAvgROut=-999.0;
   int bars=iBars(sym,tf);
   int horizon=MathMax(1,InpForwardHorizonBars);
   int minShift=horizon+2;
   int modelLookback=MathMax(InpTrendEMA,MathMax(InpDonchianPeriod+2,MathMax(InpStrictRangeLookback+2,MathMax(InpFibLookback+2,MathMax(InpVWAPLookback+1,InpRegressionLookback+2)))));
   int maxShift=MathMin(MathMax(0,InpEvidenceLookbackBars),bars-horizon-modelLookback-2);
   if(maxShift<minShift+InpCrossAssetMinHistorySamples+InpCrossAssetMinHoldoutSamples)
   { reasonOut="INSUFFICIENT_BARS_FOR_TRAIN_AND_HOLDOUT"; return false; }
   int targetDir=(candidateDirection=="BUY"?1:(candidateDirection=="SELL"?-1:0));
   if(targetDir==0) { reasonOut="NO_CANDIDATE_DIRECTION"; return false; }
   double point=MarketInfo(sym,MODE_POINT);
   int spreadPoints=(int)MarketInfo(sym,MODE_SPREAD);
   double spreadCost=(point>0.0 && spreadPoints>=0 ? point*spreadPoints : 0.0);
   // Shifts <= cutoff are the most recent 30% of the eligible history and form a
   // chronological holdout. They are not used to tune the thresholds in this function.
   int holdoutCutoff=minShift+(int)MathFloor((double)(maxShift-minShift)*0.30);
   double sumR=0.0, holdoutSumR=0.0; int wins=0, holdoutWins=0; int trainSamples=0; int lastAcceptedShift=-1;
   for(int shift=maxShift;shift>=minShift;shift--)
   {
      if(lastAcceptedShift>=0 && (lastAcceptedShift-shift)<horizon) continue;
      double c=iClose(sym,tf,shift), c4=iClose(sym,tf,shift+3);
      double ef=iMA(sym,tf,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double es=iMA(sym,tf,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double et=iMA(sym,tf,InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double rsi=iRSI(sym,tf,InpRSIPeriod,PRICE_CLOSE,shift);
      double adx=iADX(sym,tf,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,shift);
      double atr=iATR(sym,tf,InpATRPeriod,shift);
      if(c<=0.0 || c4<=0.0 || ef<=0.0 || es<=0.0 || et<=0.0 || atr<=0.0 || rsi<0.0 || adx<0.0) continue;
      if(adx<10.0) continue;
      // Apply the same 16 model-family proxies to each historical candidate bar;
      // otherwise the live direction and its training/holdout evidence would use
      // different signal definitions and the comparison would be internally inconsistent.
      double prev=iClose(sym,tf,shift+1), o=iOpen(sym,tf,shift), hi=iHigh(sym,tf,shift), lo=iLow(sym,tf,shift);
      double rsi2=iRSI(sym,tf,InpRSIPeriod,PRICE_CLOSE,shift+1);
      if(prev<=0.0 || o<=0.0 || rsi2<0.0 || hi<=0.0 || lo<=0.0) continue;
      int buy=0,sell=0;
      double momentum=(c-c4)/atr;
      double candleBody=(c-o)/atr;
      double priorHigh=-1.0e100,priorLow=1.0e100;
      for(int k=shift+1;k<=shift+InpDonchianPeriod+1;k++)
      {
         double kh=iHigh(sym,tf,k), kl=iLow(sym,tf,k);
         if(kh>priorHigh) priorHigh=kh;
         if(kl<priorLow) priorLow=kl;
      }
      // 1 TREND
      if(c>et && ef>es) buy++; else if(c<et && ef<es) sell++;
      // 2 MOMENTUM
      if(momentum>=InpMomentumATRThreshold) buy++; else if(momentum<=-InpMomentumATRThreshold) sell++;
      // 3 DONCHIAN
      if(c>priorHigh+InpBreakoutBufferATR*atr) buy++; else if(c<priorLow-InpBreakoutBufferATR*atr) sell++;
      // 4 MEANREV
      if(adx<=InpMeanRevADXMax && rsi<=InpMeanRevRSIBuy) buy++; else if(adx<=InpMeanRevADXMax && rsi>=InpMeanRevRSISell) sell++;
      // 5 STRICT_RANGE
      double rangeHigh=-1.0e100,rangeLow=1.0e100;
      for(int r=shift+1;r<shift+1+InpStrictRangeLookback;r++) { rangeHigh=MathMax(rangeHigh,iHigh(sym,tf,r)); rangeLow=MathMin(rangeLow,iLow(sym,tf,r)); }
      if(adx<=InpStrictRangeADXMax && c<=rangeLow+InpStrictRangeEdgeATR*atr && rsi<=InpStrictRangeBuyRSI) buy++;
      else if(adx<=InpStrictRangeADXMax && c>=rangeHigh-InpStrictRangeEdgeATR*atr && rsi>=InpStrictRangeSellRSI) sell++;
      // 6 ATR volatility breakout
      if(MathAbs(c-prev)>=0.65*atr && candleBody>0.20) buy++; else if(MathAbs(c-prev)>=0.65*atr && candleBody< -0.20) sell++;
      // 7 SESSION_BIAS proxy
      if(c>o && c>et) buy++; else if(c<o && c<et) sell++;
      // 8 RSI_DIVERGENCE proxy
      if(c<prev && rsi>rsi2 && rsi<45.0) buy++; else if(c>prev && rsi<rsi2 && rsi>55.0) sell++;
      // 9 HTF_TREND_CONFIRM, aligned to the historical candle timestamp to avoid look-ahead.
      int htf=(tf==PERIOD_M15?PERIOD_H1:(tf==PERIOD_M30?PERIOD_H4:(tf==PERIOD_H1?PERIOD_H4:PERIOD_D1)));
      // The bar containing the candidate timestamp may still be forming at that timestamp.
      // Use the immediately preceding HTF candle to keep the historical study look-ahead-free.
      int htfContainingShift=iBarShift(sym,htf,iTime(sym,tf,shift),false);
      int htfShift=(htfContainingShift>=0?htfContainingShift+1:-1);
      double htfClose=(htfShift>=1?iClose(sym,htf,htfShift):0.0);
      double htfEma=(htfShift>=1?iMA(sym,htf,InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,htfShift):0.0);
      if(htfClose>0.0 && htfEma>0.0 && c>et && htfClose>htfEma) buy++;
      else if(htfClose>0.0 && htfEma>0.0 && c<et && htfClose<htfEma) sell++;
      // 10 VWAP_DEVIATION proxy
      double mean=0.0; int meanN=MathMin(InpVWAPLookback,bars-shift-1);
      for(int v=shift;v<shift+meanN;v++) mean+=(iHigh(sym,tf,v)+iLow(sym,tf,v)+iClose(sym,tf,v))/3.0;
      if(meanN>0) mean/=meanN;
      if(mean>0.0 && c<mean-InpVWAPDeviationATR*atr) buy++; else if(mean>0.0 && c>mean+InpVWAPDeviationATR*atr) sell++;
      // 11 BREAK_RETEST
      double prevHigh=iHigh(sym,tf,shift+1), prevLow=iLow(sym,tf,shift+1);
      if(c>prevHigh && lo<=prevHigh+InpRetestToleranceATR*atr && c>o) buy++;
      else if(c<prevLow && hi>=prevLow-InpRetestToleranceATR*atr && c<o) sell++;
      // 12 FIBONACCI_PULLBACK
      double swingH=-1.0e100,swingL=1.0e100;
      for(int f=shift+1;f<shift+1+InpFibLookback;f++) { swingH=MathMax(swingH,iHigh(sym,tf,f)); swingL=MathMin(swingL,iLow(sym,tf,f)); }
      double swingRange=swingH-swingL;
      if(swingRange>0.0 && ef>es && c>=swingL+0.382*swingRange && c<=swingL+0.618*swingRange && c>o) buy++;
      else if(swingRange>0.0 && ef<es && c<=swingH-0.382*swingRange && c>=swingH-0.618*swingRange && c<o) sell++;
      // 13 VOLATILITY_SQUEEZE
      double atrOld=iATR(sym,tf,InpATRPeriod,shift+4);
      if(atrOld>0.0 && atr<InpSqueezeWidthFactor*atrOld && c>o && c>ef) buy++;
      else if(atrOld>0.0 && atr<InpSqueezeWidthFactor*atrOld && c<o && c<ef) sell++;
      // 14 LINEAR_REGRESSION
      double oldClose=iClose(sym,tf,shift+1+InpRegressionLookback);
      double slope=(oldClose>0.0?(c-oldClose)/atr/InpRegressionLookback:0.0);
      if(slope>=InpRegressionSlopeATR) buy++; else if(slope<=-InpRegressionSlopeATR) sell++;
      // Cross-asset proxy 15 MACD_CONFIRM, evaluated at the historical candle shift.
      double macdMain=iMACD(sym,tf,12,26,9,PRICE_CLOSE,MODE_MAIN,shift);
      double macdSignal=iMACD(sym,tf,12,26,9,PRICE_CLOSE,MODE_SIGNAL,shift);
      if(macdMain>macdSignal && macdMain>0.0) buy++; else if(macdMain<macdSignal && macdMain<0.0) sell++;
      // 16 BOLLINGER_EXPANSION proxy, using bands from the bar preceding the candidate.
      double upper=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_UPPER,shift+1);
      double lower=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_LOWER,shift+1);
      if(upper>0.0 && c>upper && c>o) buy++; else if(lower>0.0 && c<lower && c<o) sell++;
      int directionalVotes=buy+sell;
      if(adx<10.0 || directionalVotes<5 || buy==sell || MathMax(buy,sell)<5) continue;
      int historicalDir=(buy>sell?1:-1);
      if(historicalDir!=targetDir) continue;
      double futureClose=iClose(sym,tf,shift-horizon);
      if(futureClose<=0.0) continue;
      double riskUnit=atr*1.5;
      if(riskUnit<=0.0) continue;
      double netR=((futureClose-c)*targetDir-spreadCost)/riskUnit;
      if(shift<=holdoutCutoff)
      {
         holdoutSamplesOut++;
         holdoutSumR+=netR;
         if(netR>0.0) holdoutWins++;
      }
      else
      {
         trainSamples++;
         sumR+=netR;
         if(netR>0.0) wins++;
      }
      lastAcceptedShift=shift;
   }
   samplesOut=trainSamples;
   if(samplesOut<=0) { reasonOut="NO_MATCHING_TRAINING_DIRECTIONAL_SAMPLES"; return false; }
   winRateOut=(double)wins/(double)samplesOut;
   avgROut=sumR/(double)samplesOut;
   if(holdoutSamplesOut>0)
   {
      holdoutWinRateOut=(double)holdoutWins/(double)holdoutSamplesOut;
      holdoutAvgROut=holdoutSumR/(double)holdoutSamplesOut;
   }
   bool trainNPass=(samplesOut>=InpCrossAssetMinHistorySamples);
   bool trainWRPass=(winRateOut>=InpCrossAssetMinHistoryWinRate);
   bool trainRPass=(avgROut>InpCrossAssetMinHistoryAvgR);
   bool holdoutNPass=(holdoutSamplesOut>=InpCrossAssetMinHoldoutSamples);
   bool holdoutWRPass=(holdoutWinRateOut>=InpCrossAssetMinHoldoutWinRate);
   bool holdoutRPass=(holdoutAvgROut>InpCrossAssetMinHoldoutAvgR);
   bool trainPass=(trainNPass && trainWRPass && trainRPass);
   bool holdoutPass=(holdoutNPass && holdoutWRPass && holdoutRPass);
   bool pass=(trainPass && holdoutPass);
   reasonOut="trainN="+IntegerToString(samplesOut)+"/"+IntegerToString(InpCrossAssetMinHistorySamples)+":"+(trainNPass?"PASS":"FAIL")+
      ",trainWR="+DoubleToString(winRateOut,3)+"/"+DoubleToString(InpCrossAssetMinHistoryWinRate,3)+":"+(trainWRPass?"PASS":"FAIL")+
      ",trainAvgR="+DoubleToString(avgROut,3)+"/"+DoubleToString(InpCrossAssetMinHistoryAvgR,3)+":"+(trainRPass?"PASS":"FAIL")+
      ",holdoutN="+IntegerToString(holdoutSamplesOut)+"/"+IntegerToString(InpCrossAssetMinHoldoutSamples)+":"+(holdoutNPass?"PASS":"FAIL")+
      ",holdoutWR="+DoubleToString(holdoutWinRateOut,3)+"/"+DoubleToString(InpCrossAssetMinHoldoutWinRate,3)+":"+(holdoutWRPass?"PASS":"FAIL")+
      ",holdoutAvgR="+DoubleToString(holdoutAvgROut,3)+"/"+DoubleToString(InpCrossAssetMinHoldoutAvgR,3)+":"+(holdoutRPass?"PASS":"FAIL")+
      ",evidenceType=HISTORICAL_BAR_PROXY_NOT_REAL_TRADES";
   Print("CROSS-ASSET EVIDENCE GATE AUDIT | symbol=",sym," direction=",candidateDirection," ",reasonOut," result=",(pass?"PASS":"REJECT"));
   return pass;
}

string PreferredSymbolForAsset(string key,int tf,int requiredBars);

double CrossAssetOpportunityPriority(double technicalScore,double winRate,double avgR,double holdoutWinRate,double holdoutAvgR)
{
   // Technical consensus leads; independent train/holdout quality adjusts the ordering.
   // Clamp historical proxies so tiny samples/extreme estimates cannot dominate ranking.
   double trainR=MathMax(-0.50,MathMin(0.50,avgR));
   double holdR=MathMax(-0.50,MathMin(0.50,holdoutAvgR));
   return technicalScore + 8.0*(winRate-0.50) + 8.0*trainR + 5.0*(holdoutWinRate-0.50) + 8.0*holdR;
}

void LogCrossAssetRanking()
{
   if(!InpCrossAssetRankingEnabled || !InpMarketWatchScannerEnabled) return;
   int total=SymbolsTotal(true), tf=InpCrossAssetTimeframe;
   int count=0;
   // Reset the global work arrays before each scan; all indexed reads are now
   // backed by static-storage arrays, avoiding local-array uninitialized warnings.
   for(int initIndex=0;initIndex<100;initIndex++)
   {
      g_crossAssetRankNames[initIndex]="";
      g_crossAssetRankScores[initIndex]=-1.0;
      g_crossAssetRankPriority[initIndex]=-1.0;
      g_crossAssetRankDirs[initIndex]="NONE";
      g_crossAssetRankSamples[initIndex]=0;
      g_crossAssetRankWinRates[initIndex]=0.0;
      g_crossAssetRankAvgR[initIndex]=-999.0;
      g_crossAssetRankHoldoutSamples[initIndex]=0;
      g_crossAssetRankHoldoutWinRates[initIndex]=0.0;
      g_crossAssetRankHoldoutAvgR[initIndex]=-999.0;
   }
   int need=InpTrendEMA+InpDonchianPeriod+InpForwardHorizonBars+20;
   for(int i=0;i<total;i++)
   {
      string sym=SymbolName(i,true);
      if(sym=="" || !SymbolIsInConfiguredAllowlist(sym)) continue;
      string key=CanonicalAssetKey(sym);
      if(key=="" || sym!=PreferredSymbolForAsset(key,tf,need)) continue; // one broker symbol per canonical asset
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
      datetime qt=(datetime)MarketInfo(sym,MODE_TIME); int age=(qt>0?(int)(TimeCurrent()-qt):999999);
      int spr=(int)MarketInfo(sym,MODE_SPREAD), bars=iBars(sym,tf); string dir,why; int b;
      int ceiling=CrossAssetSpreadCeilingFor(sym);
      bool basic=(bid>0 && ask>=bid && age>=0 && age<=120 && point>0 && MarketInfo(sym,MODE_TRADEALLOWED)!=0 && spr>=0 && spr<=ceiling);
      double score=-1.0; int histN=0; double histWin=0.0,histAvgR=-999.0; string histReason="NOT_EVALUATED";
      int holdoutN=0; double holdoutWin=0.0,holdoutAvgR=-999.0;
      bool histPass=false;
      string localDir="NONE"; int localVotes=0;
      bool localLivePass=false;
      if(basic)
      {
         // Run the 16 LOCAL model families for each symbol in the scanner, not just the chart symbol.
         localLivePass=SymbolLocalLiveConsensus(sym,tf,localDir,localVotes);
         score=CrossAssetTechnicalScore(sym,tf,dir,why,b);
         bool localDirectionAligned=(localLivePass && localDir==dir);
         if(score>0.0 && localDirectionAligned)
            histPass=CrossAssetHistoricalEvidence(sym,tf,dir,histN,histWin,histAvgR,histReason,holdoutN,holdoutWin,holdoutAvgR);
         else if(score>0.0)
            histReason="LOCAL_16_MODEL_SYMBOL_SIGNAL_MISMATCH_OR_NO_CONSENSUS";
         Print("LOCAL MODEL PER-SYMBOL SCAN | symbol=",sym," timeframe=",tf,
            " localDirection=",localDir," localVotes=",localVotes," requiredVotes=",RequiredModelVotes(),
            " crossAssetDirection=",dir," localConsensus=",(localLivePass?"PASS":"REJECT"),
            " directionAligned=",(localDirectionAligned?"true":"false"),
            " decision=",(localDirectionAligned?"CONTINUE_TO_TRAIN_HOLDOUT_GATE":"REJECT_CANDIDATE"));
      }
      else { dir="NONE"; why=(age<0 || age>120 ? "STALE_QUOTE" : (spr>ceiling ? "SPREAD_GATE" : "QUOTE_OR_TRADE_PERMISSION_GATE")); }
      string oppositeDir=(dir=="BUY"?"SELL":(dir=="SELL"?"BUY":"NONE"));
      int oppN=0,oppHoldoutN=0; double oppWin=0.0,oppAvgR=-999.0,oppHoldoutWin=0.0,oppHoldoutAvgR=-999.0; string oppReason="NOT_EVALUATED";
      bool oppPass=false;
      if(basic && oppositeDir!="NONE")
         oppPass=CrossAssetHistoricalEvidence(sym,tf,oppositeDir,oppN,oppWin,oppAvgR,oppReason,oppHoldoutN,oppHoldoutWin,oppHoldoutAvgR);
      Print("MULTI-ASSET BIDIRECTIONAL FEASIBILITY | symbol=",sym," technicalConsensusDirection=",dir,
            " BUY_or_SELL_currentSignal=",dir," oppositeDirection=",oppositeDir,
            " oppositeTrainN=",oppN," oppositeWinRate=",DoubleToString(oppWin,3)," oppositeAvgRProxy=",DoubleToString(oppAvgR,3),
            " oppositeHoldoutN=",oppHoldoutN," oppositeHoldoutWinRate=",DoubleToString(oppHoldoutWin,3),
            " oppositeHoldoutAvgRProxy=",DoubleToString(oppHoldoutAvgR,3)," oppositeEvidenceQualified=",(oppPass?"true":"false"),
            " oppositeReason=",oppReason," | opposite historical pass alone does not override missing live directional consensus.");
      Print("MULTI-ASSET EVALUATION | symbol=",sym," timeframe=",tf," direction=",dir,
            " localModelDirection=",localDir," localModelVotes=",localVotes," localModelConsensus=",(localLivePass?"PASS":"REJECT"),
            " technicalRankScore=",DoubleToString(score,2)," historySamples=",histN,
            " historyWinRate=",DoubleToString(histWin,3)," historyAvgRProxy=",DoubleToString(histAvgR,3),
            " holdoutSamples=",holdoutN," holdoutWinRate=",DoubleToString(holdoutWin,3)," holdoutAvgRProxy=",DoubleToString(holdoutAvgR,3),
            " holdoutRequiredSamples=",InpCrossAssetMinHoldoutSamples," historyQualified=",(histPass?"true":"false")," historyReason=",histReason,
            " bars=",bars," requiredBars=",need,
            " quoteAgeSeconds=",age," spreadPoints=",spr," spreadCeiling=",ceiling,
            " decision=",(score>0 && histPass?"HISTORY_QUALIFIED_RANKED_CANDIDATE":(score>0?"TECHNICAL_ONLY_HISTORY_REJECTED":"REJECT_OR_NO_SIGNAL"))," reason=",why,
            " evidenceType=COST_ADJUSTED_ATR_NORMALIZED_HISTORICAL_PROXY_NOT_LIVE_FORWARD_RESULTS",
            " execution=RANKED_ONLY_UNTIL_EVIDENCE_AND_ORDER_GATES_PASS");
      double priority=(score>0 && histPass?CrossAssetOpportunityPriority(score,histWin,histAvgR,holdoutWin,holdoutAvgR):-1.0);
      if(score>0 && histPass && count<100)
      {
         int pos=count;
         while(pos>0 && g_crossAssetRankPriority[pos-1]<priority)
         {
            g_crossAssetRankScores[pos]=g_crossAssetRankScores[pos-1];
            g_crossAssetRankPriority[pos]=g_crossAssetRankPriority[pos-1];
            g_crossAssetRankNames[pos]=g_crossAssetRankNames[pos-1];
            g_crossAssetRankDirs[pos]=g_crossAssetRankDirs[pos-1];
            g_crossAssetRankSamples[pos]=g_crossAssetRankSamples[pos-1];
            g_crossAssetRankWinRates[pos]=g_crossAssetRankWinRates[pos-1];
            g_crossAssetRankAvgR[pos]=g_crossAssetRankAvgR[pos-1];
            g_crossAssetRankHoldoutSamples[pos]=g_crossAssetRankHoldoutSamples[pos-1];
            g_crossAssetRankHoldoutWinRates[pos]=g_crossAssetRankHoldoutWinRates[pos-1];
            g_crossAssetRankHoldoutAvgR[pos]=g_crossAssetRankHoldoutAvgR[pos-1];
            pos--;
         }
         g_crossAssetRankScores[pos]=score; g_crossAssetRankPriority[pos]=priority; g_crossAssetRankNames[pos]=sym; g_crossAssetRankDirs[pos]=dir;
         g_crossAssetRankSamples[pos]=histN; g_crossAssetRankWinRates[pos]=histWin; g_crossAssetRankAvgR[pos]=histAvgR;
         g_crossAssetRankHoldoutSamples[pos]=holdoutN; g_crossAssetRankHoldoutWinRates[pos]=holdoutWin; g_crossAssetRankHoldoutAvgR[pos]=holdoutAvgR; count++;
      }
   }
   string top=""; int n=MathMin(MathMin(InpCrossAssetTopLogCount,7),count);
   for(int j=0;j<n;j++) { if(top!="") top+=";"; top+=g_crossAssetRankNames[j]+":"+g_crossAssetRankDirs[j]+":T"+DoubleToString(g_crossAssetRankScores[j],1)+"/P"+DoubleToString(g_crossAssetRankPriority[j],1)+"/n"+IntegerToString(g_crossAssetRankSamples[j])+"/R"+DoubleToString(g_crossAssetRankAvgR[j],2)+"/ho"+IntegerToString(g_crossAssetRankHoldoutSamples[j])+"/hoR"+DoubleToString(g_crossAssetRankHoldoutAvgR[j],2); }
   if(top!="" && top!=g_lastCrossAssetRankingSignature)
      Print("MULTI-ASSET RANKING SUMMARY | timeframe=",tf," rankedCandidates=",count," top=",top,
            " | candidates pass directional historical proxy thresholds; proxy is not a true forward test and every order is revalidated by symbol-specific execution/risk gates");
   g_lastCrossAssetRankingSignature=top;
}

// Market Watch discovery and ranking are restricted to one selected broker symbol per canonical asset.
// Ranked candidates may be executed by the guarded cross-asset order path; discovery alone never authorizes an order.
bool LooksLikeCryptoSymbol(string symbolName)
{
   string u=symbolName;
   StringToUpper(u);
   string tokens="|BTC|XBT|ETH|SOL|XRP|DOGE|AVAX|NEAR|ADA|DOT|LINK|LTC|BCH|BNB|TRX|TON|SHIB|ATOM|UNI|ETC|FIL|APT|ARB|OP|SUI|INJ|ICP|XLM|ALGO|HBAR|VET|MATIC|POL|AAVE|EOS|XTZ|FTM|RENDER|FET|TAO|PEPE|WIF|";
   string parts[];
   int n=StringSplit(tokens,'|',parts);
   for(int i=0;i<n;i++)
   {
      if(parts[i]=="") continue;
      // Match the base ticker at the start to avoid false positives such as COPPER matching "OP".
      if(StringFind(u,parts[i])==0) return true;
      if(StringLen(u)>2 && StringSubstr(u,0,2)=="M." && StringFind(u,parts[i],2)==2) return true;
      if(StringLen(u)>1 && StringSubstr(u,0,1)=="#" && StringFind(u,parts[i],1)==1) return true;
   }
   return false;
}

bool SymbolIsInConfiguredAllowlist(string symbolName)
{
   string key=CanonicalAssetKey(symbolName);
   if(key=="") return false;
   string list=InpAllowedSymbols;
   StringToUpper(list);
   StringReplace(list," ","");
   // Canonical keys allow SOLUSD/SOLUSDT, NEARUSD/NEARUSDT, BTCUSD/BTCUSDT and ETHUSD/ETHUSDT aliases.
   string padded=","+list+",";
   if(list=="*" || StringFind(padded,","+key+",")>=0) return true;
   if(key=="SOLUSDT" && (StringFind(padded,",SOLUSD,")>=0 || StringFind(padded,",SOLUSDT,")>=0)) return true;
   if(key=="NEARUSD" && (StringFind(padded,",NEARUSDT,")>=0 || StringFind(padded,",NEARUSD,")>=0)) return true;
   if(key=="BTCUSDT" && (StringFind(padded,",BTCUSD,")>=0 || StringFind(padded,",BTCUSDT,")>=0)) return true;
   if(key=="ETHUSD" && (StringFind(padded,",ETHUSDT,")>=0 || StringFind(padded,",ETHUSD,")>=0)) return true;
   return false;
}

void ScanMarketWatchAssets(bool forceLog)
{
   if(!InpMarketWatchScannerEnabled) return;
   int interval=InpMarketWatchScanIntervalSeconds;
   if(interval<15) interval=15;
   datetime now=TimeLocal();
   if(!forceLog && g_lastMarketWatchScanTime>0 && (now-g_lastMarketWatchScanTime)<interval) return;
   g_lastMarketWatchScanTime=now;

   int total=SymbolsTotal(true);
   int active=0, eligible=0, blocked=0, cryptoFound=0;
   string activeList="";
   string signature="";
   int requiredBars=InpTrendEMA+InpDonchianPeriod+InpForwardHorizonBars+20;
   for(int i=0;i<total;i++)
   {
      string sym=SymbolName(i,true);
      if(sym=="") continue;
      bool configured=SymbolIsInConfiguredAllowlist(sym);
      if(!configured) continue; // "*" scans all visible instruments; an explicit list remains restrictive.
      string key=CanonicalAssetKey(sym);
      if(key=="" || sym!=PreferredSymbolForAsset(key,InpCrossAssetTimeframe,requiredBars)) continue; // collapse USD/USDT and broker-suffix aliases
      bool crypto=LooksLikeCryptoSymbol(sym);
      if(crypto) cryptoFound++;
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      double point=MarketInfo(sym,MODE_POINT), tickValue=MarketInfo(sym,MODE_TICKVALUE), tickSize=MarketInfo(sym,MODE_TICKSIZE);
      int spread=(int)MarketInfo(sym,MODE_SPREAD);
      int bars=iBars(sym,InpCrossAssetTimeframe);
      datetime quoteTime=(datetime)MarketInfo(sym,MODE_TIME);
      int quoteAge=(quoteTime>0?(int)(TimeCurrent()-quoteTime):999999);
      bool quoteActive=(bid>0.0 && ask>=bid && quoteAge>=0 && quoteAge<=120);
      bool specsValid=(point>0.0 && tickValue>0.0 && tickSize>0.0);
      bool tradeAllowed=(MarketInfo(sym,MODE_TRADEALLOWED)!=0);
      bool enoughBars=(bars>=requiredBars);
      int spreadCeiling=CrossAssetSpreadCeilingFor(sym);
      bool spreadOK=(spreadCeiling>0 && spread>=0 && spread<=spreadCeiling);
      bool scanEligible=(quoteActive && specsValid && tradeAllowed && enoughBars && configured && spreadOK);
      if(quoteActive) active++;
      if(scanEligible) eligible++;
      if((crypto || configured) && !scanEligible) blocked++;
      if((crypto || configured) && (quoteActive || configured))
      {
         string status="BLOCKED";
         if(scanEligible) status="ACTIVE_CONFIGURED_CANDIDATE";
         else if(!quoteActive) status="NO_FRESH_QUOTE";
         else if(!configured) status="DISCOVERED_NOT_CONFIGURED";
         else if(!tradeAllowed) status="SYMBOL_TRADING_DISABLED";
         else if(!enoughBars) status="INSUFFICIENT_HISTORY";
         else if(!specsValid) status="INVALID_TICK_SPECIFICATION";
         else if(!spreadOK) status="SPREAD_OVER_CEILING_OR_UNCONFIGURED";
         Print("ASSET DISCOVERY | symbol=",sym,
               " | class=",(crypto?"CRYPTO_LIKE":"CONFIGURED_ASSET"),
               " | status=",status,
               " | bid=",DoubleToString(bid,(int)MarketInfo(sym,MODE_DIGITS)),
               " ask=",DoubleToString(ask,(int)MarketInfo(sym,MODE_DIGITS)),
               " spreadPoints=",spread," quoteAgeSeconds=",quoteAge,
               " bars=",bars," requiredBars=",requiredBars,
               " spreadCeiling=",spreadCeiling," spreadOK=",(spreadOK?"true":"false"),
               " tradeAllowed=",(tradeAllowed?"true":"false"),
               " tickValue=",DoubleToString(tickValue,6)," tickSize=",DoubleToString(tickSize,6),
               " | execution=",(scanEligible?"eligible only if an EA instance runs on this chart and all live signal/risk gates pass":"not authorized by discovery"));
         if(scanEligible)
         {
            if(activeList!="") activeList+=",";
            activeList+=sym;
         }
      }
      signature+=sym+":"+IntegerToString(spread)+":"+IntegerToString(bars)+":"+(quoteActive?"1":"0")+":"+(configured?"1":"0")+";";
   }
   if(forceLog || signature!=g_lastMarketWatchScanSignature)
      Print("MARKET WATCH SCAN SUMMARY | symbolsVisible=",total," activeQuotes=",active,
            " cryptoLikeDetected=",cryptoFound," configuredEligible=",eligible,
            " cryptoOrConfiguredBlocked=",blocked," | eligibleSymbols=",(activeList!=""?activeList:"none"),
            " | canonicalAssetDeduplication=true | universe=MarketWatch_or_configured_allowlist | autoAttach=false | crossAssetRanking=",(InpCrossAssetRankingEnabled?"enabled":"disabled"),
            " | execution=guarded-cross-asset-path; discovery/ranking alone never authorizes an order.");
   g_lastMarketWatchScanSignature=signature;
   LogCrossAssetRanking();
}

string OneShotTestKey()
{
   return "BiteySOL_TestOnce_v112_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+"_"+Symbol();
}

string EntryAttemptBarKey()
{
   return "BiteyEntryAttemptBar_v1642_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+"_"+Symbol()+"_"+IntegerToString(Period());
}

string EntryAttemptStatusKey()
{
   return "BiteyEntryAttemptStatus_v1642_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+"_"+Symbol()+"_"+IntegerToString(Period());
}

string EntryAttemptStatusName(int status)
{
   if(status==1) return "ATTEMPT_IN_PROGRESS_OR_INTERRUPTED";
   if(status==2) return "ORDER_OPENED";
   if(status==3) return "ORDER_REJECTED_OR_FAILED";
   return "UNKNOWN_OR_NO_PREVIOUS_ATTEMPT";
}

datetime g_lastAdaptiveSLTPModifyTime=0;

int OnInit()
{
   string attemptBarKey=EntryAttemptBarKey();
   string attemptStatusKey=EntryAttemptStatusKey();
   if(GlobalVariableCheck(attemptBarKey)) g_lastEntryAttemptBarTime=(datetime)GlobalVariableGet(attemptBarKey);
   if(GlobalVariableCheck(attemptStatusKey)) g_lastEntryAttemptStatus=(int)GlobalVariableGet(attemptStatusKey);
   if(g_lastEntryAttemptBarTime>0)
      g_lastEntryAttemptResult="PREVIOUS_SESSION_STATUS:"+EntryAttemptStatusName(g_lastEntryAttemptStatus);
   Print("ENTRY ATTEMPT STATE RESTORE | attemptedBar=", (g_lastEntryAttemptBarTime>0?TimeToString(g_lastEntryAttemptBarTime,TIME_DATE|TIME_MINUTES):"none"),
         " status=",EntryAttemptStatusName(g_lastEntryAttemptStatus),
         " | persistence=terminal_global_variables account/magic/symbol/timeframe; full text result is session-local.");
   if(InpStrictRangeLookback<3 || InpStrictRangeLookback>100 || InpStrictRangeADXMax<1 || InpStrictRangeADXMax>60 || InpStrictRangeEdgeATR<0.05 || InpStrictRangeEdgeATR>2.0 || InpStrictRangeEMAGapATR<0.05 || InpStrictRangeEMAGapATR>3.0 || InpStrictRangeBuyRSI<5 || InpStrictRangeBuyRSI>49 || InpStrictRangeSellRSI<51 || InpStrictRangeSellRSI>95) { Print("INVALID STRICT RANGE INPUTS"); return INIT_PARAMETERS_INCORRECT; }
   if(!IsAllowedMultiAssetSymbol())
   {
      Print("SYMBOL GATE | chart symbol is not in configured multi-asset allowlist ",InpAllowedSymbols,". Current chart=",Symbol(),". No trading.");
      return(INIT_FAILED);
   }
   if(InpOperatingCapitalUSD<=0 || InpRiskPerTradeUSD<=0 || InpHardRiskCapUSD<=0 || EffectivePortfolioRiskCapUSD()<=0 || InpMaxOpenTrades<1 || InpMaxOpenTrades>7 || InpMaxPositionsPerAsset!=1 || InpCrossAssetMaxCryptoPositions<1 || InpSbtTelemetryTimeoutMs<250 ||
      InpLossRiskConfirmedUSD<=0 || InpLossRiskPersistentUSD<=0 || InpLossRiskSevereUSD<=0 || InpSeverePortfolioLossTriggerUSD<=0 || InpLossConfirmMinutes<1 || InpPersistentLossMinutes<InpLossConfirmMinutes || InpSevereLossMinutes<InpPersistentLossMinutes || InpProfitActivationThresholdUSD<0 || InpProfitSustainMinutes<1 || InpProfitRiskStepUSD<=0 || InpAdaptiveRiskMaximumUSD<=0 || InpAdaptiveRiskMaximumUSD>25.00 || InpHardRiskCapUSD>25.00 || InpRiskPerTradeUSD>25.00 || InpMaxRiskPerTradeCapitalPct<=0 || InpMaxRiskPerTradeCapitalPct>5.00 ||
      InpATRPeriod<2 || InpForwardHorizonBars<1 || InpEvidenceLookbackBars<30 ||
      InpBreakEvenTriggerATR<=0 || InpBreakEvenLockATR<0 || InpTrailTriggerATR<=0 || InpTrailDistanceATR<=0 || InpTPExtendTriggerATR<=0 || InpTPExtendDistanceATR<=0 || InpAdaptiveSLTPMinNetProfitUSD<0 || InpSLTPMinChangeATR<=0 || InpSLTPModifyCooldownSeconds<1 ||
      InpPullbackMaxGapATR<0 || InpBreakoutBufferATR<0 || InpStopATR<=0 || InpTargetATR<=0 ||
      InpMinModelVotes<1 || InpMinModelVotes>MODEL_COUNT || InpCampaignLossStopUSD<=0 || InpStrictLossThresholdUSD<=0 ||
      InpProfitFlexThresholdUSD<=0 || InpProfitProtectThresholdUSD<=0 ||
      InpProfitFlexThresholdUSD>=InpProfitProtectThresholdUSD)
   {
      Print("BITEY SBT v1.63.3 INIT ERROR: invalid risk or lookback inputs.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   g_lastBarTime=0;
   g_serverLocalOffsetSeconds=(int)(TimeLocal()-TimeCurrent());
   string resetKey=GovernorKey("RESET_TOKEN");
   string startKey=GovernorKey("START");
   string stopKey=GovernorKey("STOP");
   if(!GlobalVariableCheck(resetKey)) GlobalVariableSet(resetKey,(double)InpResetGovernorToken);
   else if((int)GlobalVariableGet(resetKey)!=InpResetGovernorToken)
   {
      GlobalVariableSet(resetKey,(double)InpResetGovernorToken);
      GlobalVariableDel(stopKey);
      GlobalVariableSet(startKey,(double)TimeCurrent());
      GlobalVariableSet(GovernorKey("STATE"),0.0);
      GlobalVariableDel(GovernorKey("LOCK_TIME"));
      GlobalVariableDel(GovernorKey("LOCK_NET"));
      GlobalVariablesFlush();
      Print("RISK GOVERNOR RESET | token changed; new campaign started. This does not close any existing position.");
   }
   if(GlobalVariableCheck(startKey)) g_campaignStartTime=GlobalVariableGet(startKey);
   else { g_campaignStartTime=(double)TimeCurrent(); GlobalVariableSet(startKey,g_campaignStartTime); }
   // Do not restore legacy STOP latches from older versions.
   UpdateRiskGovernor();
   Print("RISK GOVERNOR RESTORE CHECK | state=",GovernorStateName(g_governorState),
         " | start=",TimeToString((datetime)g_campaignStartTime,TIME_DATE|TIME_SECONDS),
         " | legacy stop latch ignored; money-based policy active.");
   if(g_campaignStartTime>(double)TimeCurrent()+60.0)
   {
      double invalidStart=g_campaignStartTime;
      g_campaignStartTime=(double)TimeCurrent();
      GlobalVariableSet(startKey,g_campaignStartTime);
      GlobalVariablesFlush();
      Print("CAMPAIGN CLOCK REPAIR | stored start was in the future: ",TimeToString((datetime)invalidStart,TIME_DATE|TIME_SECONDS),
            " | reset to server time ",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
            " | verify broker/terminal clock before relying on campaign P/L.");
      UpdateRiskGovernor();
   }
   Print("BITEY SBT Multi-Asset Engine v1.73.0 initialized | Symbol=",Symbol(),
         " TF=",Period()," Mode=",(InpMode==OBSERVE_ONLY?"OBSERVE_ONLY":"AUTO_EXECUTION"),
         " OneShotTestMode=",(InpOneShotTestMode?"true":"false"),
         " OneShotSafetyNotice=",(InpOneShotTestMode?"ENABLED_ONE_ORDER_MAY_BE_REAL":"disabled"),
         " TestDirection=",(InpTestOrderDirection==TEST_ORDER_BUY?"BUY":"SELL"),
         " AllowedSymbols=",InpAllowedSymbols," MarketWatchScanner=",(InpMarketWatchScannerEnabled?"enabled":"disabled"),
         " AutoAllowCryptoOnChart=",(InpAutoAllowDetectedCryptoOnChart?"true":"false"),
         " OtherCryptoSpreadCeiling=",InpMaxSpreadOtherCryptoPoints,
         " ScannerExecutionScope=PER_SYMBOL_TRAIN_AND_HOLDOUT_PROXY_AUDIT_ONLY");
   Print("SEVEN-ASSET CAPACITY | campaignNetUSD=",DoubleToString(g_campaignNetUSD,2),
          " activeSlots=",EffectiveMaxOpenTrades(),"/7",
          " slotPolicy=CONFIGURED_CAPACITY_UP_TO_7;PER_POSITION_AND_AGGREGATE_RISK_GOVERNORS_REMAIN_ACTIVE",
          " duplicatePolicy=ONE_POSITION_PER_CANONICAL_ASSET",
          " | capacity is not a requirement to open trades and is not evidence of profitability.");
   Print("PORTFOLIO CONFIG | MaxOpenTrades=",EffectiveMaxOpenTrades(),
         " PortfolioOpenRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),2),
         " PortfolioCapitalCapUSD=",DoubleToString(InpOperatingCapitalUSD,2),
         " PerAssetAllocationUSD=",DoubleToString(InpOperatingCapitalUSD/7.0,2),
         " MaxPositionsPerAsset=",InpMaxPositionsPerAsset,
         " EffectiveCapitalUSD=",DoubleToString(EffectiveOperatingCapitalUSD(),2),
         " RiskRequestCeilingUSD=",DoubleToString(InpRiskPerTradeUSD,2),
         " NeutralRiskBudgetUSD=",DoubleToString(MathMin(InpRiskPerTradeUSD,InpHardRiskCapUSD),2),
         " LegacyPerTradeCapFieldUSD=",DoubleToString(InpHardRiskCapUSD,2));
   Print("ADAPTIVE RISK CONFIG | enabled=",(InpAdaptiveRiskLadderEnabled?"true":"false"),
         " lossLevelsUSD=",DoubleToString(InpLossRiskConfirmedUSD,2),"/",DoubleToString(InpLossRiskPersistentUSD,2),"/",DoubleToString(InpLossRiskSevereUSD,2),
         " severeLossTriggerUSD=",DoubleToString(InpSeverePortfolioLossTriggerUSD,2),
         " lossConfirmMinutes=",InpLossConfirmMinutes," persistentLossMinutes=",InpPersistentLossMinutes," severeLossMinutes=",InpSevereLossMinutes,
         " profitActivationUSD=",DoubleToString(InpProfitActivationThresholdUSD,2)," profitSustainMinutes=",InpProfitSustainMinutes,
         " profitStepUSD=",DoubleToString(InpProfitRiskStepUSD,2)," maxRiskUSD=",DoubleToString(InpAdaptiveRiskMaximumUSD,2)," maxRiskCapitalPct=",DoubleToString(InpMaxRiskPerTradeCapitalPct,2),
         " aggregateRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),2));
   Print("THREE CANDLE SLTP CONFIG | enabled=",(InpAdaptiveSLTPEnabled?"true":"false"),
         " timeframe=",(InpAdaptiveSLTPTimeframe==PERIOD_CURRENT?Period():(int)InpAdaptiveSLTPTimeframe),
         " requiredClosedCandles=3 direction=POSITION_ALIGNED netProfitThresholdUSD=",DoubleToString(InpAdaptiveSLTPMinNetProfitUSD,2));
   Print("GOVERNOR CONFIG | State=",GovernorStateName(g_governorState),
         " CampaignNetUSD=",DoubleToString(g_campaignNetUSD,2),
         " EffectiveDailyLossUSD=",DoubleToString(EffectiveDailyLossLimitUSD(),2),
         " DailyProfitTargetUSD=",DoubleToString(InpDailyProfitTargetUSD,2),
         " MoneyPolicy=USD500_FIXED_STRICT_AT_MINUS50_FLEX_AT_PLUS100_PROTECT_AT_PLUS200",
         " AccountModeInfoOnly=",ReportedAccountMode(),
         " TerminalIsDemo=",(IsDemo()?"true":"false"));
   Print("ACCOUNT AUDIT | Server=",AccountServer()," Company=",AccountCompany(),
         " AccountNumber=",IntegerToString(AccountNumber()),
         " GovernorStart=",TimeToString((datetime)g_campaignStartTime,TIME_DATE|TIME_SECONDS),
         " GovernorStopLatched=false",
         " AccountTypeMismatchBlock=",(InpBlockOnAccountTypeMismatch?"true":"false"),
         " AccountTypeMismatch=",(AccountTypeMismatch()?"true":"false"),
         " AccountTypeMismatchGate=INFORMATIONAL_ONLY",
         " AccountMismatchInformationalOnly=true | DefaultExecution=AUTO_EXECUTION | TelemetryDoesNotGateOrders=true | AdaptiveSLTP=profit_only | Diagnostics=PROCESS/MODEL_EVIDENCE/NO_ENTRY/ORDER_BLOCKED/ORDER_ERROR/ORDER_OPENED/SLTP_MODIFY_AUDIT");
   if(AccountTypeMismatch())
      Print("ACCOUNT TYPE MISMATCH | configured mode=",ReportedAccountMode()," but terminal IsDemo()=",(IsDemo()?"true":"false"),
            " | INFORMATION ONLY: account classification does not block orders in this build.");
   if(InpSbtTelemetryEnabled)
   {
      Print("SBT TELEMETRY CONFIG | SnapshotURL=",InpSbtTelemetryURL);
      if(InpSbtClosedTradeReportsEnabled)
         Print("SBT TELEMETRY CONFIG | ClosedTradeURL=",InpSbtClosedTradeURL);
      Print("SBT TELEMETRY REQUIREMENT | In MT4 open Tools > Options > Expert Advisors, enable Allow WebRequest for listed URL, and add exactly: https://bitey-system-bots-trading.raylerr481.workers.dev");
   }
   if(InpWriteCSV) EnsureCSVHeader();
   g_lastStatusLogTime=0;
   g_lastBarsGateLogged=-1;
   ResetLastError();
   int timerSeconds=InpPositionMonitorSeconds;
   if(timerSeconds<1) timerSeconds=1;
   if(!EventSetTimer(timerSeconds))
      Print("PROCESS TIMER WARNING | EventSetTimer failed | error=",GetLastError()," | tick-driven diagnostics remain active.");
   ScanMarketWatchAssets(true);
   Print("PROCESS TIMER CONFIG | monitorSeconds=",timerSeconds,
         " signalRecheckSeconds=",MathMax(5,InpSignalRecheckSeconds),
         " | position supervision is frequent; model review is periodic; entries are duplicate-protected per bar.");
   Print("PROCESS STARTUP CHECK | connected=",(IsConnected()?"true":"false"),
         " | symbol=",Symbol()," timeframe=",Period()," bars=",Bars,
         " requiredBars=",(InpTrendEMA+InpDonchianPeriod+InpForwardHorizonBars+20),
         " | bid=",DoubleToString(Bid,Digits)," ask=",DoubleToString(Ask,Digits),
         " spreadPoints=",(int)MarketInfo(Symbol(),MODE_SPREAD),
         " | terminalTradeAllowed=",(IsTradeAllowed()?"true":"false"),
         " | accountTradeAllowed=",(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0?"true":"false"),
         " | accountExpertAllowed=",(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)!=0?"true":"false"),
         " | symbolTradeAllowed=",(MarketInfo(Symbol(),MODE_TRADEALLOWED)!=0?"true":"false"),
         " | nextStep=closed-bar evaluation on valid tick; timer recovery allowed only with a recent quote.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("PROCESS SHUTDOWN | reason=",reason," | symbol=",Symbol()," timeframe=",Period(),
         " | lastEvaluatedBar=",(g_lastBarTime>0?TimeToString(g_lastBarTime,TIME_DATE|TIME_MINUTES):"none"));
}

int CrossAssetSpreadCeilingFor(string sym)
{
   string key=CanonicalAssetKey(sym);
   if(key=="SOLUSDT") return InpMaxSpreadSOLPoints;
   if(key=="EURUSD") return InpMaxSpreadEURPoints;
   if(key=="USDJPY") return InpMaxSpreadUSDJPYPoints;
   if(key=="NEARUSD") return InpMaxSpreadNEARPoints;
   if(key=="BTCUSDT") return InpMaxSpreadBTCPoints;
   if(key=="XAUUSD") return InpMaxSpreadXAUPoints;
   if(key=="ETHUSD") return InpMaxSpreadETHPoints;
   if(key!="") return (LooksLikeCryptoSymbol(sym)?InpMaxSpreadOtherCryptoPoints:InpMaxSpreadPoints);
   return 0;
}

// Select exactly one Market Watch symbol for each canonical asset. Prefer a fresh,
// tradable, sufficiently populated symbol within its spread ceiling; then prefer the
// broker's conventional configured spelling and the lower spread ratio.
string PreferredSymbolForAsset(string key,int tf,int requiredBars)
{
   string best="";
   double bestScore=-1.0e20;
   int total=SymbolsTotal(true);
   for(int i=0;i<total;i++)
   {
      string sym=SymbolName(i,true);
      if(sym=="" || CanonicalAssetKey(sym)!=key || !SymbolIsInConfiguredAllowlist(sym)) continue;
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      double point=MarketInfo(sym,MODE_POINT), tickValue=MarketInfo(sym,MODE_TICKVALUE), tickSize=MarketInfo(sym,MODE_TICKSIZE);
      int spread=(int)MarketInfo(sym,MODE_SPREAD);
      datetime qt=(datetime)MarketInfo(sym,MODE_TIME);
      int age=(qt>0?(int)(TimeCurrent()-qt):999999);
      bool fresh=(bid>0.0 && ask>=bid && age>=0 && age<=120);
      bool tradeable=(MarketInfo(sym,MODE_TRADEALLOWED)!=0);
      bool enough=(iBars(sym,tf)>=requiredBars);
      bool specs=(point>0.0 && tickValue>0.0 && tickSize>0.0);
      int ceiling=CrossAssetSpreadCeilingFor(sym);
      bool spreadOK=(ceiling>0 && spread>=0 && spread<=ceiling);
      double score=0.0;
      if(fresh) score+=100000.0; else score-=100000.0;
      if(tradeable) score+=10000.0;
      if(enough) score+=5000.0;
      if(specs) score+=1000.0;
      if(spreadOK) score+=500.0; else score-=500.0;
      if(spreadOK && ceiling>0) score+=100.0*(1.0-(double)spread/(double)ceiling);
      string upper=sym; StringToUpper(upper);
      string preferred=key;
      if(key=="SOLUSDT") preferred="SOLUSDT";
      if(key=="NEARUSD") preferred="NEARUSD";
      if(key=="BTCUSDT") preferred="BTCUSDT";
      if(key=="ETHUSD") preferred="ETHUSD";
      if(upper==preferred) score+=10.0;
      if(score>bestScore) { bestScore=score; best=sym; }
   }
   return best;
}

int CrossAssetOpenCountForSymbol(string sym)
{
   // Enforce the one-position invariant by canonical asset, not literal broker symbol.
   // This prevents aliases such as SOLUSD/SOLUSDT or broker suffixes from opening duplicates.
   string candidateKey=CanonicalAssetKey(sym);
   if(candidateKey=="") return 0;
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(CanonicalAssetKey(OrderSymbol())==candidateKey) n++;
   }
   return n;
}

int CrossAssetCryptoOpenCount()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==InpMagic && (OrderType()==OP_BUY || OrderType()==OP_SELL) && LooksLikeCryptoSymbol(OrderSymbol())) n++;
   }
   return n;
}

bool CrossAssetSameBaseAlreadyOpen(string sym)
{
   string upper=sym; StringToUpper(upper);
   int cut=StringFind(upper,"USD");
   if(cut<1) cut=StringFind(upper,"USDT");
   string base=(cut>0?StringSubstr(upper,0,cut):upper);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      string other=OrderSymbol(); StringToUpper(other);
      int ocut=StringFind(other,"USD");
      if(ocut<1) ocut=StringFind(other,"USDT");
      string obase=(ocut>0?StringSubstr(other,0,ocut):other);
      if(base==obase) return true;
   }
   return false;
}

string CrossAssetAttemptKey(string sym, datetime bar)
{
   string safe=sym; StringReplace(safe,".","_"); StringReplace(safe,"#","X"); StringReplace(safe,"-","_");
   return "BiteyCA36_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+"_"+safe+"_"+IntegerToString((int)bar);
}

double CrossAssetNormalizeLots(string sym,double lots)
{
   double minLot=MarketInfo(sym,MODE_MINLOT), maxLot=MarketInfo(sym,MODE_MAXLOT), step=MarketInfo(sym,MODE_LOTSTEP);
   if(step<=0.0 || minLot<=0.0 || maxLot<minLot) return 0.0;
   if(lots>maxLot) lots=maxLot;
   lots=MathFloor(lots/step+1e-8)*step;
   int lotDigits=2;
   if(step>=1.0) lotDigits=0; else if(step>=0.1) lotDigits=1; else if(step<0.01) lotDigits=3;
   lots=NormalizeDouble(lots,lotDigits);
   if(lots<minLot) return 0.0;
   return lots;
}

double CrossAssetLotsForRisk(string sym,double riskUSD,double stopDistance)
{
   // Evidence-gated minimum-lot adaptation: permit broker minimum lot only when its estimated risk fits the per-position, daily and remaining aggregate risk limits.
   double tickValue=MarketInfo(sym,MODE_TICKVALUE);
   double tickSize=TickSizePriceForSymbol(sym);
   double minLot=MarketInfo(sym,MODE_MINLOT);
   double lotStep=MarketInfo(sym,MODE_LOTSTEP);
   double maxLot=MarketInfo(sym,MODE_MAXLOT);
   double riskPerLot=0.0, minLotRisk=-1.0, rawLots=0.0, lots=0.0, projected=-1.0;
   double effectiveRiskUSD=riskUSD, minLotAllowedRisk=0.0;
   double capital=EffectiveOperatingCapitalUSD();
   double perPositionCap=MathMin(25.0,MathMin(InpHardRiskCapUSD,MathMin(InpAdaptiveRiskMaximumUSD,capital*MathMax(0.01,InpMaxRiskPerTradeCapitalPct)/100.0)));
   double openRiskNow=PortfolioOpenRiskUSD();
   double aggregateHeadroom=(openRiskNow>=0.0?EffectivePortfolioRiskCapUSD()-openRiskNow:0.0);
   double dailyHeadroom=EffectiveDailyLossLimitUSD()+TodayNetProfit();
   minLotAllowedRisk=MathMin(perPositionCap,MathMin(MathMax(0.0,aggregateHeadroom),MathMax(0.0,dailyHeadroom)));
   string rejectReason="";
   if(tickValue<=0.0 || tickSize<=0.0 || riskUSD<=0.0 || stopDistance<=0.0 || minLot<=0.0 || lotStep<=0.0 || maxLot<minLot || capital<=0.0 || openRiskNow<0.0)
      rejectReason="INVALID_SYMBOL_RISK_METADATA_OR_BUDGET";
   else
   {
      double pointSize=MarketInfo(sym,MODE_POINT);
      double spreadPts=MarketInfo(sym,MODE_SPREAD);
      double estimatedEntryCostDistance=(MathMax(0.0,spreadPts)+MathMax(0,InpSlippagePoints))*pointSize;
      riskPerLot=(stopDistance/tickSize)*tickValue+(estimatedEntryCostDistance/tickSize)*tickValue;
      if(riskPerLot<=0.0)
         rejectReason="NONPOSITIVE_RISK_PER_LOT";
      else
      {
         minLotRisk=minLot*riskPerLot;
         rawLots=riskUSD/riskPerLot;
         lots=CrossAssetNormalizeLots(sym,rawLots);
         if(lots<=0.0)
         {
            // Adapt the budget to the minimum tradable lot only after full evidence passes,
            // with normal governor state and without provisional evidence. Hard per-position,
            // daily-loss and remaining aggregate-risk ceilings remain authoritative.
            if(minLotRisk<=minLotAllowedRisk+0.0001 && g_governorState==0 && !g_currentProvisionalEntry)
            {
               effectiveRiskUSD=minLotRisk;
               lots=CrossAssetNormalizeLots(sym,minLot);
               Print("ADAPTIVE MINIMUM LOT AUTHORIZED | symbol=",sym,
                     " baseBudgetUSD=",DoubleToString(riskUSD,4),
                     " adaptedBudgetUSD=",DoubleToString(effectiveRiskUSD,4),
                     " minimumLot=",DoubleToString(minLot,4),
                     " minimumLotRiskUSD=",DoubleToString(minLotRisk,4),
                     " perPositionCapUSD=",DoubleToString(perPositionCap,4),
                     " aggregateHeadroomUSD=",DoubleToString(aggregateHeadroom,4),
                     " dailyHeadroomUSD=",DoubleToString(dailyHeadroom,4),
                     " evidenceAlreadyPassed=true governor=NORMAL provisional=false");
            }
            else if(g_governorState!=0)
               rejectReason="MIN_LOT_FALLBACK_BLOCKED_BY_RISK_GOVERNOR";
            else if(g_currentProvisionalEntry)
               rejectReason="MIN_LOT_FALLBACK_BLOCKED_FOR_PROVISIONAL_EVIDENCE";
            else if(minLotRisk>perPositionCap+0.0001)
               rejectReason="MIN_LOT_RISK_EXCEEDS_PER_POSITION_CAP";
            else if(minLotRisk>aggregateHeadroom+0.0001)
               rejectReason="MIN_LOT_RISK_EXCEEDS_REMAINING_AGGREGATE_HEADROOM";
            else if(minLotRisk>dailyHeadroom+0.0001)
               rejectReason="MIN_LOT_RISK_EXCEEDS_DAILY_LOSS_HEADROOM";
            else
               rejectReason="MIN_LOT_EXCEEDS_AVAILABLE_RISK_BUDGET";
         }
         if(rejectReason=="" && lots<=0.0)
            rejectReason="NORMALIZED_LOT_NOT_TRADABLE";
         if(rejectReason=="" && lots>0.0)
         {
            double projectedCostDistance=(MathMax(0.0,MarketInfo(sym,MODE_SPREAD))+MathMax(0,InpSlippagePoints))*MarketInfo(sym,MODE_POINT);
            projected=EstimateOrderRiskUSD(sym,lots,stopDistance);
            if(projected>=0.0 && tickSize>0.0)
               projected+=lots*(projectedCostDistance/tickSize)*tickValue;
            if(projected<0.0)
               rejectReason="PROJECTED_RISK_UNAVAILABLE";
            else if(projected>effectiveRiskUSD+0.0001)
               rejectReason="PROJECTED_RISK_EXCEEDS_ADAPTED_BUDGET";
            else if(projected>perPositionCap+0.0001)
               rejectReason="PROJECTED_RISK_EXCEEDS_PER_POSITION_CAP";
            else if(openRiskNow+projected>EffectivePortfolioRiskCapUSD()+0.0001)
               rejectReason="PROJECTED_RISK_EXCEEDS_AGGREGATE_CAP";
            else if(projected>dailyHeadroom+0.0001)
               rejectReason="PROJECTED_RISK_EXCEEDS_DAILY_LOSS_HEADROOM";
         }
      }
   }
   if(rejectReason!="")
   {
      Print("CROSS-ASSET LOT RISK DETAIL | symbol=",sym,
            " rejectReason=",rejectReason,
            " riskBudgetUSD=",DoubleToString(effectiveRiskUSD,4),
            " stopDistance=",DoubleToString(stopDistance,(int)MarketInfo(sym,MODE_DIGITS)),
            " tickValue=",DoubleToString(tickValue,8),
            " tickSizePrice=",DoubleToString(tickSize,10),
            " minLot=",DoubleToString(minLot,4),
            " lotStep=",DoubleToString(lotStep,4),
            " maxLot=",DoubleToString(maxLot,4),
            " riskPerLotUSD=",DoubleToString(riskPerLot,4),
            " minLotRiskUSD=",(minLotRisk>=0.0?DoubleToString(minLotRisk,4):"UNAVAILABLE"),
            " rawLots=",DoubleToString(rawLots,6),
            " normalizedLots=",DoubleToString(lots,6),
            " projectedRiskUSD=",(projected>=0.0?DoubleToString(projected,4):"UNAVAILABLE"),
            " governorState=",g_governorState,
            " provisionalEntry=", (g_currentProvisionalEntry?"true":"false"),
            " | no order sent.");
      return 0.0;
   }
   return lots;
}

bool SymbolLocalEnsemblePass(string sym,int tf,string dir);

bool CrossAssetSendRankedOrder(string sym, string dir, double score)
{
   string reason="";
   double auditLots=-1.0, auditRisk=-1.0, auditSL=0.0, auditTP=0.0;
   // Decision layers are intentionally logged separately: technical candidate, historical evidence,
   // and final execution authorization. Cross-asset model scores are proxies, not actual trade results.
   Print("ENTRY AUTHORIZATION AUDIT | stage=REQUEST source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
         " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE technicalScore=",DoubleToString(score,2),
         " lots=NOT_CALCULATED riskUSD=NOT_CALCULATED SL=NOT_CALCULATED TP=NOT_CALCULATED",
         " decision=PENDING reason=LIVE_GATES_NOT_YET_EVALUATED");
   if(!InpCrossAssetAutoExecutionEnabled || !InpAllowTechnicalOnlyCrossAssetExecution) reason="CROSS_ASSET_EXECUTION_SWITCH_DISABLED";
   else if(InpMode!=AUTO_EXECUTION) reason="OBSERVE_ONLY_MODE";
   else if(dir!="BUY" && dir!="SELL") reason="INVALID_DIRECTION";
   else if(sym=="" || !SymbolIsInConfiguredAllowlist(sym)) reason="SYMBOL_NOT_ALLOWED";
   else if(score<InpCrossAssetMinTechnicalScore) reason="TECHNICAL_SCORE_BELOW_MINIMUM";
   else if(!IsConnected() || !IsTradeAllowed() || IsTradeContextBusy()) reason="TERMINAL_OR_TRADE_CONTEXT_GATE";
   else if(AccountCurrency()!="USD" || EffectiveOperatingCapitalUSD()<=0.0) reason="USD_CAPITAL_VALIDATION_FAILED";
   else if(CrossAssetOpenCountForSymbol(sym)>0 || CrossAssetSameBaseAlreadyOpen(sym)) reason="ONE_POSITION_PER_CANONICAL_ASSET";
   else if(CountOpenTrades()>=EffectiveMaxOpenTrades()) reason="PORTFOLIO_POSITION_CAP";
   else if(IsCryptoLikeSymbol(sym) && CrossAssetCryptoOpenCount()>=InpCrossAssetMaxCryptoPositions) reason="CRYPTO_CONCENTRATION_CAP";
   else if(TodayNetProfit()<=-EffectiveDailyLossLimitUSD()) reason="DAILY_LOSS_LIMIT";
   else if(MarketInfo(sym,MODE_TRADEALLOWED)==0) reason="BROKER_SYMBOL_TRADE_DISABLED";
   else if(CrossAssetSpreadCeilingFor(sym)<=0 || MarketInfo(sym,MODE_SPREAD)>CrossAssetSpreadCeilingFor(sym)) reason="SPREAD_GATE";
   if(reason!="")
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," direction=",dir," score=",DoubleToString(score,2)," reason=",reason," | no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   if(!SymbolLocalEnsemblePass(sym,InpCrossAssetTimeframe,dir))
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," direction=",dir,
         " reason=LOCAL_16_MODEL_SYMBOL_SCOPED_ENSEMBLE_OR_EVIDENCE_REJECTED | no order sent.");
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=LOCAL_16_MODEL_SYMBOL_SCOPED_ENSEMBLE symbol=",sym,
         " direction=",dir," reason=LOCAL_MODEL_DIRECTION_OR_PER_MODEL_EVIDENCE_GATE");
      return false;
   }
   if(!SymbolSelect(sym,true))
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," reason=SYMBOL_SELECT_FAILED | no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   datetime quoteTime=(datetime)MarketInfo(sym,MODE_TIME);
   int quoteAge=(quoteTime>0?(int)(TimeCurrent()-quoteTime):999999);
   int digits=(int)MarketInfo(sym,MODE_DIGITS), spread=(int)MarketInfo(sym,MODE_SPREAD);
   double atr=iATR(sym,InpCrossAssetTimeframe,InpATRPeriod,1);
   if(bid<=0.0 || ask<bid || point<=0.0 || quoteAge<0 || quoteAge>InpCrossAssetMaxQuoteAgeSeconds || atr<=0.0 || digits<0 || digits>10)
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," reason=INVALID_OR_STALE_MARKET_DATA quoteAge=",quoteAge," ATR=",DoubleToString(atr,8)," | no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   int n=0,hn=0; double wr=0.0,avgR=-999.0,hwr=0.0,havgR=-999.0; string histReason="";
   if(!CrossAssetHistoricalEvidence(sym,InpCrossAssetTimeframe,dir,n,wr,avgR,histReason,hn,hwr,havgR) ||
      n<InpCrossAssetMinHistorySamples || wr<InpCrossAssetMinHistoryWinRate || avgR<=InpCrossAssetMinHistoryAvgR ||
      hn<InpCrossAssetMinHoldoutSamples || hwr<InpCrossAssetMinHoldoutWinRate || havgR<=InpCrossAssetMinHoldoutAvgR)
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," direction=",dir," reason=HISTORICAL_TRAIN_OR_HOLDOUT_GATE",
            " trainN=",n," winRate=",DoubleToString(wr,3)," avgRProxy=",DoubleToString(avgR,3),
            " holdoutN=",hn," holdoutWinRate=",DoubleToString(hwr,3)," holdoutAvgRProxy=",DoubleToString(havgR,3),
            " detail=",histReason," | no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   double openRisk=PortfolioOpenRiskUSD();
   if(openRisk<0.0)
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," reason=UNKNOWN_EXISTING_PORTFOLIO_RISK | open position has missing/unverifiable SL risk.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   double riskBudget=EvidenceAdaptiveRiskBudget(EffectiveRiskBudgetUSD(),wr,avgR,hwr,havgR);
   double stopDistance=atr*InpStopATR, targetDistance=atr*InpTargetATR;
   double lots=CrossAssetLotsForRisk(sym,riskBudget,stopDistance);
   if(lots<=0.0)
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," reason=LOT_OR_STOP_RISK_VALIDATION_FAILED riskBudgetUSD=",DoubleToString(riskBudget,2)," | no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   auditLots=lots;
   double proposedRisk=EstimateOrderRiskUSD(sym,lots,stopDistance);
   double proposedCostDistance=(MathMax(0.0,MarketInfo(sym,MODE_SPREAD))+MathMax(0,InpSlippagePoints))*MarketInfo(sym,MODE_POINT);
   double proposedTickSize=TickSizePriceForSymbol(sym);
   double proposedTickValue=MarketInfo(sym,MODE_TICKVALUE);
   if(proposedRisk>=0.0 && proposedTickSize>0.0 && proposedTickValue>0.0)
      proposedRisk+=lots*(proposedCostDistance/proposedTickSize)*proposedTickValue;
   auditRisk=proposedRisk;
   if(proposedRisk<0.0 || proposedRisk>InpHardRiskCapUSD+0.0001 || openRisk+proposedRisk>EffectivePortfolioRiskCapUSD()+0.0001)
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," reason=AGGREGATE_STOP_RISK_CAP openRiskUSD=",DoubleToString(openRisk,2),
            " proposedRiskUSD=",DoubleToString(proposedRisk,2)," capUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),2)," | no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   int type=(dir=="BUY"?OP_BUY:OP_SELL);
   double price=(dir=="BUY"?ask:bid);
   double sl=(dir=="BUY"?price-stopDistance:price+stopDistance);
   double tp=(dir=="BUY"?price+targetDistance:price-targetDistance);
   auditSL=sl; auditTP=tp;
   int stopLevel=(int)MarketInfo(sym,MODE_STOPLEVEL);
   double minStop=stopLevel*point;
   if(MathAbs(price-sl)<minStop || MathAbs(tp-price)<minStop)
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," reason=BROKER_STOP_LEVEL stopLevel=",stopLevel," | no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   double spreadCost=EstimateOrderRiskUSD(sym,lots,spread*point);
   double slippageCost=EstimateOrderRiskUSD(sym,lots,InpSlippagePoints*point);
   if(spreadCost<0.0 || slippageCost<0.0 || spreadCost+slippageCost>riskBudget*0.35)
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," reason=EXECUTION_COST_TOO_HIGH_OR_UNKNOWN spreadCostUSD=",DoubleToString(spreadCost,4),
            " slippageProxyUSD=",DoubleToString(slippageCost,4)," riskBudgetUSD=",DoubleToString(riskBudget,2)," | no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   double conservativeExpectedR=MathMin(avgR,havgR);
   if(!ValidatePositiveExpectedNetProfit(sym,lots,conservativeExpectedR,stopDistance,targetDistance,dir,"CROSS_ASSET_TRAIN_HOLDOUT_MIN"))
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," direction=",dir,
            " reason=GLOBAL_POSITIVE_NET_EXPECTANCY_GATE_FAILED",
            " trainAvgRProxy=",DoubleToString(avgR,6)," holdoutAvgRProxy=",DoubleToString(havgR,6),
            " conservativeExpectedR=",DoubleToString(conservativeExpectedR,6)," | no order sent.");
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",DoubleToString(lots,4),
            " riskUSD=",DoubleToString(proposedRisk,4)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits),
            " reason=GLOBAL_POSITIVE_NET_EXPECTANCY_GATE_FAILED");
      return false;
   }
   price=NormalizeDouble(price,digits); sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);
   auditSL=sl; auditTP=tp;
   Print("ENTRY AUTHORIZATION AUDIT | stage=RISK_AND_LEVELS_VALIDATED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
         " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",DoubleToString(lots,4),
         " riskUSD=",DoubleToString(proposedRisk,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits),
         " technicalScore=",DoubleToString(score,2)," trainN=",n," trainWR=",DoubleToString(wr,3),
         " trainAvgRProxy=",DoubleToString(avgR,3)," holdoutN=",hn," holdoutWR=",DoubleToString(hwr,3),
         " holdoutAvgRProxy=",DoubleToString(havgR,3)," decision=PENDING_FINAL_DUPLICATE_AND_SYMBOL_GUARDS");
   // Final execution-time guard: no other entry path may have occupied this canonical asset.
   int finalAssetPositions=CrossAssetOpenCountForSymbol(sym);
   if(finalAssetPositions>0 || CrossAssetSameBaseAlreadyOpen(sym))
   {
      Print("CROSS-ASSET EXECUTION BLOCK | symbol=",sym," canonicalAsset=",CanonicalAssetKey(sym),
            " reason=ONE_POSITION_PER_CANONICAL_ASSET existingPositions=",finalAssetPositions,
            " | final pre-OrderSend check; no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   string symbolGuardReason="";
   string expectedAssetKey=CanonicalAssetKey(sym);
   if(!ValidateExecutionAssetSymbol(sym,expectedAssetKey,symbolGuardReason))
   {
      Print("CROSS-ASSET EXECUTION BLOCK | requestedSymbol=",sym," canonicalAsset=",expectedAssetKey,
            " reason=ASSET_SYMBOL_MISMATCH_OR_INVALID_QUOTE detail=",symbolGuardReason," | no order sent.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   Print("TRADE EVIDENCE PACKET | schema=1 phase=PRE_ORDER source=CROSS_ASSET",
         " eaVersion=1.750 symbol=",sym," canonicalAsset=",expectedAssetKey,
         " timeframe=",InpCrossAssetTimeframe," direction=",dir,
         " selectedModel=CROSS_ASSET_16_MODEL_ENSEMBLE technicalScore=",DoubleToString(score,4),
         " trainN=",n," trainWinRate=",DoubleToString(wr,4)," trainAvgRProxy=",DoubleToString(avgR,6),
         " holdoutN=",hn," holdoutWinRate=",DoubleToString(hwr,4)," holdoutAvgRProxy=",DoubleToString(havgR,6),
         " lots=",DoubleToString(lots,4)," requestedRiskUSD=",DoubleToString(proposedRisk,4),
         " bid=",DoubleToString(MarketInfo(sym,MODE_BID),digits)," ask=",DoubleToString(MarketInfo(sym,MODE_ASK),digits),
         " spreadPoints=",spread," quoteTime=",TimeToString((datetime)MarketInfo(sym,MODE_TIME),TIME_DATE|TIME_SECONDS),
         " tickValue=",DoubleToString(MarketInfo(sym,MODE_TICKVALUE),8),
         " tickSize=",DoubleToString(TickSizePriceForSymbol(sym),10),
         " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits),
         " fixedCapitalUSD=",DoubleToString(EffectiveOperatingCapitalUSD(),2),
         " aggregateOpenRiskBeforeUSD=",DoubleToString(openRisk,4),
         " aggregateRiskAfterUSD=",DoubleToString(openRisk+proposedRisk,4),
         " aggregateRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),4),
         " dailyNetUSD=",DoubleToString(TodayNetProfit(),4),
         " reason=ALL_CHECKED_GATES_PASSED");
   Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=AUTHORIZED_TO_SEND source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
         " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",DoubleToString(lots,4),
         " riskUSD=",DoubleToString(proposedRisk,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits),
         " technicalScore=",DoubleToString(score,2)," aggregateRiskAfterUSD=",DoubleToString(openRisk+proposedRisk,2),
         " reason=ALL_CHECKED_GATES_PASSED");
   ResetLastError();
   int ticket=OrderSend(sym,type,lots,price,InpSlippagePoints,sl,tp,"Bitey SBT v1.75.0 "+expectedAssetKey,InpMagic,0,clrNONE);
   if(ticket<0)
   {
      int err=GetLastError();
      Print("ENTRY AUTHORIZATION AUDIT | stage=ORDER_SEND_RESULT decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",DoubleToString(lots,4),
            " riskUSD=",DoubleToString(proposedRisk,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits),
            " reason=ORDER_SEND_FAILED error=",err," description=",TradeErrorDescription(err));
      Print("CROSS-ASSET ORDER ERROR | symbol=",sym," direction=",dir," error=",err," description=",TradeErrorDescription(err),
            " lots=",DoubleToString(lots,4)," riskUSD=",DoubleToString(proposedRisk,2)," spreadPoints=",spread," | no blind retry and no risk bypass.");
      {
      Print("ENTRY AUTHORIZATION AUDIT | stage=FINAL decision=REJECTED source=CROSS_ASSET_16_MODEL_ENSEMBLE symbol=",sym,
            " direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",(auditLots>=0.0?DoubleToString(auditLots,4):"NOT_CALCULATED"),
            " riskUSD=",(auditRisk>=0.0?DoubleToString(auditRisk,2):"NOT_CALCULATED"),
            " SL=",(auditSL>0.0?DoubleToString(auditSL,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " TP=",(auditTP>0.0?DoubleToString(auditTP,(int)MarketInfo(sym,MODE_DIGITS)):"NOT_CALCULATED"),
            " reason=REJECTED_BY_GATE_DETAILS_IN_ADJACENT_EXECUTION_BLOCK");
      return false;
      }
   }
   bool readbackOK=false;
   double readbackRisk=-1.0;
   double readbackEntryPrice=0.0, readbackSL=0.0, readbackTP=0.0, readbackLots=0.0, readbackFloatingNet=0.0;
   if(OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))
   {
      readbackEntryPrice=OrderOpenPrice();
      readbackSL=OrderStopLoss();
      readbackTP=OrderTakeProfit();
      readbackLots=OrderLots();
      readbackFloatingNet=OrderProfit()+OrderSwap()+OrderCommission();
      readbackOK=(OrderStopLoss()>0.0 && OrderTakeProfit()>0.0 &&
         MathAbs(OrderStopLoss()-sl)<=MathMax(point,MarketInfo(sym,MODE_TICKSIZE))*1.5 &&
         MathAbs(OrderTakeProfit()-tp)<=MathMax(point,MarketInfo(sym,MODE_TICKSIZE))*1.5);
      readbackRisk=(OrderStopLoss()>0.0?EstimateOrderRiskUSD(sym,OrderLots(),MathAbs(OrderOpenPrice()-OrderStopLoss())):-1.0);
      Print("ORDER SLTP READBACK AUDIT | source=CROSS_ASSET ticket=",ticket," symbol=",sym," magic=",OrderMagicNumber(),
         " requestedSL=",DoubleToString(sl,digits)," confirmedSL=",DoubleToString(OrderStopLoss(),digits),
         " requestedTP=",DoubleToString(tp,digits)," confirmedTP=",DoubleToString(OrderTakeProfit(),digits),
         " readbackMatch=",(readbackOK?"true":"false")," stopRiskUSD=",(readbackRisk>=0.0?DoubleToString(readbackRisk,2):"UNKNOWN"),
         " status=",(readbackOK?"SERVER_READBACK_CONFIRMED":"WARNING_REVIEW_IMMEDIATELY"));
   }
   else Print("ORDER SLTP READBACK AUDIT | source=CROSS_ASSET ticket=",ticket," symbol=",sym," status=SELECT_TICKET_FAILED error=",GetLastError());
   Print("ENTRY AUTHORIZATION AUDIT | stage=ORDER_SEND_RESULT decision=ACCEPTED source=CROSS_ASSET_16_MODEL_ENSEMBLE ticket=",ticket,
         " symbol=",sym," direction=",dir," model=CROSS_ASSET_16_MODEL_ENSEMBLE lots=",DoubleToString(lots,4),
         " riskUSD=",DoubleToString(proposedRisk,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits),
         " reason=ORDER_OPENED_READBACK_STATUS=", (readbackOK?"CONFIRMED":"REVIEW_READBACK_LOG"));
   double postEntryPortfolioRisk=PortfolioOpenRiskUSD();
   Print("TRADE EVIDENCE PACKET | schema=1 phase=POST_ORDER source=CROSS_ASSET",
         " ticket=",ticket," symbol=",sym," canonicalAsset=",expectedAssetKey,
         " direction=",dir," opened=true",
         " readbackStatus=",(readbackOK?"CONFIRMED":"REVIEW_REQUIRED"),
         " actualEntryPrice=",(readbackEntryPrice>0.0?DoubleToString(readbackEntryPrice,digits):"UNAVAILABLE"),
         " actualLots=",(readbackLots>0.0?DoubleToString(readbackLots,4):"UNAVAILABLE"),
         " confirmedSL=",(readbackSL>0.0?DoubleToString(readbackSL,digits):"UNAVAILABLE"),
         " confirmedTP=",(readbackTP>0.0?DoubleToString(readbackTP,digits):"UNAVAILABLE"),
         " floatingNetUSD=",DoubleToString(readbackFloatingNet,4),
         " stopRiskUSD=",(readbackRisk>=0.0?DoubleToString(readbackRisk,4):"UNKNOWN_REVIEW_READBACK"),
         " aggregateOpenRiskAfterUSD=",(postEntryPortfolioRisk>=0.0?DoubleToString(postEntryPortfolioRisk,4):"UNKNOWN_FAIL_CLOSED"),
         " aggregateRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),4),
         " openPositionsAfter=",CountOpenTrades(),
         " dailyNetUSD=",DoubleToString(TodayNetProfit(),4),
         " trainN=",n," trainWinRate=",DoubleToString(wr,4)," trainAvgRProxy=",DoubleToString(avgR,6),
         " holdoutN=",hn," holdoutWinRate=",DoubleToString(hwr,4)," holdoutAvgRProxy=",DoubleToString(havgR,6),
         " nextAction=VERIFY_POSITION_SUPERVISION_AND_BROKER_READBACK");
   Print("CROSS-ASSET ORDER OPENED | ticket=",ticket," symbol=",sym," direction=",dir," lots=",DoubleToString(lots,4),
         " technicalScore=",DoubleToString(score,2)," trainN=",n," trainWinRate=",DoubleToString(wr,3)," trainAvgRProxy=",DoubleToString(avgR,3),
         " holdoutN=",hn," holdoutWinRate=",DoubleToString(hwr,3)," holdoutAvgRProxy=",DoubleToString(havgR,3),
         " estimatedStopRiskUSD=",DoubleToString(proposedRisk,2)," aggregateRiskAfterUSD=",DoubleToString(openRisk+proposedRisk,2),
         " spreadPoints=",spread," | historical proxy is not a profit guarantee.");
   AuditExistingPositionSupervision("POST_CROSS_ASSET_ENTRY");
   return true;
}

bool CrossAssetPreflightReplacement(string sym,string dir,double score,int incumbentTicket)
{
   string reason="";
   if(!InpCrossAssetAutoExecutionEnabled || !InpAllowTechnicalOnlyCrossAssetExecution || InpMode!=AUTO_EXECUTION) reason="EXECUTION_SWITCH_OR_MODE";
   else if(dir!="BUY" && dir!="SELL") reason="INVALID_DIRECTION";
   else if(!IsConnected() || !IsTradeAllowed() || IsTradeContextBusy()) reason="TRADE_PERMISSION_OR_CONTEXT";
   else if(AccountCurrency()!="USD" || EffectiveOperatingCapitalUSD()<=0.0) reason="USD_CAPITAL_VALIDATION";
   else if(CrossAssetOpenCountForSymbol(sym)>0 || CrossAssetSameBaseAlreadyOpen(sym)) reason="ONE_POSITION_PER_CANONICAL_ASSET";
   else if(TodayNetProfit()<=-EffectiveDailyLossLimitUSD()) reason="DAILY_LOSS_LIMIT";
   else if(MarketInfo(sym,MODE_TRADEALLOWED)==0) reason="SYMBOL_TRADING_DISABLED";
   else if(CrossAssetSpreadCeilingFor(sym)<=0 || MarketInfo(sym,MODE_SPREAD)>CrossAssetSpreadCeilingFor(sym)) reason="SPREAD_GATE";
   if(reason!="")
   {
      Print("CROSS-ASSET ROTATION PREFLIGHT BLOCK | candidate=",sym," direction=",dir," reason=",reason);
      return false;
   }
   if(!SymbolSelect(sym,true)) return false;
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   datetime qt=(datetime)MarketInfo(sym,MODE_TIME); int age=(qt>0?(int)(TimeCurrent()-qt):999999);
   int digits=(int)MarketInfo(sym,MODE_DIGITS), spread=(int)MarketInfo(sym,MODE_SPREAD);
   double atr=iATR(sym,InpCrossAssetTimeframe,InpATRPeriod,1);
   if(bid<=0.0 || ask<bid || point<=0.0 || age<0 || age>InpCrossAssetMaxQuoteAgeSeconds || atr<=0.0 || digits<0 || digits>10)
   { Print("CROSS-ASSET ROTATION PREFLIGHT BLOCK | candidate=",sym," reason=STALE_OR_INVALID_QUOTE_OR_ATR age=",age); return false; }
   int n=0,hn=0; double wr=0.0,avgR=-999.0,hwr=0.0,havgR=-999.0; string histReason="";
   if(!CrossAssetHistoricalEvidence(sym,InpCrossAssetTimeframe,dir,n,wr,avgR,histReason,hn,hwr,havgR) ||
      n<InpCrossAssetMinHistorySamples || wr<InpCrossAssetMinHistoryWinRate || avgR<=InpCrossAssetMinHistoryAvgR ||
      hn<InpCrossAssetMinHoldoutSamples || hwr<InpCrossAssetMinHoldoutWinRate || havgR<=InpCrossAssetMinHoldoutAvgR)
   { Print("CROSS-ASSET ROTATION PREFLIGHT BLOCK | candidate=",sym," reason=TRAIN_HOLDOUT_EVIDENCE_GATE detail=",histReason); return false; }
   double currentRisk=PortfolioOpenRiskUSD();
   if(!OrderSelect(incumbentTicket,SELECT_BY_TICKET) || OrderCloseTime()>0) return false;
   string incumbentSymbolForPreflight=OrderSymbol();
   bool incumbentIsCrypto=LooksLikeCryptoSymbol(incumbentSymbolForPreflight);
   double incumbentRisk=(OrderStopLoss()>0.0?EstimateOrderRiskUSD(incumbentSymbolForPreflight,OrderLots(),MathAbs(OrderOpenPrice()-OrderStopLoss())):-1.0);
   if(currentRisk<0.0 || incumbentRisk<0.0) { Print("CROSS-ASSET ROTATION PREFLIGHT BLOCK | candidate=",sym," reason=UNKNOWN_PORTFOLIO_OR_INCUMBENT_RISK"); return false; }
   int cryptoAfterRotation=CrossAssetCryptoOpenCount()-(incumbentIsCrypto?1:0);
   if(IsCryptoLikeSymbol(sym) && cryptoAfterRotation>=InpCrossAssetMaxCryptoPositions)
   { Print("CROSS-ASSET ROTATION PREFLIGHT BLOCK | candidate=",sym," reason=CRYPTO_CONCENTRATION_AFTER_ROTATION cryptoCount=",cryptoAfterRotation," max=",InpCrossAssetMaxCryptoPositions); return false; }
   double riskBudget=EvidenceAdaptiveRiskBudget(EffectiveRiskBudgetUSD(),wr,avgR,hwr,havgR), stopDistance=atr*InpStopATR, targetDistance=atr*InpTargetATR;
   double lots=CrossAssetLotsForRisk(sym,riskBudget,stopDistance);
   double proposedRisk=(lots>0.0?EstimateOrderRiskUSD(sym,lots,stopDistance):-1.0);
   if(lots<=0.0 || proposedRisk<0.0 || proposedRisk>InpHardRiskCapUSD+0.0001 || currentRisk-incumbentRisk+proposedRisk>EffectivePortfolioRiskCapUSD()+0.0001)
   { Print("CROSS-ASSET ROTATION PREFLIGHT BLOCK | candidate=",sym," reason=LOT_OR_POST_ROTATION_RISK_GATE currentRisk=",DoubleToString(currentRisk,2)," incumbentRisk=",DoubleToString(incumbentRisk,2)," proposedRisk=",DoubleToString(proposedRisk,2)); return false; }
   double price=(dir=="BUY"?ask:bid), minStop=MarketInfo(sym,MODE_STOPLEVEL)*point;
   double sl=(dir=="BUY"?price-stopDistance:price+stopDistance), tp=(dir=="BUY"?price+targetDistance:price-targetDistance);
   if(MathAbs(price-sl)<minStop || MathAbs(tp-price)<minStop) { Print("CROSS-ASSET ROTATION PREFLIGHT BLOCK | candidate=",sym," reason=BROKER_STOP_LEVEL"); return false; }
   double spreadCost=EstimateOrderRiskUSD(sym,lots,spread*point), slipCost=EstimateOrderRiskUSD(sym,lots,InpSlippagePoints*point);
   if(spreadCost<0.0 || slipCost<0.0 || spreadCost+slipCost>riskBudget*0.35)
   { Print("CROSS-ASSET ROTATION PREFLIGHT BLOCK | candidate=",sym," reason=COST_GATE spreadCost=",DoubleToString(spreadCost,4)," slippageProxy=",DoubleToString(slipCost,4)); return false; }
   Print("CROSS-ASSET ROTATION PREFLIGHT PASS | candidate=",sym," direction=",dir," technicalScore=",DoubleToString(score,2),
         " trainN=",n," trainWR=",DoubleToString(wr,3)," trainAvgRProxy=",DoubleToString(avgR,3),
         " holdoutN=",hn," holdoutWR=",DoubleToString(hwr,3)," holdoutAvgRProxy=",DoubleToString(havgR,3),
         " lots=",DoubleToString(lots,4)," proposedRiskUSD=",DoubleToString(proposedRisk,2),
         " postRotationAggregateRiskUSD=",DoubleToString(currentRisk-incumbentRisk+proposedRisk,2)," | order send still rechecks every gate after close.");
   return true;
}

void ManageCrossAssetPositionsAgainstRankings()
{
    // v1.63.3 hard policy: never close/reopen positions to rotate assets.
    // Existing positions are supervised only through SL/TP management.
    return;
    if(!InpEnablePositionReplacement) return;
   if(!InpCrossAssetAutoExecutionEnabled || !InpCrossAssetRankingEnabled) return;
   for(int p=OrdersTotal()-1;p>=0;p--)
   {
      if(!OrderSelect(p,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;

      int incumbentTicket=OrderTicket();
      string incumbent=OrderSymbol();
      int incumbentType=OrderType();
      int incumbentDir=(incumbentType==OP_BUY?1:-1);
      double incumbentLots=OrderLots();
      string incumbentSignal="NONE", incumbentReason=""; int bars=0;
      double incumbentScore=CrossAssetTechnicalScore(incumbent,InpCrossAssetTimeframe,incumbentSignal,incumbentReason,bars);
      double incumbentNet=OrderProfit()+OrderSwap()+OrderCommission();
      string bestSym="", bestDir="NONE"; double bestScore=-1.0, bestPriority=-1.0; int bestIndex=-1;
      for(int j=0;j<100;j++)
      {
         string candidate=g_crossAssetRankNames[j];
         if(candidate=="") break;
         if(candidate==incumbent) continue;
         if(CrossAssetOpenCountForSymbol(candidate)>0 || CrossAssetSameBaseAlreadyOpen(candidate)) continue;
         if(g_crossAssetRankPriority[j]>bestPriority)
         { bestScore=g_crossAssetRankScores[j]; bestPriority=g_crossAssetRankPriority[j]; bestSym=candidate; bestDir=g_crossAssetRankDirs[j]; bestIndex=j; }
      }
      if(bestSym=="" || (bestDir!="BUY" && bestDir!="SELL") || bestScore<InpCrossAssetMinTechnicalScore)
      {
         Print("CROSS-ASSET POSITION COMPARISON | incumbentTicket=",incumbentTicket," incumbentSymbol=",incumbent,
               " incumbentType=",(incumbentDir>0?"BUY":"SELL")," incumbentNetUSD=",DoubleToString(incumbentNet,2),
               " incumbentTechnicalScore=",DoubleToString(incumbentScore,1)," decision=KEEP reason=NO_QUALIFIED_ALTERNATIVE");
         continue;
      }
      double incumbentPriority=incumbentScore;
      if(incumbentScore>0.0 && (incumbentSignal=="BUY" || incumbentSignal=="SELL"))
      {
         int incN=0,incHoldoutN=0; double incWR=0.0,incAvgR=-999.0,incHoldWR=0.0,incHoldAvgR=-999.0; string incHistReason="";
         if(CrossAssetHistoricalEvidence(incumbent,InpCrossAssetTimeframe,incumbentSignal,incN,incWR,incAvgR,incHistReason,incHoldoutN,incHoldWR,incHoldAvgR) &&
            incN>=InpCrossAssetMinHistorySamples && incWR>=InpCrossAssetMinHistoryWinRate && incAvgR>InpCrossAssetMinHistoryAvgR &&
            incHoldoutN>=InpCrossAssetMinHoldoutSamples && incHoldWR>=InpCrossAssetMinHoldoutWinRate && incHoldAvgR>InpCrossAssetMinHoldoutAvgR)
            incumbentPriority=CrossAssetOpportunityPriority(incumbentScore,incWR,incAvgR,incHoldWR,incHoldAvgR);
      }
      double advantage=bestPriority-incumbentPriority;
      bool losing=(incumbentNet < -MathMax(0.10,InpReplacementMinFloatingLossUSD));
      bool better=(incumbentScore>=0.0 && advantage>=MathMax(12.0,InpReplacementMinScoreAdvantage*100.0));
      int altSpread=(int)MarketInfo(bestSym,MODE_SPREAD);
      Print("CROSS-ASSET OPPORTUNITY COMPARISON | incumbentTicket=",incumbentTicket,
            " incumbentSymbol=",incumbent," incumbentType=",(incumbentDir>0?"BUY":"SELL"),
            " incumbentNetUSD=",DoubleToString(incumbentNet,2)," incumbentTechnicalScore=",DoubleToString(incumbentScore,1),
            " incumbentSignal=",incumbentSignal," incumbentSignalReason=",incumbentReason,
            " candidateSymbol=",bestSym," candidateDirection=",bestDir," candidateTechnicalScore=",DoubleToString(bestScore,1),
            " candidateOpportunityPriority=",DoubleToString(bestPriority,1)," incumbentOpportunityPriority=",DoubleToString(incumbentPriority,1),
            " priorityAdvantage=",DoubleToString(advantage,1)," candidateHistoryN=",g_crossAssetRankSamples[bestIndex],
            " candidateHistoryWinRate=",DoubleToString(g_crossAssetRankWinRates[bestIndex],3),
            " candidateHistoryAvgRProxy=",DoubleToString(g_crossAssetRankAvgR[bestIndex],3),
            " candidateHoldoutN=",g_crossAssetRankHoldoutSamples[bestIndex],
            " candidateHoldoutWinRate=",DoubleToString(g_crossAssetRankHoldoutWinRates[bestIndex],3),
            " candidateHoldoutAvgRProxy=",DoubleToString(g_crossAssetRankHoldoutAvgR[bestIndex],3),
            " candidateSpreadPoints=",altSpread," incumbentLossThresholdMet=",(losing?"true":"false"),
            " scoreAdvantageMet=",(better?"true":"false"),
            " decision=",(better?"REPLACEMENT_REVIEW_ONLY":"KEEP_CURRENT_POSITION"),
            " incumbentCurrentlyLosing=",(losing?"true":"false"),
            " | replacement may be considered even if incumbent is profitable, but only when alternative advantage is material and execution gates pass.");
      if(!better) continue;

      if(!InpAllowTechnicalOnlyCrossAssetExecution)
      {
         Print("CROSS-ASSET REPLACEMENT ABORTED | incumbentTicket=",incumbentTicket,
               " reason=ALTERNATIVE_LACKS_PER_SYMBOL_HISTORICAL_EVIDENCE | incumbent retained; no close attempted.");
         continue;
      }
      if(InpPositionReplacementAuditOnly)
      {
         Print("CROSS-ASSET REPLACEMENT DECISION | action=KEEP_CURRENT_AUDIT_ONLY | incumbentTicket=",incumbentTicket,
               " alternativeSymbol=",bestSym," | no order or close sent.");
         continue;
      }
      if(!IsTradeAllowed() || IsTradeContextBusy())
      {
         Print("CROSS-ASSET REPLACEMENT ABORTED | incumbentTicket=",incumbentTicket,
               " reason=TRADE_PERMISSION_OR_CONTEXT | incumbent retained.");
         continue;
      }

      // Prefer open-before-close if there is a spare slot. At full capacity, a prechecked
      // close-then-open rotation is allowed only if daily quota/loss gates leave room.
      // If the alternative send fails after a full-capacity close, the portfolio remains
      // within limits with one fewer position; the EA never forces a second entry.
      bool alternativeOpened=false;
      if(CountOpenTrades()<EffectiveMaxOpenTrades())
      {
         alternativeOpened=CrossAssetSendRankedOrder(bestSym,bestDir,bestScore);
         if(!alternativeOpened)
         {
            Print("CROSS-ASSET REPLACEMENT ABORTED | incumbentTicket=",incumbentTicket,
                  " incumbentSymbol=",incumbent," alternativeSymbol=",bestSym,
                  " alternativeDirection=",bestDir,
                  " reason=ALTERNATIVE_ENTRY_NOT_CONFIRMED_OR_GATE_BLOCKED | incumbent retained; no close attempted.");
            continue;
         }
      }
      else
      {
         if(!CrossAssetPreflightReplacement(bestSym,bestDir,bestScore,incumbentTicket))
         {
            Print("CROSS-ASSET REPLACEMENT ABORTED | incumbentTicket=",incumbentTicket,
                  " reason=FULL_CAPACITY_CANDIDATE_PREFLIGHT_FAILED | incumbent retained.");
            continue;
         }
         Print("CROSS-ASSET REPLACEMENT | incumbentTicket=",incumbentTicket," candidate=",bestSym," direction=",bestDir,
               " action=PRECHECKED_CLOSE_THEN_OPEN | reason=FULL_THREE_POSITION_CAP_PREVENTS_SAFE_OVERLAP");
      }

      if(!OrderSelect(incumbentTicket,SELECT_BY_TICKET))
      {
         Print("CROSS-ASSET REPLACEMENT WARNING | alternativeSymbol=",bestSym,
               " alternativeOpened=true incumbentTicket=",incumbentTicket,
               " reason=INCUMBENT_TICKET_NOT_FOUND | inspect positions; no further close attempted.");
         return;
      }
      if(OrderCloseTime()>0)
      {
         Print("CROSS-ASSET REPLACEMENT NOTICE | incumbentTicket=",incumbentTicket,
               " reason=INCUMBENT_ALREADY_CLOSED | alternativeSymbol=",bestSym," remains open.");
         return;
      }
      double closePrice=(incumbentType==OP_BUY?MarketInfo(incumbent,MODE_BID):MarketInfo(incumbent,MODE_ASK));
      int dg=(int)MarketInfo(incumbent,MODE_DIGITS);
      if(closePrice<=0 || MarketInfo(incumbent,MODE_TRADEALLOWED)==0)
      {
         Print("CROSS-ASSET REPLACEMENT WARNING | incumbentTicket=",incumbentTicket,
               " alternativeSymbol=",bestSym," alternativeOpened=true",
               " reason=INCUMBENT_CLOSE_PRICE_INVALID_OR_SYMBOL_DISABLED",
               " | both positions may remain open; aggregate risk was checked before alternative entry.");
         return;
      }
      closePrice=NormalizeDouble(closePrice,dg);
      ResetLastError();
      bool incumbentClosed=OrderClose(incumbentTicket,incumbentLots,closePrice,InpSlippagePoints,clrNONE);
      if(!incumbentClosed)
      {
         int closeErr=GetLastError();
         Print("CROSS-ASSET REPLACEMENT WARNING | incumbentTicket=",incumbentTicket,
               " incumbentSymbol=",incumbent," alternativeSymbol=",bestSym,
               " alternativeDirection=",bestDir," alternativeOpened=true",
               " incumbentCloseError=",closeErr," description=",TradeErrorDescription(closeErr),
               " | incumbent not confirmed closed; both positions may remain open. Inspect risk immediately.");
      }
      else
      {
         Print("CROSS-ASSET REPLACEMENT COMPLETED | closedTicket=",incumbentTicket,
               " closedSymbol=",incumbent," closedNetUSD=",DoubleToString(incumbentNet,2),
               " alternativeSymbol=",bestSym," alternativeDirection=",bestDir,
               " alternativeScore=",DoubleToString(bestScore,1)," scoreAdvantage=",DoubleToString(advantage,1),
               " | incumbent close confirmed; no profit guarantee.");
         if(!alternativeOpened)
         {
            alternativeOpened=CrossAssetSendRankedOrder(bestSym,bestDir,bestScore);
            if(!alternativeOpened)
               Print("CROSS-ASSET ROTATION RESULT | incumbentClosed=true alternativeOpened=false symbol=",bestSym,
                     " | portfolio remains within caps with one fewer position; no forced retry.");
         }
         return;
      }
   }
}

void ExecuteCrossAssetRankedCandidates()
{
   if(!InpCrossAssetAutoExecutionEnabled || !InpMarketWatchScannerEnabled || !InpCrossAssetRankingEnabled) return;
   if(!IsConnected() || InpMode!=AUTO_EXECUTION) return;
   int slots=EffectiveMaxOpenTrades()-CountOpenTrades();
   if(slots<=0)
   {
      Print("GLOBAL CANDIDATE RANKING AUDIT | decision=NO_FREE_SLOT openPositions=",CountOpenTrades(),
            " maximumPositions=",EffectiveMaxOpenTrades(),
            " action=CONTINUE_POSITION_SUPERVISION_ONLY");
      return;
   }
   int opened=0, reviewed=0;
   string topSymbol=g_crossAssetRankNames[0];
   string topDirection=g_crossAssetRankDirs[0];
   double topScore=g_crossAssetRankScores[0];
   Print("GLOBAL CANDIDATE RANKING AUDIT | objective=BEST_QUALIFIED_DISTINCT_ASSETS",
         " topRankSymbol=",topSymbol," topRankDirection=",topDirection,
         " topRankScore=",DoubleToString(topScore,4),
         " freeSlots=",slots," openPositions=",CountOpenTrades(),
         " maximumPositions=",EffectiveMaxOpenTrades(),
         " aggregateOpenRiskUSD=",DoubleToString(PortfolioOpenRiskUSD(),4),
         " aggregateRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),4),
         " selectionPolicy=DESCENDING_EVIDENCE_ADJUSTED_PRIORITY",
         " action=RECHECK_EACH_CANDIDATE_LIVE_GATES_AND_CANONICAL_DUPLICATES");
   // v1.57.0 portfolio-fill behavior: inspect the evidence-ranked candidates and
   // open as many distinct qualified assets as there are free slots in this pass.
   // Each send rechecks the live duplicate, spread, quote, evidence, daily and
   // aggregate-risk gates; failure on one candidate does not block later candidates.
   // This permits up to seven concurrent positions, but never forces an entry.
   for(int i=0;i<100 && opened<slots;i++)
   {
      string sym=g_crossAssetRankNames[i];
      if(sym=="") break;
      reviewed++;
      string dir=g_crossAssetRankDirs[i]; double score=g_crossAssetRankScores[i];
      if(dir!="BUY" && dir!="SELL") continue;
      if(score<InpCrossAssetMinTechnicalScore) continue;
      Print("CROSS-ASSET BEST-OPPORTUNITY REVIEW | rank=",i+1," symbol=",sym," direction=",dir,
            " technicalScore=",DoubleToString(score,2)," priority=",DoubleToString(g_crossAssetRankPriority[i],2),
            " trainN=",g_crossAssetRankSamples[i]," trainWinRate=",DoubleToString(g_crossAssetRankWinRates[i],3),
            " trainAvgRProxy=",DoubleToString(g_crossAssetRankAvgR[i],3),
            " holdoutN=",g_crossAssetRankHoldoutSamples[i]," holdoutWinRate=",DoubleToString(g_crossAssetRankHoldoutWinRates[i],3),
            " holdoutAvgRProxy=",DoubleToString(g_crossAssetRankHoldoutAvgR[i],3),
            " action=TRY_HIGHEST_RANKED_CANDIDATE_WITH_ALL_LIVE_GATES");
      if(CrossAssetSendRankedOrder(sym,dir,score)) opened++;
   }
   if(opened>0)
      Print("CROSS-ASSET EXECUTION SUMMARY | evidenceRankedCandidatesOpenedThisPass=",opened,
            " freeSlotsAtPassStart=",slots," portfolioOpen=",CountOpenTrades(),"/",EffectiveMaxOpenTrades(),
            " tradesToday=",CountTodayTrades(),"/",InpMaxTradesPerDay,
            " openRiskUSD=",DoubleToString(PortfolioOpenRiskUSD(),2)," capUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),2),
            " | fills as many distinct qualified assets as live gates allow; no entry forced and no risk/evidence threshold bypassed.");
   else
      Print("CROSS-ASSET EXECUTION SUMMARY | openedThisPass=0 rankedCandidatesReviewed=",reviewed,
            " | no candidate passed all current live execution and portfolio-risk gates; no order forced. See CROSS-ASSET EVIDENCE GATE AUDIT for per-threshold failures; evidence is historical bar proxy, not actual closed-trade outcomes.");
}

bool ThreeClosedCandlesConfirmFavorableMove(string sym,int timeframe,int orderType)
{
   if(iBars(sym,timeframe)<5) return false;
   for(int shift=1;shift<=3;shift++)
   {
      double o=iOpen(sym,timeframe,shift);
      double c=iClose(sym,timeframe,shift);
      double previousClose=iClose(sym,timeframe,shift+1);
      if(o<=0.0 || c<=0.0 || previousClose<=0.0) return false;
      if(orderType==OP_BUY)
      {
         if(c<=o || c<=previousClose) return false; // Three bullish candles with progressively higher closes.
      }
      else if(orderType==OP_SELL)
      {
         if(c>=o || c>=previousClose) return false; // Three bearish candles with progressively lower closes.
      }
      else return false;
   }
   return true;
}

// Emergency fallback for an existing position whose stop risk cannot be brought under USD5.00.
// Market close is best-effort; gaps/slippage can still cause realized loss above the cap.
bool EmergencyCloseRiskCapBreach(int ticket,string sym,int type,double lots,double riskUSD,string reason)
{
   if(!IsConnected() || !IsTradeAllowed() || IsTradeContextBusy())
   {
      Print("RISK_CAP_EMERGENCY_CLOSE_FAILED | ticket=",ticket," symbol=",sym,
         " riskUSD=",DoubleToString(riskUSD,2)," reason=",reason,
         " detail=TRADE_CONTEXT_UNAVAILABLE; existing SL remains; retry on next supervision pass");
      return false;
   }
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))
   {
      // If the ticket is no longer open, treat it as no longer requiring a live close.
      Print("RISK_CAP_EMERGENCY_CLOSE_CHECK | ticket=",ticket," symbol=",sym,
         " reason=",reason," result=TICKET_NOT_SELECTABLE_CHECK_HISTORY");
      return false;
   }
   if(OrderCloseTime()>0) return true;
   double lotsNow=OrderLots();
   double px=(type==OP_BUY?MarketInfo(sym,MODE_BID):MarketInfo(sym,MODE_ASK));
   if(lotsNow<=0.0 || px<=0.0)
   {
      Print("RISK_CAP_EMERGENCY_CLOSE_FAILED | ticket=",ticket," symbol=",sym,
         " riskUSD=",DoubleToString(riskUSD,2)," reason=",reason," detail=INVALID_CLOSE_PRICE_OR_LOTS");
      return false;
   }
   ResetLastError();
   bool sent=OrderClose(ticket,lotsNow,px,InpSlippagePoints,clrNONE);
   int err=(sent?0:GetLastError());
   bool stillOpen=OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES) && OrderCloseTime()==0;
   bool confirmed=(sent && !stillOpen);
   Print("RISK_CAP_EMERGENCY_CLOSE | ticket=",ticket," symbol=",sym,
      " riskUSD=",DoubleToString(riskUSD,2)," capUSD=",DoubleToString(MathMin(InpHardRiskCapUSD,EffectiveOperatingCapitalUSD()*InpMaxRiskPerTradeCapitalPct/100.0),2)," reason=",reason,
      " requestedPrice=",DoubleToString(px,(int)MarketInfo(sym,MODE_DIGITS)),
      " closeSent=",(sent?"true":"false")," error=",err,
      " stillOpen=",(stillOpen?"true":"false"),
      " result=",(confirmed?"CLOSED_CONFIRMED":"CLOSE_NOT_CONFIRMED_RETRY_REQUIRED"));
   return confirmed;
}

// Hard per-ticket risk repair runs independently of the profit/three-candle adaptive manager.
// It only tightens SL first; if the cap cannot be enforced, it attempts an emergency market close.
// Broker rejection, disconnection, gaps and slippage can still prevent a guaranteed realized-loss ceiling.
void EnforceOpenPositionRiskCapAdaptive()
{
   if(!IsConnected() || !IsTradeAllowed() || IsTradeContextBusy()) return;
   const double capUSD=MathMin(InpHardRiskCapUSD,EffectiveOperatingCapitalUSD()*InpMaxRiskPerTradeCapitalPct/100.0);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;

      int ticket=OrderTicket();
      string sym=OrderSymbol();
      double lots=OrderLots(), open=OrderOpenPrice(), oldSL=OrderStopLoss(), oldTP=OrderTakeProfit();
      double tickValue=MarketInfo(sym,MODE_TICKVALUE);
      double tickSize=TickSizePriceForSymbol(sym);
      double point=MarketInfo(sym,MODE_POINT);
      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      if(lots<=0 || open<=0 || tickValue<=0 || tickSize<=0 || point<=0 || bid<=0 || ask<bid || digits<0)
      {
         // Fail closed: unknown risk is never considered compliant. The account/broker may
         // reject the close, but we must record an emergency-close attempt rather than silently
         // leave an unverifiable position active. New entries are independently blocked because
         // PortfolioOpenRiskUSD() returns -1 when this position's risk cannot be estimated.
         Print("PER_TRADE_RISK_CAP_ENFORCEMENT_FAILED | ticket=",ticket," symbol=",sym,
            " reason=INVALID_LOT_PRICE_OR_TICK_VALUE lots=",DoubleToString(lots,3),
            " tickValue=",DoubleToString(tickValue,6)," tickSizePrice=",DoubleToString(tickSize,8),
            " riskStatus=UNKNOWN action=EMERGENCY_CLOSE_ATTEMPT_AND_BLOCK_NEW_ENTRIES");
         EmergencyCloseRiskCapBreach(ticket,sym,type,lots,-1.0,"INVALID_LOT_PRICE_OR_TICK_VALUE");
         continue;
      }
      double oldRisk=(oldSL>0?EstimateOrderRiskUSD(sym,lots,MathAbs(open-oldSL)):-1.0);
      if(oldRisk>=0 && oldRisk<=capUSD+0.01) continue;

      // Convert the hard USD cap to a price distance using this symbol's live tick value.
      double distance=capUSD*tickSize/(lots*tickValue);
      if(distance<=0 || !MathIsValidNumber(distance))
      {
         Print("PER_TRADE_RISK_CAP_ENFORCEMENT_FAILED | ticket=",ticket," symbol=",sym,
            " reason=INVALID_CAP_DISTANCE riskStatus=UNKNOWN action=EMERGENCY_CLOSE_ATTEMPT_AND_BLOCK_NEW_ENTRIES");
         EmergencyCloseRiskCapBreach(ticket,sym,type,lots,oldRisk,"INVALID_CAP_DISTANCE");
         continue;
      }
      double targetSL=(type==OP_BUY?open-distance:open+distance);
      targetSL=NormalizeDouble(targetSL,digits);

      // Preserve monotonic protection: only move SL toward market, never farther away.
      if(oldSL>0)
      {
         if(type==OP_BUY && targetSL<oldSL) targetSL=oldSL;
         if(type==OP_SELL && targetSL>oldSL) targetSL=oldSL;
      }
      double newRisk=EstimateOrderRiskUSD(sym,lots,MathAbs(open-targetSL));
      if(newRisk<0 || newRisk>capUSD+0.02)
      {
         Print("PER_TRADE_RISK_CAP_ENFORCEMENT_FAILED | ticket=",ticket," symbol=",sym,
            " reason=TARGET_STILL_OVER_CAP oldRiskUSD=",DoubleToString(oldRisk,2),
            " targetRiskUSD=",DoubleToString(newRisk,2)," capUSD=",DoubleToString(capUSD,2),
            " oldSL=",DoubleToString(oldSL,digits)," targetSL=",DoubleToString(targetSL,digits),
            " action=EMERGENCY_CLOSE_ATTEMPT");
         EmergencyCloseRiskCapBreach(ticket,sym,type,lots,oldRisk,"TARGET_STILL_OVER_CAP");
         continue;
      }
      int stopLevel=(int)MarketInfo(sym,MODE_STOPLEVEL);
      int freezeLevel=(int)MarketInfo(sym,MODE_FREEZELEVEL);
      double minDistance=MathMax(stopLevel,freezeLevel)*point;
      bool legal=(type==OP_BUY ? targetSL<bid-minDistance : targetSL>ask+minDistance);
      if(!legal)
      {
         Print("PER_TRADE_RISK_CAP_ENFORCEMENT_FAILED | ticket=",ticket," symbol=",sym,
            " reason=MARKET_OR_BROKER_STOP_FREEZE_DISTANCE_PREVENTS_CAP",
            " oldRiskUSD=",(oldRisk>=0?DoubleToString(oldRisk,2):"UNKNOWN"),
            " targetRiskUSD=",DoubleToString(newRisk,2)," capUSD=",DoubleToString(capUSD,2),
            " bid=",DoubleToString(bid,digits)," ask=",DoubleToString(ask,digits),
            " oldSL=",DoubleToString(oldSL,digits)," targetSL=",DoubleToString(targetSL,digits),
            " action=EMERGENCY_CLOSE_ATTEMPT");
         EmergencyCloseRiskCapBreach(ticket,sym,type,lots,oldRisk,"BROKER_DISTANCE_PREVENTS_CAP");
         continue;
      }
      // Skip insignificant changes only if the existing SL already meets the cap.
      if(oldSL>0 && MathAbs(targetSL-oldSL)<point*0.5) continue;

      ResetLastError();
      bool ok=OrderModify(ticket,open,targetSL,oldTP,0,clrNONE);
      int err=(ok?0:GetLastError());
      bool readOK=OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES);
      double readSL=(readOK?OrderStopLoss():0.0);
      double readRisk=(readOK && readSL>0?EstimateOrderRiskUSD(sym,lots,MathAbs(open-readSL)):-1.0);
      bool confirmed=(ok && readOK && readSL>0 && readRisk>=0 && readRisk<=capUSD+0.02 &&
         (oldSL<=0 || (type==OP_BUY?readSL>=oldSL-point*0.5:readSL<=oldSL+point*0.5)));
      Print("PER_TRADE_RISK_CAP_ENFORCEMENT | ticket=",ticket," symbol=",sym,
         " side=",(type==OP_BUY?"BUY":"SELL")," lots=",DoubleToString(lots,3),
         " oldRiskUSD=",(oldRisk>=0?DoubleToString(oldRisk,2):"UNKNOWN"),
         " targetRiskUSD=",DoubleToString(newRisk,2)," capUSD=",DoubleToString(capUSD,2),
         " oldSL=",DoubleToString(oldSL,digits)," requestedSL=",DoubleToString(targetSL,digits),
         " modifyOK=",(ok?"true":"false")," error=",err,
         " readbackOK=",(readOK?"true":"false"),
         " confirmedSL=",(readOK?DoubleToString(readSL,digits):"N/A"),
         " confirmedRiskUSD=",(readRisk>=0?DoubleToString(readRisk,2):"UNKNOWN"),
         " result=",(confirmed?"CAP_ENFORCED_READBACK_CONFIRMED":"CRITICAL_CAP_NOT_CONFIRMED"));
      if(!confirmed && (readRisk<0.0 || readRisk>capUSD+0.02))
         EmergencyCloseRiskCapBreach(ticket,sym,type,lots,(readRisk>=0.0?readRisk:oldRisk),"SL_MODIFY_FAILED_OR_UNCONFIRMED");
       if(!confirmed && (readRisk<0.0 || readRisk>capUSD+0.02))
          EmergencyCloseRiskCapBreach(ticket,sym,type,lots,(readRisk>=0.0?readRisk:oldRisk),"SL_MODIFY_FAILED_OR_UNCONFIRMED");
   }
}

// Manage every open symbol for this EA magic, not only the chart symbol.
// Cost-aware profit-only rule: floating net P/L includes profit, swap and commission.
// Do not adapt SL/TP until net P/L clears the configured minimum; this prevents reacting to
// a nominal price move that has not covered known transaction costs. Existing broker SL/TP
// remain untouched below the threshold. SL is monotonic; TP only extends favorably.
// v1.77: net floating loss <= -USD0.50 must persist >60 seconds before close.
bool EnforcePersistentNegativeProfitClose()
{
 bool allowEntries=true; datetime now=TimeCurrent();
 for(int i=OrdersTotal()-1;i>=0;i--)
 {
  if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
  if(OrderMagicNumber()!=InpMagic) continue;
  int type=OrderType(); if(type!=OP_BUY && type!=OP_SELL) continue;
  int ticket=OrderTicket(); string sym=OrderSymbol();
  double net=OrderProfit()+OrderSwap()+OrderCommission();
  string key=StringFormat("BiteyNegProfitSince_%d",ticket);
  if(net > -0.50) { if(GlobalVariableCheck(key)) GlobalVariableDel(key); continue; }
  allowEntries=false; datetime since=0;
  if(GlobalVariableCheck(key)) since=(datetime)GlobalVariableGet(key);
  if(since<=0 || since>now) { GlobalVariableSet(key,(double)now); Print("NEGATIVE PROFIT PERSISTENCE | TIMER_STARTED ticket=",ticket," netUSD=",DoubleToString(net,4)," threshold=-0.50"); continue; }
  int elapsed=(int)(now-since);
  if(elapsed<=60) { Print("NEGATIVE PROFIT PERSISTENCE | WAITING ticket=",ticket," netUSD=",DoubleToString(net,4)," seconds=",elapsed); continue; }
  RefreshRates(); double px=MarketInfo(sym,(type==OP_BUY?MODE_BID:MODE_ASK));
  int dg=(int)MarketInfo(sym,MODE_DIGITS); double lots=OrderLots();
  if(px<=0 || lots<=0 || !IsTradeAllowed() || IsTradeContextBusy()) { Print("NEGATIVE PROFIT AUTO-CLOSE | RETRY ticket=",ticket," seconds=",elapsed," netUSD=",DoubleToString(net,4)); continue; }
  ResetLastError(); bool ok=OrderClose(ticket,lots,NormalizeDouble(px,dg),InpSlippagePoints,clrNONE);
  int err=(ok?0:GetLastError());
  Print("NEGATIVE PROFIT AUTO-CLOSE | result=",(ok?"REQUEST_ACCEPTED":"FAILED_RETRY")," ticket=",ticket," symbol=",sym," side=",(type==OP_BUY?"BUY":"SELL")," netBeforeUSD=",DoubleToString(net,4)," threshold=-0.50 seconds=",elapsed," error=",err);
  if(ok && GlobalVariableCheck(key)) GlobalVariableDel(key);
 }
 return allowEntries;
}

void ManageAdaptiveSLTP()
{
   if(!InpAdaptiveSLTPEnabled || !IsTradeAllowed() || IsTradeContextBusy()) return;
   int tf=(InpAdaptiveSLTPTimeframe==PERIOD_CURRENT?Period():(int)InpAdaptiveSLTPTimeframe);
   datetime now=TimeCurrent();

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;

      int ticket=OrderTicket();
      string sym=OrderSymbol();
      double floatingNet=OrderProfit()+OrderSwap()+OrderCommission();
      if(floatingNet<=InpAdaptiveSLTPMinNetProfitUSD)
      {
         string profitGateKey=StringFormat("BiteySLTPProfitGate_%d",ticket);
         double lastGateDiag=(GlobalVariableCheck(profitGateKey)?GlobalVariableGet(profitGateKey):0.0);
         if(now-(datetime)lastGateDiag>=60 || lastGateDiag<=0)
         {
            Print("SLTP PROFIT GATE | ticket=",ticket," symbol=",sym,
               " floatingNetUSD=",DoubleToString(floatingNet,2),
               " requiredNetUSD>",DoubleToString(InpAdaptiveSLTPMinNetProfitUSD,2),
               " action=NO_ADAPTIVE_MODIFICATION reason=NOT_IN_NET_PROFIT");
            GlobalVariableSet(profitGateKey,(double)now);
         }
         continue;
      }
      // Profit protection has priority over the three-candle trailing confirmation.
      // The closed-candle confirmation remains mandatory for TP extension only; a qualifying
      // net-profitable position may still tighten its SL to break-even/lock/trailing levels.
      bool favorableCandlesConfirmed=ThreeClosedCandlesConfirmFavorableMove(sym,tf,type);
      if(!favorableCandlesConfirmed)
      {
         string candleGateKey=StringFormat("BiteySLTP3CandleGate_%d",ticket);
         double lastCandleGate=(GlobalVariableCheck(candleGateKey)?GlobalVariableGet(candleGateKey):0.0);
         if(now-(datetime)lastCandleGate>=60 || lastCandleGate<=0)
         {
            Print("SLTP TRAILING CONFIRMATION PENDING | ticket=",ticket," symbol=",sym,
                  " reason=THREE_CLOSED_FAVORABLE_CANDLES_NOT_CONFIRMED",
                  " side=",(type==OP_BUY?"BUY":"SELL")," timeframe=",tf,
                  " floatingNetUSD=",DoubleToString(floatingNet,2),
                  " action=ALLOW_PROFIT_LOCK_SL_CHECK; BLOCK_TP_EXTENSION_ONLY");
            GlobalVariableSet(candleGateKey,(double)now);
         }
      }
      double point=MarketInfo(sym,MODE_POINT);
      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      if(point<=0 || digits<0 || bid<=0 || ask<=0 || ask<bid)
      {
         Print("SLTP SUPERVISION SKIPPED | ticket=",ticket," symbol=",sym,
               " reason=INVALID_MARKET_QUOTE_OR_SYMBOL_SPEC bid=",DoubleToString(bid,digits),
               " ask=",DoubleToString(ask,digits));
         continue;
      }
      double atr=iATR(sym,tf,InpATRPeriod,1);
      if(atr<=0)
      {
         Print("SLTP SUPERVISION SKIPPED | ticket=",ticket," symbol=",sym,
               " reason=ATR_UNAVAILABLE timeframe=",tf);
         continue;
      }
      double emaFast=iMA(sym,tf,20,0,MODE_EMA,PRICE_CLOSE,1);
      double emaSlow=iMA(sym,tf,50,0,MODE_EMA,PRICE_CLOSE,1);
      double close1=iClose(sym,tf,1);
      bool bullContinuation=(close1>emaFast && emaFast>emaSlow);
      bool bearContinuation=(close1<emaFast && emaFast<emaSlow);
      int stopLevel=(int)MarketInfo(sym,MODE_STOPLEVEL);
      int freezeLevel=(int)MarketInfo(sym,MODE_FREEZELEVEL);
      double minDistance=MathMax(stopLevel,freezeLevel)*point;

      double open=OrderOpenPrice(), oldSL=OrderStopLoss(), oldTP=OrderTakeProfit();
      double price=(type==OP_BUY?bid:ask);
      double favorable=(type==OP_BUY?price-open:open-price);
      double newSL=oldSL, newTP=oldTP;
      string slReason="UNCHANGED", tpReason="UNCHANGED";

      if(favorable>=InpBreakEvenTriggerATR*atr)
      {
         double be=(type==OP_BUY?open+InpBreakEvenLockATR*atr:open-InpBreakEvenLockATR*atr);
         if(type==OP_BUY)
         {
            if(newSL<=0 || be>newSL+InpSLTPMinChangeATR*atr) { newSL=be; slReason="BREAK_EVEN_PROFIT_LOCK"; }
         }
         else
         {
            if(newSL<=0 || be<newSL-InpSLTPMinChangeATR*atr) { newSL=be; slReason="BREAK_EVEN_PROFIT_LOCK"; }
         }
      }
      if(favorable>=InpTrailTriggerATR*atr)
      {
         double trail=(type==OP_BUY?bid-InpTrailDistanceATR*atr:ask+InpTrailDistanceATR*atr);
         if(type==OP_BUY)
         {
            if(newSL<=0 || trail>newSL+InpSLTPMinChangeATR*atr) { newSL=trail; slReason="ATR_TRAILING_TIGHTEN"; }
         }
         else
         {
            if(newSL<=0 || trail<newSL-InpSLTPMinChangeATR*atr) { newSL=trail; slReason="ATR_TRAILING_TIGHTEN"; }
         }
      }

      // Extend TP only after favorable movement and a closed-bar trend confirmation.
      if(favorableCandlesConfirmed && favorable>=InpTPExtendTriggerATR*atr && ((type==OP_BUY && bullContinuation)||(type==OP_SELL && bearContinuation)))
      {
         double candidateTP=(type==OP_BUY?bid+InpTPExtendDistanceATR*atr:ask-InpTPExtendDistanceATR*atr);
         if(type==OP_BUY)
         {
            if(oldTP<=0 || candidateTP>oldTP+InpSLTPMinChangeATR*atr) { newTP=candidateTP; tpReason="TREND_CONFIRMED_TP_EXTENSION"; }
         }
         else
         {
            if(oldTP<=0 || candidateTP<oldTP-InpSLTPMinChangeATR*atr) { newTP=candidateTP; tpReason="TREND_CONFIRMED_TP_EXTENSION"; }
         }
      }

      // Never loosen an existing protective level.
      if(type==OP_BUY && oldSL>0 && newSL<oldSL) newSL=oldSL;
      if(type==OP_SELL && oldSL>0 && newSL>oldSL) newSL=oldSL;
      if(type==OP_BUY && oldTP>0 && newTP<oldTP) newTP=oldTP;
      if(type==OP_SELL && oldTP>0 && newTP>oldTP) newTP=oldTP;
      newSL=(newSL>0?NormalizeDouble(newSL,digits):0);
      newTP=(newTP>0?NormalizeDouble(newTP,digits):0);

      bool slChanged=(MathAbs(newSL-oldSL)>=point*0.5);
      bool tpChanged=(MathAbs(newTP-oldTP)>=point*0.5);
      if(!slChanged && !tpChanged)
      {
         // Explain why the manager is idle without flooding the Journal.
         string diagKey=StringFormat("BiteySLTPDiag_%d",ticket);
         double lastDiag=(GlobalVariableCheck(diagKey)?GlobalVariableGet(diagKey):0.0);
         if(now-(datetime)lastDiag>=60 || lastDiag<=0)
         {
            Print("SLTP SUPERVISION DECISION | ticket=",ticket," symbol=",sym,
               " side=",(type==OP_BUY?"BUY":"SELL")," open=",DoubleToString(open,digits),
               " marketPrice=",DoubleToString(price,digits)," favorableDistance=",DoubleToString(favorable,digits),
               " favorableATR=",DoubleToString(favorable/atr,2)," ATR=",DoubleToString(atr,digits),
               " BEtriggerATR=",DoubleToString(InpBreakEvenTriggerATR,2),
               " trailTriggerATR=",DoubleToString(InpTrailTriggerATR,2),
               " TPextendTriggerATR=",DoubleToString(InpTPExtendTriggerATR,2),
               " trendConfirmed=",((type==OP_BUY?bullContinuation:bearContinuation)?"true":"false"),
               " SLAction=",slReason," TPAction=",tpReason," result=NO_CHANGE_THRESHOLD_OR_TREND_NOT_MET");
            GlobalVariableSet(diagKey,(double)now);
         }
         continue;
      }

      // Enforce at most one successful adaptive SL/TP modification per ticket per newly closed
      // management-timeframe candle. The three-candle pattern remains true across many ticks;
      // without this bar guard the same three candles could trigger repeated modifications.
      datetime lastClosedBar=iTime(sym,tf,1);
      if(lastClosedBar<=0)
      {
         Print("SLTP MODIFY DEFERRED | ticket=",ticket," symbol=",sym,
               " reason=LAST_CLOSED_BAR_TIME_UNAVAILABLE action=KEEP_EXISTING_SLTP");
         continue;
      }
      string barModifyKey=StringFormat("BiteySLTPBarMod_%d",ticket);
      datetime lastModifiedBar=(GlobalVariableCheck(barModifyKey)?(datetime)GlobalVariableGet(barModifyKey):0);
      if(lastModifiedBar>=lastClosedBar)
      {
         // Log this reason at most once per ticket per closed bar. This only rate-limits
         // diagnostics; the safety guard still prevents repeated modifications on that bar.
         string deferDiagKey=StringFormat("BiteySLTPDeferredDiag_%d",ticket);
         datetime lastDeferredBar=(GlobalVariableCheck(deferDiagKey)?(datetime)GlobalVariableGet(deferDiagKey):0);
         if(lastDeferredBar<lastClosedBar)
         {
            Print("SLTP MODIFY DEFERRED | ticket=",ticket," symbol=",sym,
                  " reason=ALREADY_MODIFIED_ON_THIS_CLOSED_BAR",
                  " managementTimeframe=",tf,
                  " lastClosedBar=",TimeToString(lastClosedBar,TIME_DATE|TIME_MINUTES),
                  " action=KEEP_EXISTING_SLTP_UNTIL_NEXT_CLOSED_BAR");
            GlobalVariableSet(deferDiagKey,(double)lastClosedBar);
         }
         continue;
      }

      // Per-ticket cooldown prevents one position blocking management of another.
      string cooldownKey=StringFormat("BiteySLTPMod_%d",ticket);
      double lastModify=(GlobalVariableCheck(cooldownKey)?GlobalVariableGet(cooldownKey):0.0);
      if(lastModify>0 && now-(datetime)lastModify<InpSLTPModifyCooldownSeconds)
      {
         Print("SLTP MODIFY DEFERRED | ticket=",ticket," symbol=",sym," reason=TICKET_COOLDOWN",
               " remainingSeconds=",InpSLTPModifyCooldownSeconds-(now-(datetime)lastModify),
               " oldSL=",DoubleToString(oldSL,digits)," candidateSL=",DoubleToString(newSL,digits),
               " oldTP=",DoubleToString(oldTP,digits)," candidateTP=",DoubleToString(newTP,digits));
         continue;
      }

      bool slValid=true, tpValid=true;
      if(newSL>0)
      {
         if(type==OP_BUY && (newSL>=bid-minDistance || newSL>=bid)) slValid=false;
         if(type==OP_SELL && (newSL<=ask+minDistance || newSL<=ask)) slValid=false;
      }
      if(newTP>0)
      {
         if(type==OP_BUY && newTP<=ask+minDistance) tpValid=false;
         if(type==OP_SELL && newTP>=bid-minDistance) tpValid=false;
      }
      if(!slValid) { newSL=oldSL; slChanged=false; slReason="BLOCKED_STOP_FREEZE_DISTANCE"; }
      if(!tpValid) { newTP=oldTP; tpChanged=false; tpReason="BLOCKED_STOP_FREEZE_DISTANCE"; }
      if(!slChanged && !tpChanged)
      {
         Print("SLTP MODIFY SKIPPED | ticket=",ticket," symbol=",sym," reason=BROKER_STOP_FREEZE_DISTANCE",
               " side=",(type==OP_BUY?"BUY":"SELL")," bid=",DoubleToString(bid,digits)," ask=",DoubleToString(ask,digits),
               " oldSL=",DoubleToString(oldSL,digits)," oldTP=",DoubleToString(oldTP,digits));
         continue;
      }
      if(type==OP_BUY && oldSL>0 && newSL<oldSL) newSL=oldSL;
      if(type==OP_SELL && oldSL>0 && newSL>oldSL) newSL=oldSL;
      ResetLastError();
      bool ok=OrderModify(ticket,open,newSL,newTP,0,clrNONE);
      int err=(ok?0:GetLastError());
      GlobalVariableSet(cooldownKey,(double)now);
      double readSL=-1,readTP=-1;
      bool readOK=OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES);
      if(readOK) { readSL=OrderStopLoss(); readTP=OrderTakeProfit(); }
      bool modifyConfirmed=(ok && readOK && MathAbs(readSL-newSL)<point*1.5 && MathAbs(readTP-newTP)<point*1.5);
      if(modifyConfirmed)
         GlobalVariableSet(barModifyKey,(double)lastClosedBar);
      Print("SLTP MODIFY AUDIT | ticket=",ticket," symbol=",sym," magic=",InpMagic,
            " side=",(type==OP_BUY?"BUY":"SELL")," lots=",DoubleToString(OrderLots(),3),
            " open=",DoubleToString(open,digits)," bid=",DoubleToString(bid,digits)," ask=",DoubleToString(ask,digits),
            " favorableDistance=",DoubleToString(favorable,digits)," ATR=",DoubleToString(atr,digits),
            " floatingNetUSD=",DoubleToString(floatingNet,2),
            " threeClosedCandlesConfirmed=true timeframe=",tf,
            " profitGateUSD>",DoubleToString(InpAdaptiveSLTPMinNetProfitUSD,2),
            " oldSL=",DoubleToString(oldSL,digits)," requestedSL=",DoubleToString(newSL,digits)," slReason=",slReason,
            " oldTP=",DoubleToString(oldTP,digits)," requestedTP=",DoubleToString(newTP,digits)," tpReason=",tpReason,
            " modifyOK=",(ok?"true":"false")," error=",err," readbackOK=",(readOK?"true":"false"),
            " confirmedSL=",(readOK?DoubleToString(readSL,digits):"N/A")," confirmedTP=",(readOK?DoubleToString(readTP,digits):"N/A"),
            " monotonicSL=",((!readOK || oldSL<=0 || (type==OP_BUY?readSL>=oldSL-point*0.5:readSL<=oldSL+point*0.5))?"true":"false"),
            " modifiedBar=",TimeToString(lastClosedBar,TIME_DATE|TIME_MINUTES),
            " result=",(modifyConfirmed?"MODIFY_CONFIRMED":"CHECK_SERVER_READBACK"));
   }
}

void AuditManagedPositionSLTPReadback()
{
   int seen=0, missingStops=0, missingTargets=0; double aggregate=0.0; bool riskKnown=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      seen++;
      double sl=OrderStopLoss(), tp=OrderTakeProfit();
      double risk=(sl>0.0?EstimateOrderRiskUSD(OrderSymbol(),OrderLots(),MathAbs(OrderOpenPrice()-sl)):-1.0);
      if(sl<=0.0) missingStops++;
      if(tp<=0.0) missingTargets++;
      if(risk<0.0) riskKnown=false; else aggregate+=risk;
      int digits=(int)MarketInfo(OrderSymbol(),MODE_DIGITS);
      Print("MANAGED POSITION SLTP AUDIT | ticket=",OrderTicket()," symbol=",OrderSymbol()," magic=",OrderMagicNumber(),
         " side=",(OrderType()==OP_BUY?"BUY":"SELL")," lots=",DoubleToString(OrderLots(),3),
         " open=",DoubleToString(OrderOpenPrice(),digits)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits),
         " stopRiskUSD=",(risk>=0.0?DoubleToString(risk,2):"UNKNOWN"),
         " floatingNetUSD=",DoubleToString(OrderProfit()+OrderSwap()+OrderCommission(),2),
         " status=",(sl<=0.0?"CRITICAL_NO_SL":(tp<=0.0?"WARNING_NO_TP":"READBACK_PRESENT")),
         " note=READ_ONLY_AUDIT_NO_MODIFICATION_ATTEMPTED");
   }
   Print("MANAGED POSITION SLTP AUDIT SUMMARY | magic=",InpMagic," positionsSeen=",seen," missingSL=",missingStops,
      " missingTP=",missingTargets," aggregateStopRiskUSD=",(riskKnown?DoubleToString(aggregate,2):"UNKNOWN"),
      " capUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),2)," result=",(seen==0?"NO_MANAGED_POSITIONS":(missingStops>0?"CRITICAL_MISSING_SL":(missingTargets>0?"WARNING_MISSING_TP":"READBACK_AUDIT_COMPLETE"))));
}

// Strict invariant repair: if older EA versions or manual actions left duplicate
// managed positions on the same canonical asset, retain the best model-qualified
// incumbent and close the other managed duplicates. Never opens a replacement here.
void EnforceOnePositionPerCanonicalAsset()
{
   int tickets[200]; string symbols[200]; string keys[200]; int types[200];
   double nets[200]; double priorities[200]; int total=0;
   // Initialize every numeric slot before any selection/comparison. The arrays
   // are fixed-size in MQL4, and explicit initialization avoids compiler warnings
   // and makes fallback values deterministic if a scan exits early.
   ArrayInitialize(tickets,-1);
   ArrayInitialize(types,-1);
   ArrayInitialize(nets,0.0);
   ArrayInitialize(priorities,-1000000.0);
   for(int i=OrdersTotal()-1;i>=0 && total<200;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      string key=CanonicalAssetKey(OrderSymbol());
      if(key=="") continue;
      tickets[total]=OrderTicket(); symbols[total]=OrderSymbol(); keys[total]=key; types[total]=OrderType();
      nets[total]=OrderProfit()+OrderSwap()+OrderCommission();
      string sig="NONE",why=""; int bars=0;
      double technical=CrossAssetTechnicalScore(OrderSymbol(),InpCrossAssetTimeframe,sig,why,bars);
      double rank=-1000000.0;
      string posDir=(OrderType()==OP_BUY?"BUY":"SELL");
      if(technical>0.0 && sig==posDir)
      {
         int n=0,hn=0; double wr=0.0,avgR=-999.0,hwr=0.0,havgR=-999.0; string histWhy="";
         if(CrossAssetHistoricalEvidence(OrderSymbol(),InpCrossAssetTimeframe,posDir,n,wr,avgR,histWhy,hn,hwr,havgR) &&
            n>=InpCrossAssetMinHistorySamples && wr>=InpCrossAssetMinHistoryWinRate && avgR>InpCrossAssetMinHistoryAvgR &&
            hn>=InpCrossAssetMinHoldoutSamples && hwr>=InpCrossAssetMinHoldoutWinRate && havgR>InpCrossAssetMinHoldoutAvgR)
            rank=CrossAssetOpportunityPriority(technical,wr,avgR,hwr,havgR);
         else rank=technical*0.01; // directional signal present but not fully history-qualified
      }
      priorities[total]=rank;
      total++;
   }

   bool handled[200]; ArrayInitialize(handled,false);
   for(int a=0;a<total;a++)
   {
      if(handled[a] || tickets[a]<0) continue;
      int group[200]; int count=0;
      ArrayInitialize(group,-1);
      for(int b=a;b<total && count<200;b++)
      {
         if(!handled[b] && tickets[b]>=0 && keys[b]==keys[a])
         { group[count]=b; count++; handled[b]=true; }
      }
      if(count<=1) continue;
      int keep=group[0];
      for(int g=1;g<count;g++)
      {
         int idx=group[g];
         // Prefer model-qualified opportunity; if scores tie, preserve the position
         // with the better current net result. This is a deterministic tie-breaker,
         // not a claim that floating P/L predicts future profitability.
         if(priorities[idx]>priorities[keep]+0.0001 ||
            (MathAbs(priorities[idx]-priorities[keep])<=0.0001 && nets[idx]>nets[keep])) keep=idx;
      }
      Print("CANONICAL POSITION CONSOLIDATION | asset=",keys[a]," detectedPositions=",count,
            " keepTicket=",tickets[keep]," keepSymbol=",symbols[keep]," keepDirection=",(types[keep]==OP_BUY?"BUY":"SELL"),
            " keepModelPriority=",DoubleToString(priorities[keep],3)," keepFloatingNetUSD=",DoubleToString(nets[keep],2),
            " | closing only duplicate managed tickets; no replacement entry is sent.");
      for(int c=0;c<count;c++)
      {
         int idx2=group[c]; if(idx2==keep) continue;
         if(!OrderSelect(tickets[idx2],SELECT_BY_TICKET) || OrderCloseTime()>0) continue;
         string sym=OrderSymbol(); int typ=OrderType(); double lots=OrderLots();
         double px=(typ==OP_BUY?MarketInfo(sym,MODE_BID):MarketInfo(sym,MODE_ASK));
         int dg=(int)MarketInfo(sym,MODE_DIGITS);
         if(px<=0.0 || MarketInfo(sym,MODE_TRADEALLOWED)==0)
         {
            Print("CANONICAL POSITION CONSOLIDATION BLOCK | asset=",keys[a]," duplicateTicket=",tickets[idx2],
                  " reason=INVALID_CLOSE_PRICE_OR_SYMBOL_DISABLED | no new entry permitted while duplicate remains.");
            continue;
         }
         px=NormalizeDouble(px,dg); ResetLastError();
         bool closed=OrderClose(tickets[idx2],lots,px,InpSlippagePoints,clrNONE);
         if(closed)
            Print("CANONICAL POSITION CONSOLIDATION RESULT | asset=",keys[a]," action=CLOSED_DUPLICATE",
                  " closedTicket=",tickets[idx2]," closedSymbol=",sym," closedNetUSD=",DoubleToString(nets[idx2],2),
                  " retainedTicket=",tickets[keep]," reason=ONE_POSITION_PER_CANONICAL_ASSET");
         else
            Print("CANONICAL POSITION CONSOLIDATION ERROR | asset=",keys[a]," duplicateTicket=",tickets[idx2],
                  " error=",GetLastError()," description=",TradeErrorDescription(GetLastError()),
                  " | no new entry permitted while duplicate remains.");
      }
   }
}

// Read-only inventory: the supervisor manages all open market positions with this magic,
// including positions opened by older EA versions, because source version is not used as a filter.
void AuditExistingPositionSupervision(string trigger)
{
   int managed=0, missingSL=0, duplicatePositionRows=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      managed++;
      string sym=OrderSymbol();
      string asset=CanonicalAssetKey(sym);
      bool hasSL=(OrderStopLoss()>0.0);
      if(!hasSL) missingSL++;
      int auditedTicket=OrderTicket();
      int canonicalCount=0;
      for(int j=OrdersTotal()-1;j>=0;j--)
      {
         if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
         if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
         if(CanonicalAssetKey(OrderSymbol())==asset) canonicalCount++;
      }
      // The nested OrderSelect loop changes MT4's currently selected order; restore the
      // audited ticket before reading its fields for the log.
      if(!OrderSelect(auditedTicket,SELECT_BY_TICKET) || OrderCloseTime()>0) continue;
      if(canonicalCount>1) duplicatePositionRows++;
      double riskUSD=-1.0;
      if(hasSL) riskUSD=EstimateOrderRiskUSD(sym,OrderLots(),MathAbs(OrderOpenPrice()-OrderStopLoss()));
      Print("EXISTING POSITION SUPERVISION AUDIT | trigger=",trigger,
            " ticket=",OrderTicket()," symbol=",sym," canonicalAsset=",asset,
            " magic=",OrderMagicNumber()," side=",(OrderType()==OP_BUY?"BUY":"SELL"),
            " lots=",DoubleToString(OrderLots(),4),
            " openedAt=",TimeToString(OrderOpenTime(),TIME_DATE|TIME_MINUTES),
            " sourceVersion=UNKNOWN_OR_PREVIOUS_VERSION",
            " SL=",DoubleToString(OrderStopLoss(),(int)MarketInfo(sym,MODE_DIGITS)),
            " TP=",DoubleToString(OrderTakeProfit(),(int)MarketInfo(sym,MODE_DIGITS)),
            " stopRiskEstimateUSD=",(riskUSD>=0.0?DoubleToString(riskUSD,4):"UNAVAILABLE_NO_SL_OR_SYMBOL_DATA"),
            " floatingNetUSD=",DoubleToString(OrderProfit()+OrderSwap()+OrderCommission(),4),
            " canonicalPositionsForAsset=",canonicalCount,
            " supervisionPath=MANAGE_ADAPTIVE_SLTP_AND_READBACK_AUDIT",
            " status=",(hasSL?"RECOGNIZED_FOR_SUPERVISION":"RECOGNIZED_BUT_MISSING_STOP_LOSS"));
   }
   double portfolioRiskSnapshot=PortfolioOpenRiskUSD();
   Print("PORTFOLIO EVIDENCE SNAPSHOT | schema=1 trigger=",trigger,
         " timestamp=",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
         " accountCurrency=",AccountCurrency(),
         " fixedOperatingCapitalUSD=",DoubleToString(EffectiveOperatingCapitalUSD(),2),
         " managedMarketPositions=",managed,
         " configuredMaximum=",EffectiveMaxOpenTrades(),
         " freeSlots=",MathMax(0,EffectiveMaxOpenTrades()-CountOpenTrades()),
         " aggregateOpenStopRiskUSD=",(portfolioRiskSnapshot>=0.0?DoubleToString(portfolioRiskSnapshot,4):"UNKNOWN_FAIL_CLOSED"),
         " aggregateRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),4),
         " dailyNetUSD=",DoubleToString(TodayNetProfit(),4),
         " dailyLossLimitUSD=",DoubleToString(EffectiveDailyLossLimitUSD(),2),
         " missingSLPositions=",missingSL," duplicatedCanonicalPositionRows=",duplicatePositionRows,
         " evidenceScope=ALL_OPEN_MARKET_ORDERS_MATCHING_MAGIC; each ticket is logged above");
   Print("EXISTING POSITION SUPERVISION SUMMARY | trigger=",trigger,
         " managedMarketPositions=",managed," configuredMaximum=",EffectiveMaxOpenTrades(),
         " missingSLPositions=",missingSL," duplicatedCanonicalPositionRows=",duplicatePositionRows,
         " action=ONE_POSITION_PER_CANONICAL_ASSET_GUARD_RUNS_EACH_TIMER",
         " | recognition audit is not proof of successful broker-side modification.");
}

void OnTimer()
{
   // Run before scans and cross-asset execution so a negative open trade is handled
   // before any new order can be considered on this timer pass.
   if(!EnforcePersistentNegativeProfitClose())
   {
      EnforceOpenPositionRiskCapAdaptive();
      ManageAdaptiveSLTP();
      return;
   }
   static datetime lastInheritanceAudit=0;
   if(lastInheritanceAudit==0 || TimeCurrent()-lastInheritanceAudit>=30)
   {
      lastInheritanceAudit=TimeCurrent();
      AuditExistingPositionSupervision("TIMER_START");
   }
   EnforceOpenPositionRiskCapAdaptive();
   ManageAdaptiveSLTP();
   static datetime lastManagedAudit=0;
   if(lastManagedAudit==0 || TimeCurrent()-lastManagedAudit>=30)
   {
      lastManagedAudit=TimeCurrent();
      AuditManagedPositionSLTPReadback();
   }
   ScanMarketWatchAssets(false);
   EnforceOnePositionPerCanonicalAsset();
   datetime crossNow=TimeCurrent();
   int crossInterval=MathMax(30,InpSignalRecheckSeconds);
   if(g_lastCrossAssetExecutionTime==0 || (crossNow-g_lastCrossAssetExecutionTime)>=crossInterval)
   {
      g_lastCrossAssetExecutionTime=crossNow;
      // SL/TP-only policy: asset rotation by closing/reopening is disabled.
      ExecuteCrossAssetRankedCandidates();
   }
   // A timer never authorizes trading from stale quotes. Position supervision is
   // frequent; full model evaluation is throttled separately to avoid excess churn.
   datetime quoteServerTime=(datetime)MarketInfo(Symbol(),MODE_TIME);
   datetime quoteLocalEstimate=(datetime)(quoteServerTime+g_serverLocalOffsetSeconds);
   int quoteAgeSeconds=(quoteServerTime>0 ? (int)(TimeLocal()-quoteLocalEstimate) : 999999);
   bool freshQuote=(quoteAgeSeconds>=0 && quoteAgeSeconds<=120);

   if(freshQuote && IsAllowedMultiAssetSymbol() && IsConnected())
   {
      // Lightweight position-management pass every timer tick (e.g. every 5 seconds).
      int timerClosed=ManageOpenTrades();
      if(timerClosed>0)
      {
         g_lastEntryAttemptBarTime=iTime(Symbol(),Period(),0); // No same-bar re-entry immediately after a time exit.
         Print("TIMER POSITION MANAGEMENT | closedByTime=",timerClosed,
               " | action=position closed; same-bar re-entry suppressed; all risk gates remain active.");
      }

      int signalInterval=InpSignalRecheckSeconds;
      if(signalInterval<5) signalInterval=5;
      datetime nowLocal=TimeLocal();
      if(g_lastTimerSignalEvaluation==0 || (nowLocal-g_lastTimerSignalEvaluation)>=signalInterval)
      {
         g_lastTimerSignalEvaluation=nowLocal;
         ProcessEngine(true);
      }
   }

   datetime now=TimeLocal();
   if(g_lastStatusLogTime>0 && (now-g_lastStatusLogTime)<60) return;
   g_lastStatusLogTime=now;
   int required=InpTrendEMA+InpDonchianPeriod+InpForwardHorizonBars+20;
   Print("PROCESS HEARTBEAT | connected=",(IsConnected()?"true":"false"),
         " | symbol=",Symbol()," timeframe=",Period()," bars=",Bars," requiredBars=",required,
         " | currentBar=",(iTime(Symbol(),Period(),0)>0?TimeToString(iTime(Symbol(),Period(),0),TIME_DATE|TIME_MINUTES):"unavailable"),
         " | lastEvaluatedBar=",(g_lastBarTime>0?TimeToString(g_lastBarTime,TIME_DATE|TIME_MINUTES):"none"),
         " | quoteAgeSeconds=",quoteAgeSeconds,
         " | bid=",DoubleToString(Bid,Digits)," ask=",DoubleToString(Ask,Digits),
         " spreadPoints=",(int)MarketInfo(Symbol(),MODE_SPREAD),
         " | terminalTradeAllowed=",(IsTradeAllowed()?"true":"false"),
         " | accountCurrency=",AccountCurrency()," effectiveCapitalUSD=",DoubleToString(EffectiveOperatingCapitalUSD(),2),
         " | action=position supervision on timer; model recheck throttled; closed-bar evidence and risk gates remain active.");
}

void ProcessEngine(bool timerInvocation)
{
   if(timerInvocation)
   {
      datetime quoteServerTime=(datetime)MarketInfo(Symbol(),MODE_TIME);
      datetime quoteLocalEstimate=(datetime)(quoteServerTime+g_serverLocalOffsetSeconds);
      int quoteAgeSeconds=(quoteServerTime>0 ? (int)(TimeLocal()-quoteLocalEstimate) : 999999);
      if(quoteAgeSeconds<0 || quoteAgeSeconds>120) return; // Never trade on a stale timer-only quote.
   }
   if(!IsAllowedMultiAssetSymbol()) return;
   int requiredBars=InpTrendEMA+InpDonchianPeriod+InpForwardHorizonBars+20;
   if(Bars < requiredBars)
   {
      if(g_lastBarsGateLogged<0 || Bars!=g_lastBarsGateLogged || g_lastStatusLogTime==0 || (TimeLocal()-g_lastStatusLogTime)>=60)
      {
         Print("PROCESS DATA_GATE | rejected=true | reason=INSUFFICIENT_HISTORY_BARS | bars=",Bars,
               " requiredBars=",requiredBars," | action=NO_ORDER; load more chart history and wait for valid ticks.");
         g_lastBarsGateLogged=Bars;
         g_lastStatusLogTime=TimeLocal();
      }
      return;
   }
   if(!IsConnected())
   {
      if(g_lastStatusLogTime==0 || (TimeLocal()-g_lastStatusLogTime)>=60)
      {
         Print("PROCESS DATA_GATE | rejected=true | reason=TERMINAL_DISCONNECTED | action=NO_ORDER until connection returns.");
         g_lastStatusLogTime=TimeLocal();
      }
      return;
   }
   datetime barTime=iTime(Symbol(),Period(),0);
   UpdateRiskGovernor();
   if(barTime==0)
   {
      if(g_lastStatusLogTime==0 || (TimeLocal()-g_lastStatusLogTime)>=60)
      {
         Print("PROCESS DATA_GATE | rejected=true | reason=CURRENT_BAR_TIME_UNAVAILABLE | action=NO_ORDER.");
         g_lastStatusLogTime=TimeLocal();
      }
      return;
   }
   bool isNewBar=(barTime!=g_lastBarTime);
   if(!isNewBar && !timerInvocation) return;
   if(isNewBar)
   {
      g_lastBarTime=barTime;
      Print("PROCESS NEW BAR | barTime=",TimeToString(barTime,TIME_DATE|TIME_MINUTES),
            " | closedBarTime=",TimeToString(iTime(Symbol(),Period(),1),TIME_DATE|TIME_MINUTES),
            " | bars=",Bars," | bid=",DoubleToString(Bid,Digits)," ask=",DoubleToString(Ask,Digits),
            " | spreadPoints=",(int)MarketInfo(Symbol(),MODE_SPREAD),
            " | nextStep=manage positions then evaluate sixteen symbol-scoped models.");
   }
   else
   {
      Print("PERIODIC MODEL RECHECK | barTime=",TimeToString(barTime,TIME_DATE|TIME_MINUTES),
            " | closedBarEvidence remains based on completed candles; current quotes/spread/position state refreshed.");
   }
   int closedByTime=ManageOpenTrades();
   if(closedByTime>0)
   {
      // Order management is completed first. Suppress same-bar re-entry after a time exit.
      g_lastEntryAttemptBarTime=barTime;
      SyncClosedTrades();
      Print("ENTRY SKIPPED | time exit processed; same-bar re-entry suppressed until a new bar.");
      return;
   }
   EvaluateEngine();
   // Send realized-trade telemetry only after the current bar's decision and any
   // eligible order attempt. WebRequest is synchronous in MQL4, so keep it last.
   SyncClosedTrades();
}

void OnTick()
{
   if(!EnforcePersistentNegativeProfitClose()) { ManageAdaptiveSLTP(); return; }
   ManageAdaptiveSLTP();
   ProcessEngine(false);
}

void EnsureCSVHeader()
{
   int h=FileOpen("Bitey_SOLUSD_Evidence_v1_12.csv",FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) { Print("CSV warning: cannot open evidence file. Error=",GetLastError()); return; }
   if(FileSize(h)==0)
      FileWrite(h,"time","symbol","timeframe","model","direction","samples","win_rate","avg_R","signal","decision");
   FileClose(h);
}

void WriteEvidenceRow(string model,string direction,DirectionEvidence &e,int signal,string decision)
{
   if(!InpWriteCSV) return;
   int h=FileOpen("Bitey_SOLUSD_Evidence_v1_12.csv",FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),IntegerToString(Period()),model,direction,
             IntegerToString(e.samples),DoubleToString(e.winRate,4),DoubleToString(e.avgR,4),IntegerToString(signal),decision);
   FileClose(h);
}

// Escape JSON strings, including whitespace/control characters, before embedding them
// in outbound telemetry. Backslashes must be escaped before other sequences.
string JsonEscape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, CharToString(8), "\\b");
   StringReplace(value, CharToString(12), "\\f");
   StringReplace(value, "\n", "\\n");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\t", "\\t");
   StringReplace(value, CharToString(11), "\\u000B");
   return value;
}

string JsonBool(bool value) { return value ? "true" : "false"; }

// Serialize a single evidence record through a reference. Keeping field access
// inside this helper avoids MQL4's false-positive warning on struct arrays.
bool EvidencePass(DirectionEvidence &e);

string EvidenceToJson(DirectionEvidence &e)
{
   bool passed=EvidencePass(e);
   return "{\"n\":"+IntegerToString(e.samples)+
          ",\"win_rate\":"+DoubleToString(e.winRate,4)+
          ",\"avg_r\":"+DoubleToString(e.avgR,6)+
          ",\"pass\":"+JsonBool(passed)+"}";
}

string CurrentRegime(double closePrice,double emaTrend,double adx)
{
   if(adx < InpTrendADXMin) return "RANGE_OR_WEAK_TREND";
   if(closePrice > emaTrend) return "TREND_UP";
   if(closePrice < emaTrend) return "TREND_DOWN";
   return "TRANSITION";
}

void SendSbtSnapshot(int decision,string decisionText,int buyVotes,int sellVotes,
                     int trend,int momentum,int donchian,int meanrev,int strictRange,
                     string modelsJson,string bestStrategy,double bestScore,
                     double closePrice,double emaFast,double emaSlow,double emaTrend,
                     double rsi,double adx,double atr,bool riskGateAllowed,
                     string riskGateReason,string executionResult)
{
   if(!InpSbtTelemetryEnabled || StringLen(InpSbtTelemetryURL)==0) return;

   RefreshRates();
   string direction = decision>0 ? "BUY" : (decision<0 ? "SELL" : "HOLD");
   string mode = InpMode==AUTO_EXECUTION ? "AUTO_EXECUTION" : "OBSERVE_ONLY";
   string accountMode = ReportedAccountMode();
   double riskBudget = EffectiveRiskBudgetUSD();
   double spreadPoints = MarketInfo(Symbol(),MODE_SPREAD);

   string body="{";
   body+="\"source\":\"Bitey_SBT_MultiAsset_v1_74_0\",";
   body+="\"symbol\":\""+JsonEscape(Symbol())+"\",";
   body+="\"timeframe\":\""+IntegerToString(Period())+"\",";
   body+="\"chart_timeframe\":\""+IntegerToString(Period())+"\",";
   body+="\"timestamp\":\""+JsonEscape(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS))+"\",";
   body+="\"mode\":\""+mode+"\",";
   body+="\"execution_enabled\":"+JsonBool(InpMode==AUTO_EXECUTION)+",";
   body+="\"report_type\":\"live_snapshot\",";
   body+="\"regime\":\""+CurrentRegime(closePrice,emaTrend,adx)+"\",";
   body+="\"best_strategy\":\""+JsonEscape(bestStrategy)+"\",";
   body+="\"best_score\":"+DoubleToString(bestScore,6)+",";
   body+="\"metrics\":{";
   body+="\"engine_version\":\"1.64.0\",";
   body+="\"magic\":"+IntegerToString(InpMagic)+",";
   body+="\"decision\":\""+JsonEscape(decisionText)+"\",";
   body+="\"provisional_evidence\":"+JsonBool(g_currentProvisionalEntry)+",";
   body+="\"direction\":\""+direction+"\",";
   body+="\"buy_votes\":"+IntegerToString(buyVotes)+",";
   body+="\"sell_votes\":"+IntegerToString(sellVotes)+",";
   body+="\"signals\":{\"trend\":"+IntegerToString(trend)+",\"momentum\":"+IntegerToString(momentum)+",\"donchian\":"+IntegerToString(donchian)+",\"meanrev\":"+IntegerToString(meanrev)+",\"strict_range\":"+IntegerToString(strictRange)+"},";
   body+="\"models\":"+modelsJson+",";
   body+="\"spread_points\":"+DoubleToString(spreadPoints,1)+",";
   body+="\"risk_budget_usd\":"+DoubleToString(riskBudget,2)+",";
   body+="\"risk_request_usd\":"+DoubleToString(InpRiskPerTradeUSD,2)+",";
   body+="\"hard_risk_cap_usd\":"+DoubleToString(InpHardRiskCapUSD,2)+",";
   body+="\"operating_capital_usd\":"+DoubleToString(EffectiveOperatingCapitalUSD(),2)+",";
   body+="\"campaign_net_usd\":"+DoubleToString(g_campaignNetUSD,2)+",";
   body+="\"governor_state\":\""+GovernorStateName(g_governorState)+"\",";
   body+="\"campaign_loss_stop_usd\":"+DoubleToString(InpCampaignLossStopUSD,2)+",";
   body+="\"daily_loss_limit_usd\":"+DoubleToString(EffectiveDailyLossLimitUSD(),2)+",";
   body+="\"max_trades_per_day\":"+IntegerToString(InpMaxTradesPerDay)+",";
   body+="\"max_open_trades\":"+IntegerToString(EffectiveMaxOpenTrades())+",";
   body+="\"trades_today\":"+IntegerToString(CountTodayTrades())+",";
   body+="\"positions_open\":"+IntegerToString(CountOpenTrades())+",";
   body+="\"ema_fast\":"+DoubleToString(emaFast,Digits)+",";
   body+="\"ema_slow\":"+DoubleToString(emaSlow,Digits)+",";
   body+="\"ema_200\":"+DoubleToString(emaTrend,Digits)+",";
   body+="\"close\":"+DoubleToString(closePrice,Digits)+",";
   body+="\"rsi\":"+DoubleToString(rsi,4)+",";
   body+="\"adx\":"+DoubleToString(adx,4)+",";
   body+="\"atr\":"+DoubleToString(atr,Digits+2)+",";
   body+="\"execution_result\":\""+JsonEscape(executionResult)+"\"},";
   body+="\"strategies\":"+modelsJson+",";
   body+="\"market\":{";
   body+="\"bid\":"+DoubleToString(Bid,Digits)+",";
   body+="\"ask\":"+DoubleToString(Ask,Digits)+",";
   body+="\"close\":"+DoubleToString(closePrice,Digits)+",";
   body+="\"ema_fast\":"+DoubleToString(emaFast,Digits)+",";
   body+="\"ema_slow\":"+DoubleToString(emaSlow,Digits)+",";
   body+="\"ema_200\":"+DoubleToString(emaTrend,Digits)+",";
   body+="\"atr\":"+DoubleToString(atr,Digits+2)+",";
   body+="\"rsi\":"+DoubleToString(rsi,4)+",";
   body+="\"adx\":"+DoubleToString(adx,4)+",";
   body+="\"spread_points\":"+DoubleToString(spreadPoints,1)+"},";
   body+="\"account\":{";
   body+="\"mode\":\""+accountMode+"\",";
   body+="\"terminal_is_demo\":"+JsonBool(IsDemo())+",";
   body+="\"server\":\""+JsonEscape(AccountServer())+"\",";
   body+="\"company\":\""+JsonEscape(AccountCompany())+"\",";
   body+="\"balance\":"+DoubleToString(AccountBalance(),2)+",";
   body+="\"equity\":"+DoubleToString(AccountEquity(),2)+",";
   body+="\"currency\":\""+JsonEscape(AccountCurrency())+"\",";
   body+="\"position_count\":"+IntegerToString(CountOpenTrades())+",";
   body+="\"operational_capital_usd\":"+DoubleToString(EffectiveOperatingCapitalUSD(),2)+"},";
   body+="\"risk_gate\":{";
   body+="\"allowed\":"+JsonBool(riskGateAllowed)+",";
   body+="\"reason\":\""+JsonEscape(riskGateReason)+"\",";
   body+="\"risk_budget_usd\":"+DoubleToString(riskBudget,2)+",";
   body+="\"hard_risk_cap_usd\":"+DoubleToString(InpHardRiskCapUSD,2)+",";
   body+="\"campaign_net_usd\":"+DoubleToString(g_campaignNetUSD,2)+",";
   body+="\"governor_state\":\""+GovernorStateName(g_governorState)+"\",";
   body+="\"campaign_loss_stop_usd\":"+DoubleToString(InpCampaignLossStopUSD,2)+",";
   body+="\"daily_loss_limit_usd\":"+DoubleToString(EffectiveDailyLossLimitUSD(),2)+",";
   body+="\"scope\":\"EA symbol and magic only; not account-wide\"},";
   body+="\"learning\":{";
   body+="\"framework\":\"Q_LEARNING\",";
   body+="\"policy_key\":\"bitey_shared_trading_q_v1\",";
   body+="\"learning_scope\":\"shared_bitey_ia_sbt\",";
   body+="\"experience_source\":\"realized_trade_closures\",";
   body+="\"state_id\":"+IntegerToString(BuildStateId(closePrice,emaFast,emaSlow,emaTrend,rsi,adx,atr))+",";
   body+="\"action\":\""+direction+"\",";
   body+="\"reward_available\":false,";
   body+="\"update_policy\":\"closed_trade_only_backend_owned\"},";
   body+="\"bot\":{";
   body+="\"name\":\"Bitey SBT Multi-Model Engine\",";
   body+="\"id\":\"bitey-sbt-multimodel\",";
   body+="\"version\":\"1.64.0\",";
   body+="\"magic\":"+IntegerToString(InpMagic)+",";
   body+="\"strategy\":\"ENSEMBLE\",";
   body+="\"signal\":\""+direction+"\",";
   body+="\"active\":true}}";

   char post[],result[];
    // Copy the complete UTF-8 payload, then remove StringToCharArray's trailing NUL.
    // This avoids truncating multibyte characters and excludes NUL from the HTTP body.
    int copied=StringToCharArray(body,post,0,WHOLE_ARRAY,CP_UTF8);
    if(copied>0 && ArraySize(post)>0 && post[ArraySize(post)-1]==0)
       ArrayResize(post,ArraySize(post)-1);
   string headers="Content-Type: application/json; charset=utf-8\r\n";
   if(StringLen(InpSbtToken)>0) headers+="X-MT4-Token: "+InpSbtToken+"\r\n";
   string responseHeaders="";
   ResetLastError();
   int status=WebRequest("POST",InpSbtTelemetryURL,headers,InpSbtTelemetryTimeoutMs,post,result,responseHeaders);
   int err=GetLastError();
   if(status>=200 && status<300)
      Print("SBT TELEMETRY OK | HTTP=",status," decision=",direction," result=",executionResult);
   else
   {
      if(err==4060)
         Print("SBT TELEMETRY BLOCKED BY MT4 | error=4060 ERR_FUNCTION_NOT_ALLOWED. Add the Worker origin to Tools > Options > Expert Advisors > Allow WebRequest for listed URL: https://bitey-system-bots-trading.raylerr481.workers.dev . This terminal permission cannot be enabled by EA code.");
      else if(err==12002)
         Print("SBT TELEMETRY TIMEOUT | WinINet=12002 url=",InpSbtTelemetryURL,
               " | order decision is independent of telemetry; check Worker/network latency and MT4 WebRequest allow-list.");
      else
         Print("SBT TELEMETRY ERROR | HTTP=",status," error=",err," url=",InpSbtTelemetryURL,
               " response=",CharArrayToString(result)," | telemetry is reporting-only and does not change the risk decision.");
   }
}

int BuildStateId(double closePrice,double emaFast,double emaSlow,double emaTrend,double rsi,double adx,double atr)
{
   int trendBucket=(closePrice>emaTrend?2:(closePrice<emaTrend?0:1));
   int momentumBucket=(emaFast>emaSlow?2:(emaFast<emaSlow?0:1));
   int rsiBucket=(int)MathMin(4,MathMax(0,MathFloor(rsi/20.0)));
   int adxBucket=(adx<InpTrendADXMin?0:(adx<25.0?1:2));
   double atrPct=(closePrice>0?10000.0*atr/closePrice:0.0);
   int volatilityBucket=(atrPct<5.0?0:(atrPct<10.0?1:2));
   return trendBucket*10000+momentumBucket*1000+rsiBucket*100+adxBucket*10+volatilityBucket;
}

int StrategyCode(string name)
{
   for(int i=0;i<MODEL_COUNT;i++) if(name==g_modelNames[i]) return i+1;
   return 0;
}

string StrategyFromCode(int code)
{
   if(code>=1 && code<=MODEL_COUNT) return g_modelNames[code-1];
   return "UNKNOWN";
}

string TicketGlobalKey(string suffix,int ticket)
{
   return "B38_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+"_"+IntegerToString(ticket)+"_"+suffix;
}

void StoreEntryExperience(int ticket,int direction,double actualRiskUSD)
{
   GlobalVariableSet(TicketGlobalKey("state",ticket),(double)g_currentStateId);
   GlobalVariableSet(TicketGlobalKey("model",ticket),(double)StrategyCode(g_currentBestStrategy));
   GlobalVariableSet(TicketGlobalKey("risk",ticket),actualRiskUSD);
   GlobalVariableSet(TicketGlobalKey("action",ticket),(double)(direction>0?1:-1));
}

string ExitReasonForSelectedOrder()
{
   double closePrice=OrderClosePrice();
   double sl=OrderStopLoss();
   double tp=OrderTakeProfit();
   double tolerance=MathMax(Point*3.0,MarketInfo(OrderSymbol(),MODE_TICKSIZE)*3.0);
   if(sl>0 && MathAbs(closePrice-sl)<=tolerance) return "STOP_LOSS";
   if(tp>0 && MathAbs(closePrice-tp)<=tolerance) return "TAKE_PROFIT";
   return "TIME_OR_MANUAL_OR_OTHER";
}

bool SendClosedTradeReport(int historyIndex)
{
   if(!InpSbtClosedTradeReportsEnabled || StringLen(InpSbtClosedTradeURL)<10) return false;
   if(!OrderSelect(historyIndex,SELECT_BY_POS,MODE_HISTORY)) return false;
   if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) return false;
   if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) return false;
   int ticket=OrderTicket();
   string sentKey=TicketGlobalKey("sent",ticket);
   if(GlobalVariableCheck(sentKey) && GlobalVariableGet(sentKey)>0) return true;

   double netPnl=OrderProfit()+OrderCommission()+OrderSwap();
   string stateKey=TicketGlobalKey("state",ticket);
   string modelKey=TicketGlobalKey("model",ticket);
   string riskKey=TicketGlobalKey("risk",ticket);
   string actionKey=TicketGlobalKey("action",ticket);
   bool hasEntryState=GlobalVariableCheck(stateKey) && GlobalVariableCheck(riskKey) && GlobalVariableCheck(actionKey);
   int entryState=(hasEntryState?(int)GlobalVariableGet(stateKey):0);
   int modelCode=(GlobalVariableCheck(modelKey)?(int)GlobalVariableGet(modelKey):0);
   double riskUSD=(GlobalVariableCheck(riskKey)?GlobalVariableGet(riskKey):0.0);
   double rewardR=(riskUSD>0.0?netPnl/riskUSD:0.0);
   int direction=(OrderType()==OP_BUY?1:-1);
   string side=(direction>0?"BUY":"SELL");
   int closeShift=iBarShift(Symbol(),Period(),OrderCloseTime(),false);
   if(closeShift<1) closeShift=1;
   double close1=iClose(Symbol(),Period(),closeShift);
   double emaFast=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,closeShift);
   double emaSlow=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,closeShift);
   double emaTrend=iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,closeShift);
   double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,closeShift);
   double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,closeShift);
   double atr=GetATR(closeShift);
   int nextState=BuildStateId(close1,emaFast,emaSlow,emaTrend,rsi,adx,atr);
   string model=StrategyFromCode(modelCode);
   string body="{";
   body+="\"source\":\"MT4_DESKTOP\",";
   body+="\"bot_id\":\"BITEY_SBT_MULTIMODEL\",";
   body+="\"strategy\":\""+JsonEscape(model)+"\",";
   body+="\"version\":\"1.64.0\",";
   body+="\"ticket\":"+IntegerToString(ticket)+",";
   body+="\"magic\":"+IntegerToString(OrderMagicNumber())+",";
   body+="\"symbol\":\""+JsonEscape(OrderSymbol())+"\",";
   body+="\"timeframe\":\""+IntegerToString(Period())+"\",";
   body+="\"side\":\""+side+"\",";
   body+="\"lots\":"+DoubleToString(OrderLots(),2)+",";
   body+="\"open_time\":\""+TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS)+"\",";
   body+="\"close_time\":\""+TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS)+"\",";
   body+="\"open_price\":"+DoubleToString(OrderOpenPrice(),Digits)+",";
   body+="\"close_price\":"+DoubleToString(OrderClosePrice(),Digits)+",";
   body+="\"stop_loss\":"+DoubleToString(OrderStopLoss(),Digits)+",";
   body+="\"take_profit\":"+DoubleToString(OrderTakeProfit(),Digits)+",";
   body+="\"pnl\":"+DoubleToString(netPnl,2)+",";
   body+="\"commission\":"+DoubleToString(OrderCommission(),2)+",";
   body+="\"swap\":"+DoubleToString(OrderSwap(),2)+",";
   body+="\"exit_reason\":\""+JsonEscape(ExitReasonForSelectedOrder())+"\",";
   body+="\"r_multiple\":"+DoubleToString(rewardR,5)+",";
   body+="\"metadata\":{";
   body+="\"report_family\":\"BITEY_SBT_LIBRARY\",";
   body+="\"learning_scope\":\"shared_bitey_ia_sbt\",";
   body+="\"source_version\":\"1.64.0\",";
   body+="\"q_learning\":{";
   body+="\"algorithm\":\"Q_LEARNING\",";
   body+="\"policy_key\":\"bitey_shared_trading_q_v1\",";
   body+="\"eligible\":"+JsonBool(InpQlearningExperienceEnabled && hasEntryState && riskUSD>0)+",";
   body+="\"state_id\":"+IntegerToString(entryState)+",";
   body+="\"action\":\""+side+"\",";
   body+="\"reward_r\":"+DoubleToString(rewardR,5)+",";
   body+="\"next_state_id\":"+IntegerToString(nextState)+",";
   body+="\"terminal\":true,";
   body+="\"model\":\""+JsonEscape(model)+"\",";
   body+="\"costs_included\":true,";
   body+="\"update_policy\":\"backend_owned_not_client_assumed\",";
   body+="\"ineligible_reason\":\""+(hasEntryState?"":"entry_state_missing_after_restart_or_legacy_trade")+"\"}}}";

   char post[],result[];
    // Copy the complete UTF-8 payload, then remove StringToCharArray's trailing NUL.
    // This avoids truncating multibyte characters and excludes NUL from the HTTP body.
    int copied=StringToCharArray(body,post,0,WHOLE_ARRAY,CP_UTF8);
    if(copied>0 && ArraySize(post)>0 && post[ArraySize(post)-1]==0)
       ArrayResize(post,ArraySize(post)-1);
   string headers="Content-Type: application/json; charset=utf-8\r\n";
   if(StringLen(InpSbtToken)>0) headers+="X-MT4-Token: "+InpSbtToken+"\r\n";
   string responseHeaders="";
   ResetLastError();
   int status=WebRequest("POST",InpSbtClosedTradeURL,headers,InpSbtTelemetryTimeoutMs,post,result,responseHeaders);
   int err=GetLastError();
   if(status>=200 && status<300)
   {
      GlobalVariableSet(sentKey,1.0);
      if(GlobalVariableCheck(stateKey)) GlobalVariableDel(stateKey);
      if(GlobalVariableCheck(modelKey)) GlobalVariableDel(modelKey);
      if(GlobalVariableCheck(riskKey)) GlobalVariableDel(riskKey);
      if(GlobalVariableCheck(actionKey)) GlobalVariableDel(actionKey);
      Print("SBT CLOSED TRADE REPORT OK | ticket=",ticket," HTTP=",status,
            " net=",DoubleToString(netPnl,2)," R=",DoubleToString(rewardR,4),
            " QLearningEligible=",(InpQlearningExperienceEnabled && hasEntryState && riskUSD>0?"YES":"NO"));
      return true;
   }
   if(err==4060)
      Print("SBT CLOSED TRADE REPORT BLOCKED BY MT4 | ticket=",ticket," error=4060 ERR_FUNCTION_NOT_ALLOWED. Add the Worker origin to Tools > Options > Expert Advisors > Allow WebRequest for listed URL: https://bitey-system-bots-trading.raylerr481.workers.dev . The closed trade will be retried while it remains in history.");
   else if(err==12002)
      Print("SBT CLOSED TRADE REPORT TIMEOUT | ticket=",ticket," WinINet=12002 url=",InpSbtClosedTradeURL,
            " | report remains eligible for retry while trade is in history.");
   else
      Print("SBT CLOSED TRADE REPORT ERROR | ticket=",ticket," HTTP=",status," error=",err,
            " url=",InpSbtClosedTradeURL," response=",CharArrayToString(result),
            " | report remains eligible for retry while trade is in history.");
   return false;
}

void SyncClosedTrades()
{
   int total=OrdersHistoryTotal();
   for(int i=total-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      string sentKey=TicketGlobalKey("sent",OrderTicket());
      if(GlobalVariableCheck(sentKey) && GlobalVariableGet(sentKey)>0) continue;
      if(!SendClosedTradeReport(i)) break; // avoid hammering an unavailable backend
   }
}

int ManageOpenTrades()
{
   int closedCount=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      int barsOpen=iBarShift(Symbol(),Period(),OrderOpenTime(),false);
      if(barsOpen<0 || barsOpen<InpMaxHoldBars) continue;
      RefreshRates();
      double closePrice=NormalizeDouble(type==OP_BUY?Bid:Ask,Digits);
      int ticket=OrderTicket();
      double lots=OrderLots();
      ResetLastError();
      if(OrderClose(ticket,lots,closePrice,InpSlippagePoints,clrNONE))
      {
         closedCount++;
         Print("TIME EXIT | ticket=",ticket," direction=",(type==OP_BUY?"BUY":"SELL"),
               " barsOpen=",barsOpen," maxHoldBars=",InpMaxHoldBars,
               " closePrice=",DoubleToString(closePrice,Digits));
      }
      else Print("TIME EXIT FAILED | ticket=",ticket," barsOpen=",barsOpen," error=",GetLastError());
   }
   return closedCount;
}

double GetATR(int shift)
{
   return iATR(Symbol(),Period(),InpATRPeriod,shift);
}

int SignOf(double x,double tolerance)
{
   if(x>tolerance) return 1;
   if(x< -tolerance) return -1;
   return 0;
}

bool GetModelSignalsForSymbol(string sym,int tf,int shift,int &trend,int &momentum,int &donchian,int &meanrev,int &strictRange,
                     int &atrBreakout,int &sessionBias,int &rsiDivergence,int &htfTrend,
                     int &vwapDeviation,int &breakRetest,int &fibPullback,int &volSqueeze,int &linearRegression,
                     int &macdConfirm,int &bollingerExpansion)
{
   trend=0; momentum=0; donchian=0; meanrev=0; strictRange=0;
   atrBreakout=0; sessionBias=0; rsiDivergence=0; htfTrend=0;
   vwapDeviation=0; breakRetest=0; fibPullback=0; volSqueeze=0; linearRegression=0;
   macdConfirm=0; bollingerExpansion=0;
   if(iBars(sym,tf) < InpTrendEMA+InpDonchianPeriod+shift+InpMomentumLookback+20) return false;
   double close1=iClose(sym,tf,shift), close2=iClose(sym,tf,shift+1);
   double open1=iOpen(sym,tf,shift), high1=iHigh(sym,tf,shift), low1=iLow(sym,tf,shift);
   double atr=iATR(sym,tf,InpATRPeriod,shift);
   double emaFast=iMA(sym,tf,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,shift);
   double emaSlow=iMA(sym,tf,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,shift);
   double emaTrend=iMA(sym,tf,InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,shift);
   double adx=iADX(sym,tf,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,shift);
   double plusDI=iADX(sym,tf,InpADXPeriod,PRICE_CLOSE,MODE_PLUSDI,shift);
   double minusDI=iADX(sym,tf,InpADXPeriod,PRICE_CLOSE,MODE_MINUSDI,shift);
   double rsi=iRSI(sym,tf,InpRSIPeriod,PRICE_CLOSE,shift);
   if(close1<=0 || close2<=0 || atr<=0 || emaFast<=0 || emaSlow<=0 || emaTrend<=0) return false;

   // 1. EMA trend following with ADX and directional-DI confirmation.
   if(adx>=InpTrendADXMin)
   {
      if(close1>emaTrend && emaFast>emaSlow && plusDI>minusDI) trend=1;
      else if(close1<emaTrend && emaFast<emaSlow && minusDI>plusDI) trend=-1;
      else if(MathAbs(close1-emaSlow)<=0.25*atr)
      {
         if(close1>emaTrend && plusDI>minusDI) trend=1;
         else if(close1<emaTrend && minusDI>plusDI) trend=-1;
      }
   }

   // 2. Momentum confirmation, normalized by ATR; same rule used by evidence backtest.
   double oldClose=iClose(sym,tf,shift+InpMomentumLookback);
   if(oldClose>0)
   {
      double normalized=(close1-oldClose)/atr;
      if(normalized>=InpMomentumATRThreshold && close1>emaSlow) momentum=1;
      else if(normalized<=-InpMomentumATRThreshold && close1<emaSlow) momentum=-1;
   }
   if(InpMomentumTrendContinuation && momentum==0 && adx>=InpTrendADXMin)
   {
      if(close1>emaTrend && emaFast>emaSlow && close1>emaSlow && plusDI>minusDI && rsi<InpContinuationBuyRSIMax) momentum=1;
      else if(close1<emaTrend && emaFast<emaSlow && close1<emaSlow && minusDI>plusDI && rsi>InpContinuationSellRSIMin) momentum=-1;
   }

   // Donchian boundaries only use candles older than the candidate candle.
   double priorHigh=-1.0e100, priorLow=1.0e100;
   for(int k=shift+1;k<=shift+InpDonchianPeriod;k++)
   {
      double hi=iHigh(sym,tf,k), lo=iLow(sym,tf,k);
      if(hi>priorHigh) priorHigh=hi;
      if(lo<priorLow) priorLow=lo;
   }
   double breakoutBuffer=MathMax(0.0,InpBreakoutBufferATR)*atr;
   // 3. Donchian breakout.
   if(close1>priorHigh+breakoutBuffer) donchian=1;
   else if(close1<priorLow-breakoutBuffer) donchian=-1;

   // 4. RSI mean reversion candidate in a weak-trend regime. Historical evidence
   // is recalculated using this exact rule; wider triggers do not bypass the evidence gate.
   if(adx<=InpMeanRevADXMax)
   {
      if(rsi<=InpMeanRevRSIBuy) meanrev=1;
      else if(rsi>=InpMeanRevRSISell) meanrev=-1;
   }

   // 5. Strict range reversion uses a shorter, closed-bar range instead of the
   // Donchian breakout window. This avoids requiring price to touch a 20-bar extreme
   // while simultaneously demanding compressed EMAs. Confirmation and evidence gates remain.
   double rangeHigh=-1.0e100, rangeLow=1.0e100;
   int rangeLookback=MathMax(3,InpStrictRangeLookback);
   for(int srk=shift+1;srk<=shift+rangeLookback;srk++)
   {
      double srHigh=iHigh(sym,tf,srk);
      double srLow=iLow(sym,tf,srk);
      if(srHigh>rangeHigh) rangeHigh=srHigh;
      if(srLow<rangeLow) rangeLow=srLow;
   }
   if(adx<=InpStrictRangeADXMax && MathAbs(emaFast-emaSlow)<=InpStrictRangeEMAGapATR*atr)
   {
      // Range-edge + RSI define the candidate. Do not require the same candle to
      // close in the signal direction: v1.17 audit showed this eliminated every
      // qualifying candidate. Historical evidence remains mandatory downstream.
      if(close1<=rangeLow+InpStrictRangeEdgeATR*atr && rsi<=InpStrictRangeBuyRSI) strictRange=1;
      else if(close1>=rangeHigh-InpStrictRangeEdgeATR*atr && rsi>=InpStrictRangeSellRSI) strictRange=-1;
   }

   // 6. ATR volatility expansion: larger-than-normal candle plus directional close.
   double rangeSum=0.0;
   for(int n=shift+1;n<=shift+10;n++) rangeSum+=iHigh(sym,tf,n)-iLow(sym,tf,n);
   double avgRange=rangeSum/10.0, candleRange=high1-low1;
   if(avgRange>0.0 && candleRange>=1.35*avgRange && candleRange>=0.80*atr)
   {
      if(close1>open1 && close1>close2) atrBreakout=1;
      else if(close1<open1 && close1<close2) atrBreakout=-1;
   }

   // 7. Session bias is a weak confirmation, never a time-only entry.
   int hour=TimeHour(iTime(sym,tf,shift));
   if(hour>=7 && hour<20)
   {
      if(close1>emaTrend && emaFast>emaSlow && close1>close2) sessionBias=1;
      else if(close1<emaTrend && emaFast<emaSlow && close1<close2) sessionBias=-1;
   }

   // 8. Conservative short-window RSI/price divergence proxy.
   double oldLow=1.0e100, oldHigh=-1.0e100; int lowShift=shift+6, highShift=shift+6;
   for(int d=shift+2;d<=shift+6;d++)
   {
      if(iLow(sym,tf,d)<oldLow) { oldLow=iLow(sym,tf,d); lowShift=d; }
      if(iHigh(sym,tf,d)>oldHigh) { oldHigh=iHigh(sym,tf,d); highShift=d; }
   }
   double oldRsiLow=iRSI(sym,tf,InpRSIPeriod,PRICE_CLOSE,lowShift);
   double oldRsiHigh=iRSI(sym,tf,InpRSIPeriod,PRICE_CLOSE,highShift);
   if(low1<oldLow && rsi>oldRsiLow+3.0) rsiDivergence=1;
   else if(high1>oldHigh && rsi<oldRsiHigh-3.0) rsiDivergence=-1;

   // 9. Higher-timeframe trend confirmation using a closed H4 candle.
   // Use the HTF candle immediately before the candle containing this signal timestamp.
   // This avoids using a still-forming H4 bar (look-ahead in historical evidence).
   int htfContainingShift=iBarShift(sym,PERIOD_H4,iTime(sym,tf,shift),false);
   int htfShift=(htfContainingShift>=0 ? htfContainingShift+1 : -1);
   if(htfShift>=1)
   {
      double h4Fast=iMA(sym,PERIOD_H4,20,0,MODE_EMA,PRICE_CLOSE,htfShift);
      double h4Slow=iMA(sym,PERIOD_H4,50,0,MODE_EMA,PRICE_CLOSE,htfShift);
      if(h4Fast>0 && h4Slow>0)
      {
         if(h4Fast>h4Slow && close1>emaSlow) htfTrend=1;
         else if(h4Fast<h4Slow && close1<emaSlow) htfTrend=-1;
      }
   }

   // 10. Rolling tick-volume VWAP deviation. This is a broker tick-volume proxy,
   // not exchange-grade centralized SOL volume; evidence validation is mandatory.
   double pv=0.0,vol=0.0;
   int vwapN=MathMax(5,MathMin(InpVWAPLookback,100));
   for(int vw=shift;vw<shift+vwapN && vw<iBars(sym,tf);vw++)
   {
      double typical=(iHigh(sym,tf,vw)+iLow(sym,tf,vw)+iClose(sym,tf,vw))/3.0;
      double tv=(double)iVolume(sym,tf,vw);
      if(typical>0 && tv>0) { pv+=typical*tv; vol+=tv; }
   }
   if(vol>0.0)
   {
      double vwap=pv/vol;
      if(close1<vwap-InpVWAPDeviationATR*atr && rsi<45.0) vwapDeviation=1;
      else if(close1>vwap+InpVWAPDeviationATR*atr && rsi>55.0) vwapDeviation=-1;
   }

   // 11. Breakout followed by a retest and close back beyond the broken boundary.
   double priorTop=-1.0e100,priorBottom=1.0e100;
   int rtN=MathMax(5,MathMin(InpRetestLookback,40));
   for(int rt=shift+2;rt<=shift+rtN+1;rt++)
   {
      priorTop=MathMax(priorTop,iHigh(sym,tf,rt));
      priorBottom=MathMin(priorBottom,iLow(sym,tf,rt));
   }
   double tolerance=MathMax(0.0,InpRetestToleranceATR)*atr;
   double previousClose=iClose(sym,tf,shift+1);
   if(previousClose>priorTop && low1<=priorTop+tolerance && close1>priorTop) breakRetest=1;
   else if(previousClose<priorBottom && high1>=priorBottom-tolerance && close1<priorBottom) breakRetest=-1;

   // 12. Trend-aligned Fibonacci retracement zone (38.2%-61.8%) with candle confirmation.
   double swingHigh=-1.0e100,swingLow=1.0e100;
   int fibN=MathMax(10,MathMin(InpFibLookback,100));
   for(int fb=shift+1;fb<=shift+fibN;fb++)
   {
      swingHigh=MathMax(swingHigh,iHigh(sym,tf,fb));
      swingLow=MathMin(swingLow,iLow(sym,tf,fb));
   }
   double swingRange=swingHigh-swingLow;
   if(swingRange>atr && adx>=InpTrendADXMin)
   {
      double retraceFromHigh=(swingHigh-close1)/swingRange;
      double retraceFromLow=(close1-swingLow)/swingRange;
      if(close1>emaTrend && emaFast>emaSlow && retraceFromHigh>=0.382 && retraceFromHigh<=0.618 && close1>open1) fibPullback=1;
      else if(close1<emaTrend && emaFast<emaSlow && retraceFromLow>=0.382 && retraceFromLow<=0.618 && close1<open1) fibPullback=-1;
   }

   // 13. Bollinger-band squeeze release, using closed bars and directional confirmation.
   double upperNow=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_UPPER,shift);
   double lowerNow=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_LOWER,shift);
   double upperPrev=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_UPPER,shift+1);
   double lowerPrev=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_LOWER,shift+1);
   double widthNow=upperNow-lowerNow,widthPrev=upperPrev-lowerPrev;
   double widthAvg=0.0; int widthCount=0;
   for(int bw=shift+2;bw<shift+12 && bw<iBars(sym,tf);bw++)
   {
      double bu=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_UPPER,bw);
      double bl=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_LOWER,bw);
      if(bu>bl && bl>0) { widthAvg+=(bu-bl); widthCount++; }
   }
   if(widthCount>0 && widthPrev>0 && widthNow>widthPrev && widthPrev<(widthAvg/widthCount)*InpSqueezeWidthFactor)
   {
      if(close1>upperNow && close1>open1) volSqueeze=1;
      else if(close1<lowerNow && close1<open1) volSqueeze=-1;
   }

   // 14. ATR-normalized linear-regression slope with trend-side confirmation.
   int lrN=MathMax(5,MathMin(InpRegressionLookback,50));
   double sumX=0.0,sumY=0.0,sumXY=0.0,sumXX=0.0;
   for(int lr=0;lr<lrN;lr++)
   {
      double x=(double)lr;
      double y=iClose(sym,tf,shift+lrN-1-lr);
      sumX+=x; sumY+=y; sumXY+=x*y; sumXX+=x*x;
   }
   double denom=lrN*sumXX-sumX*sumX;
   if(denom!=0.0)
   {
      double slope=(lrN*sumXY-sumX*sumY)/denom;
      if(slope/atr>=InpRegressionSlopeATR && close1>emaSlow) linearRegression=1;
      else if(slope/atr<=-InpRegressionSlopeATR && close1<emaSlow) linearRegression=-1;
   }

   // 15. MACD confirmation: closed-bar main/signal alignment, histogram improvement,
   // and trend-side confirmation. The same formula is used by historical evidence.
   double macdMain=iMACD(sym,tf,12,26,9,PRICE_CLOSE,MODE_MAIN,shift);
   double macdSignal=iMACD(sym,tf,12,26,9,PRICE_CLOSE,MODE_SIGNAL,shift);
   double macdMainPrev=iMACD(sym,tf,12,26,9,PRICE_CLOSE,MODE_MAIN,shift+1);
   double macdSignalPrev=iMACD(sym,tf,12,26,9,PRICE_CLOSE,MODE_SIGNAL,shift+1);
   if(macdMain>macdSignal && macdMain>macdMainPrev && macdMain>=0.0 && close1>emaSlow) macdConfirm=1;
   else if(macdMain<macdSignal && macdMain<macdMainPrev && macdMain<=0.0 && close1<emaSlow) macdConfirm=-1;

   // 16. Bollinger expansion breakout: expanding bands plus a directional closed-bar close.
   if(widthNow>0.0 && widthPrev>0.0 && widthNow>widthPrev)
   {
      if(close1>upperNow && close1>open1) bollingerExpansion=1;
      else if(close1<lowerNow && close1<open1) bollingerExpansion=-1;
   }
   return true;
}

bool GetModelSignals(int shift,int &trend,int &momentum,int &donchian,int &meanrev,int &strictRange,
                     int &atrBreakout,int &sessionBias,int &rsiDivergence,int &htfTrend,
                     int &vwapDeviation,int &breakRetest,int &fibPullback,int &volSqueeze,int &linearRegression,
                     int &macdConfirm,int &bollingerExpansion)
{
   return GetModelSignalsForSymbol(Symbol(),Period(),shift,trend,momentum,donchian,meanrev,strictRange,
      atrBreakout,sessionBias,rsiDivergence,htfTrend,vwapDeviation,breakRetest,fibPullback,volSqueeze,
      linearRegression,macdConfirm,bollingerExpansion);
}

// Returns the realized forward outcome in R for a hypothetical entry at the closed bar close.
// If stop and target are both touched inside one candle, the conservative result is -1R.
bool ForwardOutcomeRForSymbol(string sym,int tf,int entryShift,int direction,double &outR)
{
   outR=0.0;
   double entry=iClose(sym,tf,entryShift);
   double atr=iATR(sym,tf,InpATRPeriod,entryShift);
   if(entry<=0 || atr<=0 || direction==0) return false;
   double riskDistance=atr*InpStopATR;
   double targetDistance=atr*InpTargetATR;
   if(riskDistance<=0 || targetDistance<=0) return false;
   // Exclude incomplete outcomes instead of silently scoring a shorter horizon.
   if(entryShift<=InpForwardHorizonBars) return false;
   int endShift=entryShift-InpForwardHorizonBars;
   if(endShift<1) return false;
   for(int s=entryShift-1;s>=endShift;s--)
   {
      if(s<0) break;
      double hi=iHigh(sym,tf,s), lo=iLow(sym,tf,s);
      bool hitSL=false, hitTP=false;
      if(direction>0)
      {
         hitSL=(lo<=entry-riskDistance); hitTP=(hi>=entry+targetDistance);
      }
      else
      {
         hitSL=(hi>=entry+riskDistance); hitTP=(lo<=entry-targetDistance);
      }
      if(hitSL && hitTP) { outR=-1.0; return true; }
      if(hitSL) { outR=-1.0; return true; }
      if(hitTP) { outR=InpTargetATR/InpStopATR; return true; }
   }
   // Exit at the close of the final forward bar, normalized by the initial stop distance.
   double exitClose=iClose(sym,tf,endShift);
   if(exitClose<=0) return false;
   outR=(direction>0 ? (exitClose-entry) : (entry-exitClose))/riskDistance;
   return true;
}

int ModelSignalAtForSymbol(string sym,int tf,int model,int shift)
{
   int t=0,m=0,d=0,r=0,sr=0,a=0,sb=0,rd=0,ht=0,vw=0,br=0,fp=0,vs=0,lr=0,mc=0,be=0;
   if(!GetModelSignalsForSymbol(sym,tf,shift,t,m,d,r,sr,a,sb,rd,ht,vw,br,fp,vs,lr,mc,be)) return 0;
   if(model==MODEL_TREND) return t;
   if(model==MODEL_MOMENTUM) return m;
   if(model==MODEL_DONCHIAN) return d;
   if(model==MODEL_MEANREV) return r;
   if(model==MODEL_STRICT_RANGE) return sr;
   if(model==MODEL_ATR_BREAKOUT) return a;
   if(model==MODEL_SESSION_BIAS) return sb;
   if(model==MODEL_RSI_DIVERGENCE) return rd;
   if(model==MODEL_HTF_TREND) return ht;
   if(model==MODEL_VWAP_DEVIATION) return vw;
   if(model==MODEL_BREAK_RETEST) return br;
   if(model==MODEL_FIB_PULLBACK) return fp;
   if(model==MODEL_VOL_SQUEEZE) return vs;
   if(model==MODEL_LINEAR_REGRESSION) return lr;
   if(model==MODEL_MACD_CONFIRM) return mc;
   if(model==MODEL_BOLLINGER_EXPANSION) return be;
   return 0;
}

int ModelSignalAt(int model,int shift)
{
   return ModelSignalAtForSymbol(Symbol(),Period(),model,shift);
}

void BuildEvidenceForSymbol(string sym,int tf,int model,int direction,DirectionEvidence &e)
{
   ResetEvidence(e);
   int maxShift=MathMin(InpEvidenceLookbackBars,iBars(sym,tf)-InpTrendEMA-InpDonchianPeriod-InpForwardHorizonBars-5);
   int minShift=InpForwardHorizonBars+1;
   for(int shift=minShift;shift<=maxShift;shift++)
   {
      if(ModelSignalAtForSymbol(sym,tf,model,shift)!=direction) continue;
      double resultR=0.0;
      if(!ForwardOutcomeRForSymbol(sym,tf,shift,direction,resultR)) continue;
      e.samples++;
      if(resultR>0.0) e.wins++;
      e.sumR+=resultR;
   }
   FinalizeEvidence(e);
}

void BuildEvidence(int model,int direction,DirectionEvidence &e)
{
   BuildEvidenceForSymbol(Symbol(),Period(),model,direction,e);
}

bool SymbolLocalLiveConsensus(string sym,int tf,string &dirOut,int &votesOut)
{
   dirOut="NONE"; votesOut=0;
   int t=0,m=0,d=0,r=0,sr=0,a=0,sb=0,rd=0,ht=0,vw=0,br=0,fp=0,vs=0,lr=0,mc=0,be=0;
   if(!GetModelSignalsForSymbol(sym,tf,1,t,m,d,r,sr,a,sb,rd,ht,vw,br,fp,vs,lr,mc,be))
   {
      Print("LOCAL 16-MODEL SYMBOL SCAN | symbol=",sym," timeframe=",tf," decision=REJECT reason=LOCAL_MODEL_DATA_UNAVAILABLE");
      return false;
   }
   int signals[16]; signals[0]=t; signals[1]=m; signals[2]=d; signals[3]=r;
   signals[4]=sr; signals[5]=a; signals[6]=sb; signals[7]=rd; signals[8]=ht;
   signals[9]=vw; signals[10]=br; signals[11]=fp; signals[12]=vs; signals[13]=lr;
   signals[14]=mc; signals[15]=be;
   int buy=0,sell=0;
   for(int i=0;i<16;i++) { if(signals[i]>0) buy++; else if(signals[i]<0) sell++; }
   votesOut=MathMax(buy,sell);
   if(buy!=sell && votesOut>=RequiredModelVotes()) dirOut=(buy>sell?"BUY":"SELL");
   bool pass=(dirOut=="BUY" || dirOut=="SELL");
   Print("LOCAL 16-MODEL PER-SYMBOL VOTES | symbol=",sym," timeframe=",tf,
      " BUY=",buy," SELL=",sell," chosenDirection=",dirOut,
      " requiredVotes=",RequiredModelVotes()," decision=",(pass?"PASS":"REJECT"),
      " modelFamilies=TREND,MOMENTUM,DONCHIAN,MEANREV,STRICT_RANGE,ATR_BREAKOUT,SESSION_BIAS,RSI_DIVERGENCE,HTF_TREND,VWAP_DEVIATION,BREAK_RETEST,FIB_PULLBACK,VOL_SQUEEZE,LINEAR_REGRESSION,MACD_CONFIRM,BOLLINGER_EXPANSION");
   return pass;
}

bool EvidencePass(DirectionEvidence &e);

bool SymbolLocalEnsemblePass(string sym,int tf,string dir)
{
   if(dir!="BUY" && dir!="SELL") return false;
   int t=0,m=0,d=0,r=0,sr=0,a=0,sb=0,rd=0,ht=0,vw=0,br=0,fp=0,vs=0,lr=0,mc=0,be=0;
   if(!GetModelSignalsForSymbol(sym,tf,1,t,m,d,r,sr,a,sb,rd,ht,vw,br,fp,vs,lr,mc,be))
   {
      Print("LOCAL 16-MODEL SYMBOL AUDIT | symbol=",sym," timeframe=",tf," decision=REJECT reason=LOCAL_MODEL_DATA_UNAVAILABLE");
      return false;
   }
   int signals[16]; signals[0]=t; signals[1]=m; signals[2]=d; signals[3]=r;
   signals[4]=sr; signals[5]=a; signals[6]=sb; signals[7]=rd; signals[8]=ht;
   signals[9]=vw; signals[10]=br; signals[11]=fp; signals[12]=vs; signals[13]=lr;
   signals[14]=mc; signals[15]=be;
   int wanted=(dir=="BUY"?1:-1), directionVotes=0, qualifiedVotes=0;
   for(int i=0;i<16;i++) if(signals[i]==wanted) directionVotes++;
   for(int j=0;j<16;j++)
   {
      if(signals[j]!=wanted) continue;
      DirectionEvidence ev; BuildEvidenceForSymbol(sym,tf,j,wanted,ev);
      bool pass=EvidencePass(ev);
      Print("LOCAL MODEL SYMBOL EVIDENCE | symbol=",sym," timeframe=",tf," modelId=",j,
         " direction=",dir," samples=",ev.samples," winRate=",DoubleToString(ev.winRate,3),
         " avgR=",DoubleToString(ev.avgR,3)," qualified=",(pass?"true":"false"));
      if(pass) qualifiedVotes++;
   }
   bool pass=(directionVotes>=RequiredModelVotes() && qualifiedVotes>=RequiredModelVotes());
   Print("LOCAL 16-MODEL SYMBOL ENSEMBLE | symbol=",sym," timeframe=",tf," direction=",dir,
      " directionalVotes=",directionVotes," evidenceQualifiedVotes=",qualifiedVotes,
      " requiredVotes=",RequiredModelVotes()," decision=",(pass?"PASS":"REJECT"),
      " scope=INDEPENDENT_CANDIDATE_SYMBOL_CLOSED_BAR_AND_PER_MODEL_EVIDENCE");
   return pass;
}

bool IsProvisionalEvidence(DirectionEvidence &e)
{
   // A narrow opportunity-expansion tier: NORMAL governor only, 6-11 samples,
   // >=55% wins and >+0.10R mean. This is not used during STRICT or PROTECT.
   return (g_governorState==0 && e.samples>=6 && e.samples<InpMinEvidenceSamples &&
           e.winRate>=0.55 && e.avgR>0.10);
}

bool EvidencePass(DirectionEvidence &e)
{
   int minSamples=InpMinEvidenceSamples;
   double minWinRate=InpMinEvidenceWinRate;
   double minAvgR=InpMinEvidenceAvgR;
   if(g_governorState==1 || g_governorState==3)
   {
      minSamples=MathMax(InpMinEvidenceSamples,18);
      minWinRate=MathMax(InpMinEvidenceWinRate,0.48);
      minAvgR=MathMax(InpMinEvidenceAvgR,0.05);
   }
   else if(g_governorState==2)
   {
      minSamples=MathMax(8,MathMin(InpMinEvidenceSamples,10));
      minWinRate=MathMax(0.40,InpMinEvidenceWinRate-0.02);
      minAvgR=MathMax(0.01,InpMinEvidenceAvgR-0.005);
   }
   if(e.samples>=minSamples && e.winRate>=minWinRate && e.avgR>minAvgR) return true;
   return IsProvisionalEvidence(e);
}

string EvidenceRejectReason(DirectionEvidence &e)
{
   int minSamples=InpMinEvidenceSamples;
   double minWinRate=InpMinEvidenceWinRate;
   double minAvgR=InpMinEvidenceAvgR;
   if(g_governorState==1 || g_governorState==3)
   {
      minSamples=MathMax(InpMinEvidenceSamples,18);
      minWinRate=MathMax(InpMinEvidenceWinRate,0.48);
      minAvgR=MathMax(InpMinEvidenceAvgR,0.05);
   }
   else if(g_governorState==2)
   {
      minSamples=MathMax(8,MathMin(InpMinEvidenceSamples,10));
      minWinRate=MathMax(0.40,InpMinEvidenceWinRate-0.02);
      minAvgR=MathMax(0.01,InpMinEvidenceAvgR-0.005);
   }
   if(IsProvisionalEvidence(e)) return "PROVISIONAL_STRONG_EDGE_REDUCED_RISK";
   if(e.samples<minSamples)
      return "INSUFFICIENT_SAMPLES n="+IntegerToString(e.samples)+" required="+IntegerToString(minSamples);
   if(e.winRate<minWinRate)
      return "WIN_RATE_BELOW_THRESHOLD actual="+DoubleToString(e.winRate,3)+" required="+DoubleToString(minWinRate,3);
   if(e.avgR<=minAvgR)
      return "AVERAGE_R_NOT_ABOVE_THRESHOLD actual="+DoubleToString(e.avgR,3)+" required_gt="+DoubleToString(minAvgR,3);
   return "PASS";
}

string TradeErrorDescription(int code)
{
   switch(code)
   {
      case 0: return "NO_ERROR";
      case 1: return "NO_RESULT_OR_UNCHANGED";
      case 2: return "COMMON_ERROR";
      case 3: return "INVALID_TRADE_PARAMETERS";
      case 4: return "TRADE_SERVER_BUSY";
      case 5: return "OLD_TERMINAL_VERSION";
      case 6: return "NO_CONNECTION";
      case 8: return "TOO_FREQUENT_REQUESTS";
      case 64: return "ACCOUNT_DISABLED";
      case 65: return "INVALID_ACCOUNT";
      case 128: return "TRADE_TIMEOUT_CHECK_ACCOUNT_BEFORE_RETRY";
      case 129: return "INVALID_PRICE_REFRESH_QUOTES";
      case 130: return "INVALID_STOPS_STOPLEVEL_OR_FREEZELEVEL";
      case 131: return "INVALID_TRADE_VOLUME_LOT_STEP_OR_MINMAX";
      case 132: return "MARKET_CLOSED";
      case 133: return "TRADING_DISABLED_BY_SERVER_OR_SYMBOL";
      case 134: return "NOT_ENOUGH_MONEY_MARGIN";
      case 135: return "PRICE_CHANGED";
      case 136: return "OFF_QUOTES";
      case 137: return "BROKER_BUSY";
      case 138: return "REQUOTE";
      case 139: return "ORDER_LOCKED";
      case 140: return "LONG_POSITIONS_ONLY";
      case 141: return "TOO_MANY_REQUESTS";
      case 145: return "MODIFICATION_DENIED_TOO_CLOSE_TO_MARKET";
      case 146: return "TRADE_CONTEXT_BUSY";
      case 147: return "EXPIRATION_DENIED_BY_BROKER";
      case 148: return "TOO_MANY_ORDERS";
      case 4109: return "EA_TRADING_NOT_ALLOWED_ENABLE_EXPERT_ADVISORS_AND_ALLOW_LIVE_TRADING";
      case 4110: return "BUY_NOT_ALLOWED_IN_EA_PROPERTIES";
      case 4111: return "SELL_NOT_ALLOWED_IN_EA_PROPERTIES";
   }
   return "UNKNOWN_MT4_ERROR_CHECK_MQL4_ERROR_CODE";
}

bool IsNewCalendarDay(datetime a,datetime b)
{
   if(a<=0 || b<=0) return true;
   return (TimeYear(a)!=TimeYear(b) || TimeMonth(a)!=TimeMonth(b) || TimeDay(a)!=TimeDay(b));
}

int CountTodayTrades()
{
   int count=0;
   datetime dayStart=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      // Daily entry quota is based on when the position was OPENED, not when an older
      // position happened to close. Otherwise yesterday's trade closed today consumes
      // today's entry allowance even though no new entry was opened today.
      if(OrderOpenTime()>=dayStart) count++;
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderOpenTime()>=dayStart) count++;
   }
   return count;
}

// Prints the exact orders counted against today's entry quota. This is diagnostic only:
// it never changes the limit and never authorizes an otherwise blocked order.
void PrintTodayTradeCountAudit()
{
   datetime dayStart=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   int historyCount=0,openCount=0;
   Print("DAILY ENTRY AUDIT | serverDate=",TimeToString(dayStart,TIME_DATE),
         " magic=",InpMagic," countedBy=OrderOpenTime", " limit=",InpMaxTradesPerDay);
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderOpenTime()<dayStart) continue;
      historyCount++;
      Print("DAILY ENTRY AUDIT ITEM | bucket=HISTORY ticket=",OrderTicket(),
            " symbol=",OrderSymbol()," type=",OrderType(),
            " opened=",TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),
            " closed=",TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),
            " magic=",OrderMagicNumber());
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderOpenTime()<dayStart) continue;
      openCount++;
      Print("DAILY ENTRY AUDIT ITEM | bucket=OPEN ticket=",OrderTicket(),
            " symbol=",OrderSymbol()," type=",OrderType(),
            " opened=",TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),
            " magic=",OrderMagicNumber()," stopLoss=",DoubleToString(OrderStopLoss(),Digits));
   }
   Print("DAILY ENTRY AUDIT SUMMARY | historyEntries=",historyCount,
         " openEntries=",openCount," total=",historyCount+openCount,
         " functionCount=",CountTodayTrades()," limit=",InpMaxTradesPerDay,
         " | portfolio-wide across orders with this magic number; configured limit remains enforced.");
}

double TodayNetProfit()
{
   double net=0.0;
   datetime dayStart=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()>=dayStart) net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return net;
}

int CountOpenTrades()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==InpMagic && (OrderType()==OP_BUY || OrderType()==OP_SELL)) count++;
   }
   return count;
}

int CountOpenTradesForSymbol()
{
   // Count by canonical asset, not literal broker symbol, so SOLUSD/SOLUSDT or suffix aliases
   // cannot create duplicate exposure in the same one-asset slot.
   int count=0;
   string chartKey=CanonicalAssetKey(Symbol());
   if(chartKey=="") return 0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(CanonicalAssetKey(OrderSymbol())==chartKey) count++;
   }
   return count;
}

bool IsCryptoLikeSymbol(string symbol)
{
   string upper=symbol; StringToUpper(upper);
   if(StringFind(upper,"USDT")>=0 || StringFind(upper,"BTC")>=0 || StringFind(upper,"ETH")>=0 ||
      StringFind(upper,"SOL")>=0 || StringFind(upper,"DOGE")>=0 || StringFind(upper,"AVAX")>=0 ||
      StringFind(upper,"NEAR")>=0 || StringFind(upper,"AAVE")>=0 || StringFind(upper,"ADA")>=0 ||
      StringFind(upper,"SUI")>=0 || StringFind(upper,"XRP")>=0 || StringFind(upper,"BNB")>=0 ||
      StringFind(upper,"LTC")>=0 || StringFind(upper,"DOT")>=0 || StringFind(upper,"LINK")>=0 ||
      StringFind(upper,"TRX")>=0 || StringFind(upper,"SHIB")>=0 || StringFind(upper,"TON")>=0)
      return true;
   return false;
}

int CountOpenCryptoPositions()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(IsCryptoLikeSymbol(OrderSymbol())) count++;
   }
   return count;
}

void AuditPortfolioBeforeEntry()
{
   double aggregateRisk=PortfolioOpenRiskUSD();
   Print("PORTFOLIO ENTRY AUDIT | candidateSymbol=",Symbol(),
         " candidateEvidenceGate=must_pass_current_chart_closed_bar_models_and_cost_checks",
         " openPositions=",CountOpenTrades(),"/",EffectiveMaxOpenTrades(),
         " openCryptoPositions=",CountOpenCryptoPositions(),"/",InpCrossAssetMaxCryptoPositions,
         " aggregateStopRiskUSD=",(aggregateRisk>=0.0?DoubleToString(aggregateRisk,2):"UNKNOWN"),
         " aggregateRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),2),
         " portfolioFloatingAndClosedTodayNetUSD=",DoubleToString(TodayNetProfit(),2),
         " dailyLossLimitUSD=",DoubleToString(EffectiveDailyLossLimitUSD(),2),
         " distinctSymbolRequired=true");
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      double risk=(OrderStopLoss()>0.0?EstimateOrderRiskUSD(OrderSymbol(),OrderLots(),MathAbs(OrderOpenPrice()-OrderStopLoss())):-1.0);
      Print("PORTFOLIO INCUMBENT AUDIT | ticket=",OrderTicket(),
            " symbol=",OrderSymbol()," direction=",(OrderType()==OP_BUY?"BUY":"SELL"),
            " floatingNetUSD=",DoubleToString(OrderProfit()+OrderSwap()+OrderCommission(),2),
            " stopRiskUSD=",(risk>=0.0?DoubleToString(risk,2):"UNKNOWN"),
            " hasStop=",(OrderStopLoss()>0.0?"true":"false"),
            " opened=",TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS));
   }
}

// MODE_TICKSIZE from this broker is already expressed in price units.
// Do NOT multiply by MODE_POINT: the v1.41 live log showed both values as
// 0.001 for SOLUSDT, and multiplying them produced a 0.000001 tick, inflating
// stop risk and spread cost by 1000x. Keep the broker-reported tick size as-is.
double TickSizePriceForSymbol(string symbol)
{
   double tickSizePrice=MarketInfo(symbol,MODE_TICKSIZE);
   if(tickSizePrice<=0.0) return 0.0;
   return tickSizePrice;
}

bool ValidatePositiveExpectedNetProfit(string symbol,double lots,double expectedR,double stopDistance,double targetDistance,string direction,string source)
{
   double point=MarketInfo(symbol,MODE_POINT);
   double tickSize=TickSizePriceForSymbol(symbol);
   double tickValue=MarketInfo(symbol,MODE_TICKVALUE);
   double spreadPoints=MarketInfo(symbol,MODE_SPREAD);
   double stopRiskUSD=EstimateOrderRiskUSD(symbol,lots,stopDistance);
   double targetGrossUSD=EstimateOrderRiskUSD(symbol,lots,targetDistance);
   double spreadCostUSD=EstimateOrderRiskUSD(symbol,lots,spreadPoints*point);
   double slippageCostUSD=EstimateOrderRiskUSD(symbol,lots,InpSlippagePoints*point);
   double commissionCostUSD=lots*InpRoundTurnCommissionPerLotUSD;
   double swapCostUSD=lots*InpExpectedSwapCostPerLotUSD;
   if(lots<=0.0 || expectedR<=0.0 || stopDistance<=0.0 || targetDistance<=0.0 ||
      point<=0.0 || tickSize<=0.0 || tickValue<=0.0 || stopRiskUSD<=0.0 ||
      targetGrossUSD<=0.0 || spreadCostUSD<0.0 || slippageCostUSD<0.0 ||
      InpRoundTurnCommissionPerLotUSD<0.0 || InpExpectedSwapCostPerLotUSD<0.0)
   {
      Print("GLOBAL EXPECTANCY GATE | decision=REJECTED source=",source," symbol=",symbol,
            " direction=",direction," expectedR=",DoubleToString(expectedR,6),
            " reason=EXPECTED_EDGE_OR_COST_INPUT_UNKNOWN_OR_NONPOSITIVE",
            " stopRiskUSD=",DoubleToString(stopRiskUSD,4)," targetGrossUSD=",DoubleToString(targetGrossUSD,4),
            " spreadCostUSD=",DoubleToString(spreadCostUSD,4)," slippageCostUSD=",DoubleToString(slippageCostUSD,4),
            " commissionInputUSDPerLot=",DoubleToString(InpRoundTurnCommissionPerLotUSD,4),
            " swapInputUSDPerLot=",DoubleToString(InpExpectedSwapCostPerLotUSD,4),
            " | no order sent for BUY or SELL.");
      return false;
   }
   double grossExpectedUSD=expectedR*stopRiskUSD;
   double allKnownCostsUSD=spreadCostUSD+slippageCostUSD+commissionCostUSD+swapCostUSD;
   double netExpectedUSD=grossExpectedUSD-allKnownCostsUSD;
   double netTargetUSD=targetGrossUSD-allKnownCostsUSD;
   if(netExpectedUSD<=0.0 || netTargetUSD<=0.0)
   {
      Print("GLOBAL EXPECTANCY GATE | decision=REJECTED source=",source," symbol=",symbol,
            " direction=",direction," reason=EXPECTED_NET_PROFIT_NOT_STRICTLY_POSITIVE",
            " expectedR=",DoubleToString(expectedR,6)," stopRiskUSD=",DoubleToString(stopRiskUSD,4),
            " grossExpectedUSD=",DoubleToString(grossExpectedUSD,4),
            " targetGrossUSD=",DoubleToString(targetGrossUSD,4),
            " spreadCostUSD=",DoubleToString(spreadCostUSD,4),
            " slippageCostUSD=",DoubleToString(slippageCostUSD,4),
            " commissionCostUSD=",DoubleToString(commissionCostUSD,4),
            " expectedSwapCostUSD=",DoubleToString(swapCostUSD,4),
            " totalEstimatedCostsUSD=",DoubleToString(allKnownCostsUSD,4),
            " netExpectedUSD=",DoubleToString(netExpectedUSD,4),
            " netAtTPUSD=",DoubleToString(netTargetUSD,4),
            " | no order sent; no same-bar retry.");
      return false;
   }
   Print("GLOBAL EXPECTANCY GATE | decision=PASS source=",source," symbol=",symbol,
         " direction=",direction," expectedR=",DoubleToString(expectedR,6),
         " stopRiskUSD=",DoubleToString(stopRiskUSD,4)," grossExpectedUSD=",DoubleToString(grossExpectedUSD,4),
         " targetGrossUSD=",DoubleToString(targetGrossUSD,4),
         " spreadCostUSD=",DoubleToString(spreadCostUSD,4),
         " slippageCostUSD=",DoubleToString(slippageCostUSD,4),
         " commissionCostUSD=",DoubleToString(commissionCostUSD,4),
         " expectedSwapCostUSD=",DoubleToString(swapCostUSD,4),
         " totalEstimatedCostsUSD=",DoubleToString(allKnownCostsUSD,4),
         " netExpectedUSD=",DoubleToString(netExpectedUSD,4),
         " netAtTPUSD=",DoubleToString(netTargetUSD,4),
         " rule=STRICTLY_POSITIVE_NET_EXPECTANCY_FOR_BUY_AND_SELL");
   return true;
}

double EstimateOrderRiskUSD(string symbol,double lots,double stopDistance)
{
   double tickValue=MarketInfo(symbol,MODE_TICKVALUE);
   double tickSizePrice=TickSizePriceForSymbol(symbol);
   if(tickValue<=0.0 || tickSizePrice<=0.0 || lots<=0.0 || stopDistance<=0.0) return -1.0;
   return lots*(stopDistance/tickSizePrice)*tickValue;
}

double PortfolioOpenRiskUSD()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(OrderStopLoss()<=0) return -1.0; // Unknown risk must fail closed.
      double risk=EstimateOrderRiskUSD(OrderSymbol(),OrderLots(),MathAbs(OrderOpenPrice()-OrderStopLoss()));
      if(risk<0) return -1.0;
      total+=risk;
   }
   return total;
}

void PrintOpenTradeBlockDetails()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      count++;
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      Print("OPEN TRADE DIAGNOSTIC | ticket=",OrderTicket(),
            " type=",(OrderType()==OP_BUY?"BUY":"SELL"),
            " symbol=",OrderSymbol()," magic=",OrderMagicNumber(),
            " lots=",DoubleToString(OrderLots(),2),
            " open=",DoubleToString(OrderOpenPrice(),Digits),
            " SL=",DoubleToString(OrderStopLoss(),Digits),
            " TP=",DoubleToString(OrderTakeProfit(),Digits),
            " netFloatingUSD=",DoubleToString(net,2),
            " opened=",TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS));
   }
   Print("OPEN TRADE COUNT DIAGNOSTIC | portfolioMatchingMarketPositions=",count,
         " configuredPortfolioMax=",EffectiveMaxOpenTrades()," chartSymbol=",Symbol()," magic=",InpMagic,
         " terminalOrdersTotal=",OrdersTotal());
}

double NormalizeLotsDown(double lots)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   if(step<=0) step=0.01;
   if(lots>maxLot) lots=maxLot;
   lots=MathFloor(lots/step+1e-8)*step;
   int lotDigits=2;
   if(step>=1.0) lotDigits=0; else if(step>=0.1) lotDigits=1; else if(step<0.01) lotDigits=3;
   lots=NormalizeDouble(lots,lotDigits);
   if(lots<minLot) return 0.0;
   return lots;
}

double CalculateLotsForRisk(double riskUSD,double stopDistancePrice)
{
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSizeRaw=MarketInfo(Symbol(),MODE_TICKSIZE);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double lotStep=MarketInfo(Symbol(),MODE_LOTSTEP);

   if(tickValue<=0 || tickSizeRaw<=0 || Point<=0 || stopDistancePrice<=0 ||
      minLot<=0 || maxLot<minLot || lotStep<=0)
   {
      Print("LOT SPEC ERROR | tickValue=",DoubleToString(tickValue,8),
            " tickSizeRaw=",DoubleToString(tickSizeRaw,10),
            " Point=",DoubleToString(Point,Digits+2),
            " minLot=",DoubleToString(minLot,4),
            " maxLot=",DoubleToString(maxLot,4),
            " lotStep=",DoubleToString(lotStep,4),
            " stopDistance=",DoubleToString(stopDistancePrice,Digits+2));
      return 0.0;
   }

   // MODE_TICKSIZE is used directly as a price increment for this broker; do not multiply by Point.
   double tickSizePrice=TickSizePriceForSymbol(Symbol());
   if(tickSizePrice<=0)
   {
      Print("LOT SPEC ERROR | normalized tick size is invalid. raw=",DoubleToString(tickSizeRaw,10));
      return 0.0;
   }

   double ticksToStop=stopDistancePrice/tickSizePrice;
   double pointSize=MarketInfo(Symbol(),MODE_POINT);
   double spreadPointsNow=MarketInfo(Symbol(),MODE_SPREAD);
   double estimatedSpreadSlipDistance=(MathMax(0.0,spreadPointsNow)+MathMax(0,InpSlippagePoints))*pointSize;
   double riskPerLot=(ticksToStop*tickValue)+(estimatedSpreadSlipDistance/tickSizePrice)*tickValue;
   double requestedRiskUSD=riskUSD;
   double capitalRiskCap=EffectiveOperatingCapitalUSD()*InpMaxRiskPerTradeCapitalPct/100.0;
   riskUSD=MathMin(riskUSD,MathMin(InpHardRiskCapUSD,capitalRiskCap));
   double rawLots=(riskPerLot>0.0?riskUSD/riskPerLot:0.0);
   double minLotRisk=minLot*riskPerLot;

   Print("LOT RISK BREAKDOWN | symbol=",Symbol(),
         " requestedRiskUSD=",DoubleToString(requestedRiskUSD,4),
         " effectiveRiskBudgetUSD=",DoubleToString(riskUSD,4),
         " capitalUSD=",DoubleToString(EffectiveOperatingCapitalUSD(),2),
         " capitalRiskCapUSD=",DoubleToString(capitalRiskCap,4),
         " stopDistancePrice=",DoubleToString(stopDistancePrice,Digits+2),
         " spreadPoints=",DoubleToString(spreadPointsNow,1),
         " slippagePoints=",InpSlippagePoints,
         " estimatedSpreadSlipDistance=",DoubleToString(estimatedSpreadSlipDistance,Digits+2),
         " stopRiskPerLotUSD=",DoubleToString(ticksToStop*tickValue,4),
         " estimatedEntryCostPerLotUSD=",DoubleToString((estimatedSpreadSlipDistance/tickSizePrice)*tickValue,4),
         " totalRiskPerLotUSD=",DoubleToString(riskPerLot,4),
         " rawLots=",DoubleToString(rawLots,6),
         " brokerMinLot=",DoubleToString(minLot,4),
         " minimumLotEstimatedRiskUSD=",DoubleToString(minLotRisk,4),
         " lotStep=",DoubleToString(lotStep,4),
         " brokerMaxLot=",DoubleToString(maxLot,4),
         " tickValue=",DoubleToString(tickValue,8),
         " tickSizeRaw=",DoubleToString(tickSizeRaw,10),
         " tickSizePrice=",DoubleToString(tickSizePrice,10),
         " | decision=LOT_DIAGNOSTICS_BEFORE_NORMALIZATION");
   Print("LOT CALC | riskBudgetUSD=",DoubleToString(riskUSD,2),
         " stopDistance=",DoubleToString(stopDistancePrice,Digits+2),
         " tickValue=",DoubleToString(tickValue,8),
         " tickSizeRaw=",DoubleToString(tickSizeRaw,10),
         " tickSizePrice=",DoubleToString(tickSizePrice,10),
         " riskPerLotUSD=",DoubleToString(riskPerLot,4),
         " rawLots=",DoubleToString(rawLots,6),
         " minLot=",DoubleToString(minLot,4),
         " minLotRiskUSD=",DoubleToString(minLotRisk,4),
         " lotStep=",DoubleToString(lotStep,4));

   // If broker lot granularity makes the requested target too small, permit the minimum lot
   // only in NORMAL non-provisional mode and only if its projected stop-risk fits the dynamic
   // budget passed by the caller. The caller separately enforces remaining global risk capacity.
   // Reduced-risk governor/provisional entries never use this exception.
   if(rawLots<minLot)
   {
      double capital=EffectiveOperatingCapitalUSD();
      double normalRisk=MathMin(InpRiskPerTradeUSD,capital);
      bool normalBudget=(riskUSD>=normalRisk-0.0001 && g_governorState==0 && !g_currentProvisionalEntry);
      if(normalBudget && minLotRisk<=riskUSD+0.0001)
      {
         Print("LOT MINIMUM ACCEPTED | requestedRiskUSD=",DoubleToString(riskUSD,2),
               " brokerMinLots=",DoubleToString(minLot,4),
               " projectedStopRiskUSD=",DoubleToString(minLotRisk,2),
               " dynamicBudgetUSD=",DoubleToString(riskUSD,2),
               " reason=within dynamic risk budget; portfolio and daily-loss gates remain authoritative");
         return NormalizeDouble(minLot,3);
      }
      string lotRejectReason="MINIMUM_LOT_RISK_EXCEEDS_AVAILABLE_BUDGET_OR_GOVERNOR_POLICY";
      if(minLotRisk>riskUSD+0.0001) lotRejectReason="MINIMUM_LOT_RISK_EXCEEDS_EFFECTIVE_RISK_BUDGET";
      else if(g_governorState!=0) lotRejectReason="MINIMUM_LOT_FALLBACK_BLOCKED_BY_GOVERNOR";
      else if(g_currentProvisionalEntry) lotRejectReason="MINIMUM_LOT_FALLBACK_BLOCKED_FOR_PROVISIONAL_EVIDENCE";
      Print("LOT REJECTION DETAIL | symbol=",Symbol()," reason=",lotRejectReason,
            " requestedRiskUSD=",DoubleToString(requestedRiskUSD,4),
            " effectiveRiskBudgetUSD=",DoubleToString(riskUSD,4),
            " brokerMinLot=",DoubleToString(minLot,4),
            " minimumLotEstimatedRiskUSD=",DoubleToString(minLotRisk,4),
            " stopDistancePrice=",DoubleToString(stopDistancePrice,Digits+2),
            " riskPerLotUSD=",DoubleToString(riskPerLot,4),
            " governorState=",IntegerToString(g_governorState),
            " provisionalEntry=",(g_currentProvisionalEntry?"true":"false"),
            " | decision=NO_ORDER");
      Print("LOT BLOCKED | broker minimum lot projected risk USD ",DoubleToString(minLotRisk,2),
            " exceeds dynamic budget or reduced-risk policy. requestedRiskUSD=",DoubleToString(riskUSD,2),
            " dynamicBudgetUSD=",DoubleToString(riskUSD,2),
            " governorState=",IntegerToString(g_governorState),
            " provisional=",(g_currentProvisionalEntry?"true":"false"),
            ". Risk limit preserved.");
      return 0.0;
   }
   double lots=NormalizeLotsDown(rawLots);
   if(lots<minLot || lots>maxLot)
   {
      Print("LOT REJECTION DETAIL | symbol=",Symbol()," reason=NORMALIZED_LOT_OUTSIDE_BROKER_MIN_MAX",
            " normalizedLots=",DoubleToString(lots,6)," rawLots=",DoubleToString(rawLots,6),
            " brokerMinLot=",DoubleToString(minLot,4)," brokerMaxLot=",DoubleToString(maxLot,4),
            " lotStep=",DoubleToString(lotStep,4)," effectiveRiskBudgetUSD=",DoubleToString(riskUSD,4),
            " minimumLotEstimatedRiskUSD=",DoubleToString(minLotRisk,4)," | decision=NO_ORDER");
      return 0.0;
   }
   double projectedRisk=lots*riskPerLot;
   if(projectedRisk>riskUSD+0.0001)
    {
       Print("LOT REJECTION DETAIL | symbol=",Symbol()," reason=NORMALIZED_LOT_PROJECTED_RISK_EXCEEDS_BUDGET",
             " normalizedLots=",DoubleToString(lots,6)," projectedRiskUSD=",DoubleToString(projectedRisk,4),
             " effectiveRiskBudgetUSD=",DoubleToString(riskUSD,4)," minimumLotEstimatedRiskUSD=",DoubleToString(minLotRisk,4),
             " brokerMinLot=",DoubleToString(minLot,4)," lotStep=",DoubleToString(lotStep,4),
             " stopDistancePrice=",DoubleToString(stopDistancePrice,Digits+2)," riskPerLotUSD=",DoubleToString(riskPerLot,4),
             " | decision=NO_ORDER");
      return 0.0;
   }
   return lots;
}

// Returns true only when a sufficiently losing, opposite-direction position was closed for a qualified candidate.
// This is a conservative heuristic using historical score, not a reliable forecast or guarantee of higher profit.
// A successful close does not guarantee that the subsequent OrderSend will succeed; all gates are rechecked.
// Compare the historical edge of the proposed direction with the incumbent direction,
// then charge estimated entry spread/slippage in R units. Historical scores are only
// estimates; this is a decision heuristic, not a forecast or profit guarantee.
// If the old trade is closed, the caller MUST re-run TradeGate before any replacement entry.
bool TryReplacePositionIfBetter(int candidateDirection,double candidateScore,double incumbentDirectionScore,string candidateStrategy)
{
   // SL/TP-only policy: retain existing positions; never close/reopen in this path.
   return false;
   if(!InpEnablePositionReplacement || candidateDirection==0) return false;
   int openCount=CountOpenTradesForSymbol();
   if(openCount!=1) return false; // Only compare the incumbent on this symbol; other symbols are managed independently.

   int ticket=-1,oldType=-1;
   double oldNet=0.0,oldLots=0.0,oldOpen=0.0,oldSL=0.0,oldTP=0.0;
   datetime oldTime=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      ticket=OrderTicket(); oldType=OrderType(); oldLots=OrderLots(); oldOpen=OrderOpenPrice();
      oldSL=OrderStopLoss(); oldTP=OrderTakeProfit(); oldTime=OrderOpenTime();
      oldNet=OrderProfit()+OrderSwap()+OrderCommission();
      break;
   }
   if(ticket<0) return false;
   int oldDirection=(oldType==OP_BUY?1:-1);
   if(oldDirection==candidateDirection)
   {
      // A same-direction candidate is not a second independent opportunity: opening it would
      // duplicate exposure. Compare the continuation edge with the best opposite-direction
      // historical baseline and report current floating P/L and stop-defined risk. Keep the
      // incumbent rather than close/reopen in the same direction and pay spread twice.
      double sameDirRisk=(oldSL>0.0?EstimateOrderRiskUSD(Symbol(),oldLots,MathAbs(oldOpen-oldSL)):-1.0);
      double currentSpreadPoints=MarketInfo(Symbol(),MODE_SPREAD);
      double currentPoint=MarketInfo(Symbol(),MODE_POINT);
      double estimatedCloseCostUSD=-1.0;
      if(currentSpreadPoints>=0.0 && currentPoint>0.0)
         estimatedCloseCostUSD=EstimateOrderRiskUSD(Symbol(),oldLots,currentSpreadPoints*currentPoint);
      if(estimatedCloseCostUSD>=0.0 && (estimatedCloseCostUSD>MathMax(10.0,EffectiveOperatingCapitalUSD()*0.10)))
         Print("EXECUTION COST SANITY WARNING | symbol=",Symbol()," spreadPoints=",DoubleToString(currentSpreadPoints,1)," point=",DoubleToString(currentPoint,10)," tickSizeRawPrice=",DoubleToString(MarketInfo(Symbol(),MODE_TICKSIZE),10)," tickValue=",DoubleToString(MarketInfo(Symbol(),MODE_TICKVALUE),8)," lots=",DoubleToString(oldLots,4)," estimatedCloseSpreadCostUSD=",DoubleToString(estimatedCloseCostUSD,4)," | review broker contract specification; cost is diagnostic, never bypasses risk gates.");
      bool oppositeBaselineValid=(incumbentDirectionScore > -1.0e90);
      double continuationAdvantage=(oppositeBaselineValid ? candidateScore-incumbentDirectionScore : 0.0);
      double continuationNetAdvantage=(oppositeBaselineValid && EffectiveRiskBudgetUSD()>0.0 && estimatedCloseCostUSD>=0.0 ?
         continuationAdvantage-estimatedCloseCostUSD/EffectiveRiskBudgetUSD() : 0.0);
      string oppositeBaselineText=(oppositeBaselineValid ? DoubleToString(incumbentDirectionScore,4) : "N/A");

      // Compare the incumbent's remaining SL/TP geometry with a fresh same-direction entry.
      // These are price-distance estimates, not probabilities or guaranteed expected returns.
      RefreshRates();
      double liveExitPrice=(oldDirection>0?Bid:Ask);
      double incumbentRemainingRewardDistance=0.0, incumbentRemainingRiskDistance=0.0;
      if(oldTP>0.0) incumbentRemainingRewardDistance=(oldDirection>0?oldTP-liveExitPrice:liveExitPrice-oldTP);
      if(oldSL>0.0) incumbentRemainingRiskDistance=(oldDirection>0?liveExitPrice-oldSL:oldSL-liveExitPrice);
      if(incumbentRemainingRewardDistance<0.0) incumbentRemainingRewardDistance=0.0;
      if(incumbentRemainingRiskDistance<0.0) incumbentRemainingRiskDistance=0.0;
      double incumbentRemainingRewardUSD=(incumbentRemainingRewardDistance>0.0?EstimateOrderRiskUSD(Symbol(),oldLots,incumbentRemainingRewardDistance):0.0);
      double incumbentRemainingRiskUSD=(incumbentRemainingRiskDistance>0.0?EstimateOrderRiskUSD(Symbol(),oldLots,incumbentRemainingRiskDistance):0.0);
      double atrNow=GetATR(1), riskBudgetNow=EffectiveRiskBudgetUSD();
      double freshLots=(atrNow>0.0 && riskBudgetNow>0.0?CalculateLotsForRisk(riskBudgetNow,atrNow*InpStopATR):0.0);
      double freshRiskUSD=(freshLots>0.0?EstimateOrderRiskUSD(Symbol(),freshLots,atrNow*InpStopATR):-1.0);
      double freshRewardUSD=(freshLots>0.0 && atrNow>0.0?EstimateOrderRiskUSD(Symbol(),freshLots,atrNow*InpTargetATR): -1.0);
      double freshSpreadCostUSD=(freshLots>0.0 && currentSpreadPoints>=0.0 && currentPoint>0.0?EstimateOrderRiskUSD(Symbol(),freshLots,currentSpreadPoints*currentPoint):-1.0);
      double freshSlippageCostUSD=(freshLots>0.0 && currentPoint>0.0?EstimateOrderRiskUSD(Symbol(),freshLots,InpSlippagePoints*currentPoint):-1.0);
      double holdRewardRiskRatio=(incumbentRemainingRiskUSD>0.0?incumbentRemainingRewardUSD/incumbentRemainingRiskUSD:-1.0);
      double freshRewardRiskRatio=(freshRiskUSD>0.0 && freshRewardUSD>=0.0?freshRewardUSD/freshRiskUSD:-1.0);
      double freshNetRewardUSD=(freshRewardUSD>=0.0 && freshSpreadCostUSD>=0.0 && freshSlippageCostUSD>=0.0?freshRewardUSD-freshSpreadCostUSD-freshSlippageCostUSD:-1.0);
      Print("POSITION ECONOMIC AUDIT | mode=HOLD_VS_FRESH_SAME_DIRECTION | ticket=",ticket,
            " existingNetUSD=",DoubleToString(oldNet,2),
            " incumbentRemainingRewardUSD=",DoubleToString(incumbentRemainingRewardUSD,2),
            " incumbentRemainingRiskUSD=",DoubleToString(incumbentRemainingRiskUSD,2),
            " incumbentRemainingRewardRiskRatio=",DoubleToString(holdRewardRiskRatio,3),
            " freshCandidateStrategy=",candidateStrategy,
            " freshCandidateExpectedRScore=",DoubleToString(candidateScore,4),
            " freshLots=",DoubleToString(freshLots,4),
            " freshRiskUSD=",DoubleToString(freshRiskUSD,2),
            " freshTargetRewardUSD=",DoubleToString(freshRewardUSD,2),
            " freshRewardRiskRatio=",DoubleToString(freshRewardRiskRatio,3),
            " freshSpreadCostUSD=",DoubleToString(freshSpreadCostUSD,4),
            " freshSlippageProxyUSD=",DoubleToString(freshSlippageCostUSD,4),
            " freshTargetRewardAfterEntryCostsUSD=",DoubleToString(freshNetRewardUSD,2),
            " | geometryOnly=true; reward/risk ratio is not win probability or expectancy.");
      Print("POSITION COMPARISON | action=COMPARE_HOLD_VS_CONTINUE | ticket=",ticket,
            " existingDirection=",(oldDirection>0?"BUY":"SELL"),
            " existingFloatingNetUSD=",DoubleToString(oldNet,2),
            " existingOpen=",DoubleToString(oldOpen,Digits),
            " existingSL=",DoubleToString(oldSL,Digits)," existingTP=",DoubleToString(oldTP,Digits),
            " existingRiskToSLUSD=",DoubleToString(sameDirRisk,2),
            " existingAgeMinutes=",IntegerToString((int)((TimeCurrent()-oldTime)/60)),
            " candidateDirection=",(candidateDirection>0?"BUY":"SELL"),
            " candidateStrategy=",candidateStrategy,
            " candidateExpectedRScore=",DoubleToString(candidateScore,4),
            " oppositeDirectionBaselineRScore=",oppositeBaselineText,
            " directionalEdgeAdvantageR=",DoubleToString(continuationAdvantage,4),
            " estimatedCloseSpreadCostUSD=",DoubleToString(estimatedCloseCostUSD,4),
            " netDirectionalAdvantageAfterEstimatedCostR=",(oppositeBaselineValid?DoubleToString(continuationNetAdvantage,4):"N/A"),
            " | scores are historical estimates, not forecasts; missing baseline is not treated as a valid advantage.");
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=SAME_DIRECTION_REPLACEMENT_NOT_PROVEN_NET_BETTER",
            " | ticket=",ticket," candidateStrategy=",candidateStrategy,
            " incumbentRemainingRewardUSD=",DoubleToString(incumbentRemainingRewardUSD,2),
            " incumbentRemainingRiskUSD=",DoubleToString(incumbentRemainingRiskUSD,2),
            " freshTargetRewardAfterEntryCostsUSD=",DoubleToString(freshNetRewardUSD,2),
            " | same-direction close/reopen is not authorized by model score or target geometry alone; expected-value comparison needs validated probabilities. Preserve current SL/TP; same-direction additions require all entry/risk gates; maxOpenTrades=",EffectiveMaxOpenTrades(),".");
      return false;
   }

   // A missing opposite-direction candidate is represented internally by -1.0e100.
   // Never compare or print that sentinel as a real score, and never replace without a valid baseline.
   if(incumbentDirectionScore < -1.0e90)
   {
      Print("OPPOSITE CANDIDATE AUDIT | status=INCOMPLETE | action=KEEP_CURRENT",
            " | reason=NO_QUALIFIED_HISTORICAL_BASELINE_FOR_INCUMBENT_DIRECTION",
            " | candidateDirection=",(candidateDirection>0?"BUY":"SELL"),
            " candidateStrategy=",candidateStrategy,
            " candidateScore=",DoubleToString(candidateScore,4),
            " incumbentDirectionScore=N/A | replacement comparison cannot be validated; no close or new order.");
      return false;
   }

   double riskUSD=EffectiveRiskBudgetUSD();
   double atrForCandidate=GetATR(1);
   double candidateLots=0.0;
   if(atrForCandidate>0.0 && riskUSD>0.0)
      candidateLots=CalculateLotsForRisk(riskUSD,atrForCandidate*InpStopATR);
   if(candidateLots<=0.0)
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=new candidate fails ATR/risk/lot validation before replacement comparison.");
      return false;
   }
   double portfolioRiskBefore=PortfolioOpenRiskUSD();
   double incumbentRisk=(oldSL>0.0?EstimateOrderRiskUSD(Symbol(),oldLots,MathAbs(oldOpen-oldSL)):-1.0);
   double candidateRisk=EstimateOrderRiskUSD(Symbol(),candidateLots,atrForCandidate*InpStopATR);
   if(portfolioRiskBefore<0.0 || incumbentRisk<0.0 || candidateRisk<0.0 ||
      portfolioRiskBefore-incumbentRisk+candidateRisk>EffectivePortfolioRiskCapUSD()+0.0001)
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=PORTFOLIO_RISK_CAP_WOULD_BE_EXCEEDED_BY_REPLACEMENT",
            " | portfolioRiskUSD=",DoubleToString(portfolioRiskBefore,2),
            " incumbentRiskUSD=",DoubleToString(incumbentRisk,2),
            " candidateRiskUSD=",DoubleToString(candidateRisk,2),
            " capUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),2),
            " | old position remains open; no replacement close permitted.");
      return false;
   }
   double pointSize=MarketInfo(Symbol(),MODE_POINT);
   double spreadPoints=MarketInfo(Symbol(),MODE_SPREAD);
   double spreadCostUSD=-1.0;
   double slippageCostUSD=-1.0;
   if(pointSize>0.0 && spreadPoints>=0.0)
   {
      double oldSpreadCost=EstimateOrderRiskUSD(Symbol(),oldLots,spreadPoints*pointSize);
      double newSpreadCost=EstimateOrderRiskUSD(Symbol(),candidateLots,spreadPoints*pointSize);
      if(oldSpreadCost>=0.0 && newSpreadCost>=0.0) spreadCostUSD=oldSpreadCost+newSpreadCost;
      double oldSlipCost=EstimateOrderRiskUSD(Symbol(),oldLots,InpSlippagePoints*pointSize);
      double newSlipCost=EstimateOrderRiskUSD(Symbol(),candidateLots,InpSlippagePoints*pointSize);
      if(oldSlipCost>=0.0 && newSlipCost>=0.0) slippageCostUSD=oldSlipCost+newSlipCost; // one close + one entry
   }
   if(spreadCostUSD<0.0 || slippageCostUSD<0.0)
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=EXECUTION_COST_CANNOT_BE_VALIDATED | tick conversion/specification invalid; no replacement close permitted.");
      return false;
   }
   if(spreadCostUSD>MathMax(10.0,EffectiveOperatingCapitalUSD()*0.10))
   {
      Print("EXECUTION COST SANITY WARNING | symbol=",Symbol()," spreadPoints=",DoubleToString(spreadPoints,1)," point=",DoubleToString(pointSize,10)," tickSizeRawPrice=",DoubleToString(MarketInfo(Symbol(),MODE_TICKSIZE),10)," tickValue=",DoubleToString(MarketInfo(Symbol(),MODE_TICKVALUE),8)," oldLots=",DoubleToString(oldLots,4)," candidateLots=",DoubleToString(candidateLots,4)," estimatedTwoLegSpreadCostUSD=",DoubleToString(spreadCostUSD,4)," | replacement cost may be invalid; fail-safe KEEP_CURRENT.");
      return false;
   }
   double estimatedExecutionCostUSD=spreadCostUSD+slippageCostUSD;
   double estimatedExecutionCostR=(riskUSD>0.0?estimatedExecutionCostUSD/riskUSD:1.0e6);
   double netEdgeAdvantage=candidateScore-incumbentDirectionScore-estimatedExecutionCostR;

   Print("POSITION COMPARISON | action=COMPARE_HOLD_VS_REVERSE | existingTicket=",ticket,
         " existingDirection=",(oldDirection>0?"BUY":"SELL"),
         " existingFloatingNetUSD=",DoubleToString(oldNet,2),
         " existingOpen=",DoubleToString(oldOpen,Digits),
         " existingSL=",DoubleToString(oldSL,Digits)," existingTP=",DoubleToString(oldTP,Digits),
         " existingAgeMinutes=",IntegerToString((int)((TimeCurrent()-oldTime)/60)),
         " candidateDirection=",(candidateDirection>0?"BUY":"SELL"),
         " candidateStrategy=",candidateStrategy,
         " candidateHistoricalExpectedRScore=",DoubleToString(candidateScore,4),
         " incumbentHistoricalExpectedRScore=",DoubleToString(incumbentDirectionScore,4),
         " rawEdgeAdvantage=",DoubleToString(candidateScore-incumbentDirectionScore,4),
         " spreadPoints=",DoubleToString(spreadPoints,1),
         " estimatedSpreadCostUSD=",DoubleToString(spreadCostUSD,4),
         " estimatedRoundTripSlippageUSD=",DoubleToString(slippageCostUSD,4),
         " estimatedExecutionCostR=",DoubleToString(estimatedExecutionCostR,4),
         " netEdgeAdvantageAfterCosts=",DoubleToString(netEdgeAdvantage,4),
         " requiredNetAdvantage=",DoubleToString(InpReplacementMinScoreAdvantage,4),
         " | historical scores are estimates, not forecast guarantees.");

   // Unlike the prior version, the incumbent need not be losing: a sufficiently strong,
   // cost-adjusted reversal can justify exiting a profitable or near-breakeven position too.
   if(candidateScore<InpReplacementMinExpectedRScore)
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=REVERSE_EDGE_BELOW_MINIMUM | candidateScore=",
            DoubleToString(candidateScore,4)," requiredScore=",DoubleToString(InpReplacementMinExpectedRScore,4));
      return false;
   }
   if(netEdgeAdvantage<InpReplacementMinScoreAdvantage)
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=REVERSE_EDGE_NOT_ENOUGH_AFTER_COSTS | netAdvantage=",
            DoubleToString(netEdgeAdvantage,4)," required=",DoubleToString(InpReplacementMinScoreAdvantage,4),
            " | keep incumbent; do not churn on a weak or costly reversal.");
      return false;
   }
   if(InpMode!=AUTO_EXECUTION || !IsTradeAllowed() || MarketInfo(Symbol(),MODE_TRADEALLOWED)==0 || IsTradeContextBusy())
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=execution permission/context gate prevents safe replacement.");
      return false;
   }
   if(AccountCurrency()!="USD" || EffectiveOperatingCapitalUSD()<=0.0)
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=USD operating-capital validation failed.");
      return false;
   }
   if(MaxSpreadForCurrentSymbol()<=0 || spreadPoints>MaxSpreadForCurrentSymbol())
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=spread gate prevents replacement | spreadPoints=",
            DoubleToString(spreadPoints,1)," max=",MaxSpreadForCurrentSymbol());
      return false;
   }
   if(TodayNetProfit()<=-EffectiveDailyLossLimitUSD())
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=DAILY_LOSS_LIMIT_PREVENTS_REPLACEMENT | dailyNetUSD=",DoubleToString(TodayNetProfit(),2),
            " dailyLossLimitUSD=",DoubleToString(EffectiveDailyLossLimitUSD(),2));
      return false;
   }
   double atr=GetATR(1);
   double risk=EffectiveRiskBudgetUSD();
   if(atr<=0.0 || risk<=0.0 || CalculateLotsForRisk(risk,atr*InpStopATR)<=0.0)
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=new candidate fails pre-close ATR/risk/lot validation.");
      return false;
   }

   Print("OPPOSITE CANDIDATE AUDIT | status=PASS_PRECHECK | action=WOULD_REPLACE_IF_EXECUTION_ENABLED",
         " | ticket=",ticket," existingDirection=",(oldDirection>0?"BUY":"SELL"),
         " candidateDirection=",(candidateDirection>0?"BUY":"SELL"),
         " candidateStrategy=",candidateStrategy,
         " candidateScore=",DoubleToString(candidateScore,4),
         " incumbentScore=",DoubleToString(incumbentDirectionScore,4),
         " netAdvantageAfterCosts=",DoubleToString(netEdgeAdvantage,4),
         " spreadPoints=",DoubleToString(spreadPoints,1),
         " effectiveCapitalUSD=",DoubleToString(EffectiveOperatingCapitalUSD(),2),
         " riskBudgetUSD=",DoubleToString(risk,2),
         " dailyTrades=",CountTodayTrades(),"/",InpMaxTradesPerDay,
         " dailyNetUSD=",DoubleToString(TodayNetProfit(),2),
         " dailyLossLimitUSD=",DoubleToString(EffectiveDailyLossLimitUSD(),2),
         " | all current pre-close replacement checks passed.");
   if(InpPositionReplacementAuditOnly)
   {
      Print("POSITION DECISION | action=KEEP_CURRENT | result=AUDIT_ONLY_WOULD_REPLACE",
            " | ticket=",ticket," remains open; no OrderClose and no replacement OrderSend",
            " | reason=InpPositionReplacementAuditOnly=true; validate comparison logs in demo before enabling execution.");
      return false;
   }

   RefreshRates();
   double closePrice=NormalizeDouble(oldType==OP_BUY?Bid:Ask,Digits);
   ResetLastError();
   if(!OrderClose(ticket,oldLots,closePrice,InpSlippagePoints,clrNONE))
   {
      int err=GetLastError();
      Print("POSITION DECISION | action=KEEP_CURRENT | result=REPLACEMENT_CLOSE_FAILED | ticket=",ticket,
            " error=",err," | old position remains; no new order will be sent.");
      return false;
   }
   Print("POSITION DECISION | action=REPLACE_POSITION | result=OLD_POSITION_CLOSED | ticket=",ticket,
         " oldDirection=",(oldDirection>0?"BUY":"SELL")," oldFloatingNetBeforeCloseUSD=",DoubleToString(oldNet,2),
         " candidateDirection=",(candidateDirection>0?"BUY":"SELL")," candidateStrategy=",candidateStrategy,
         " candidateScore=",DoubleToString(candidateScore,4),
         " netEdgeAdvantageAfterCosts=",DoubleToString(netEdgeAdvantage,4),
         " | next=caller rechecks all standard gates before sending; if rejected, remain flat.");
   return true;
}

bool TradeGate(string &reason)
{
   reason="OK";
   UpdateRiskGovernor();
   if(InpMode!=AUTO_EXECUTION) { reason="OBSERVE_ONLY mode"; return false; }
   // Account classification (IsDemo) is informational only; DEMO and REAL accounts follow the same risk gates.
   if(!IsTradeAllowed()) { reason="terminal or EA trading not allowed"; return false; }
   // Do not send an order when the broker explicitly marks this symbol as non-tradable.
   // This is a diagnostic gate, not a bypass: server/account restrictions still apply at OrderSend.
   if(MarketInfo(Symbol(),MODE_TRADEALLOWED)==0)
   {
      reason="broker reports SYMBOL_TRADING_DISABLED (MODE_TRADEALLOWED=false)";
      return false;
   }
   if(AccountCurrency()!="USD") { reason="account currency is not USD; cannot verify USD risk budget safely"; return false; }
   if(EffectiveOperatingCapitalUSD()<=0.0) { reason="fixed virtual USD500 operating allocation is invalid"; return false; }
   if(MaxSpreadForCurrentSymbol()<=0) { reason="unsupported symbol spread configuration"; return false; }
   if(MarketInfo(Symbol(),MODE_SPREAD)>MaxSpreadForCurrentSymbol()) { reason="spread gate for "+Symbol(); return false; }
   AuditPortfolioBeforeEntry();
   int openTradeCount=CountOpenTrades();
   int sameSymbolCount=CountOpenTradesForSymbol();
   if(sameSymbolCount>=InpMaxPositionsPerAsset)
   {
      reason="one-position-per-asset limit already reached";
      Print("ORDER BLOCKED | reason=SYMBOL_POSITION_CAP | symbol=",Symbol(),
            " sameCanonicalAssetOpen=",sameSymbolCount," maxPositionsPerAsset=",InpMaxPositionsPerAsset,
            " | no further same-symbol entry; SL/TP supervision continues.");
      return false;
   }
   if(IsCryptoLikeSymbol(Symbol()) && CountOpenCryptoPositions()>=InpCrossAssetMaxCryptoPositions)
   {
      reason="crypto correlation concentration limit reached";
      Print("ORDER BLOCKED | reason=CRYPTO_CONCENTRATION_LIMIT | candidateSymbol=",Symbol(),
            " cryptoOpen=",CountOpenCryptoPositions()," maxCrypto=",InpCrossAssetMaxCryptoPositions,
            " | total portfolio slots do not override the crypto concentration guard.");
      return false;
   }
   if(openTradeCount>=EffectiveMaxOpenTrades())
   {
      reason="maximum open trades reached (count="+IntegerToString(openTradeCount)+
             ", max="+IntegerToString(EffectiveMaxOpenTrades())+")";
      PrintOpenTradeBlockDetails();
      return false;
   }
if(TodayNetProfit()<=-EffectiveDailyLossLimitUSD()) { reason="portfolio daily loss limit reached"; return false; }
double openRisk=PortfolioOpenRiskUSD();
   if(openRisk<0.0) { reason="portfolio open risk unknown (missing SL or invalid tick specification)"; return false; }
   if(openRisk>=EffectivePortfolioRiskCapUSD()) { reason="portfolio open-risk cap already reached"; return false; }
   if(IsTradeContextBusy()) { reason="trade context busy"; return false; }
   return true;
}

bool SendOrderUnlocked(int direction)
{
   g_lastExecutionResult="ORDER_NOT_SENT";
   string gateReason="";
   if(!TradeGate(gateReason))
   {
      g_lastExecutionResult="BLOCKED_BY_RISK_GATE: "+gateReason;
      Print("ORDER BLOCKED | reason=",gateReason," | mode=",(InpMode==AUTO_EXECUTION?"AUTO_EXECUTION":"OBSERVE_ONLY"),
            " | currency=",AccountCurrency()," effectiveCapitalUSD=",DoubleToString(EffectiveOperatingCapitalUSD(),2),
            " spreadPoints=",DoubleToString(MarketInfo(Symbol(),MODE_SPREAD),1),
            " tradesToday=",CountTodayTrades(),"/",InpMaxTradesPerDay,
            " openPositions=",CountOpenTrades(),"/",EffectiveMaxOpenTrades(),
            " dailyNetUSD=",DoubleToString(TodayNetProfit(),2),
            " dailyLossLimitUSD=",DoubleToString(EffectiveDailyLossLimitUSD(),2),
            " tradeAllowed=",(IsTradeAllowed()?"true":"false"),
            " contextBusy=",(IsTradeContextBusy()?"true":"false"));
      return false;
   }
   RefreshRates();
   double atr=GetATR(1);
   if(atr<=0) { g_lastExecutionResult="BLOCKED_INVALID_ATR"; Print("ORDER BLOCKED | invalid ATR"); return false; }
   double stopDistance=atr*InpStopATR;
   double targetDistance=atr*InpTargetATR;
   double riskUSD=EffectiveRiskBudgetUSD();
   if(riskUSD<=0) { g_lastExecutionResult="BLOCKED_ZERO_RISK_BUDGET"; Print("ORDER BLOCKED | calculated risk is zero"); return false; }
   double lots=CalculateLotsForRisk(riskUSD,stopDistance);
   if(lots<=0) { g_lastExecutionResult="BLOCKED_LOT_CALCULATION_OR_MINIMUM_LOT_RISK"; Print("ENTRY REJECTION DETAIL | symbol=",Symbol()," direction=",(direction>0?"BUY":"SELL")," reason=LOT_CALCULATION_RETURNED_ZERO"," riskBudgetUSD=",DoubleToString(riskUSD,4)," stopDistancePrice=",DoubleToString(stopDistance,Digits+2)," brokerMinLot=",DoubleToString(MarketInfo(Symbol(),MODE_MINLOT),4)," lotStep=",DoubleToString(MarketInfo(Symbol(),MODE_LOTSTEP),4)," minimumLotRiskRequiresReview=true | no order sent; see LOT RISK BREAKDOWN / LOT REJECTION DETAIL above."); return false; }
   double currentPortfolioRisk=PortfolioOpenRiskUSD();
   double proposedRisk=EstimateOrderRiskUSD(Symbol(),lots,stopDistance);
   if(currentPortfolioRisk<0.0 || proposedRisk<0.0 || proposedRisk>InpHardRiskCapUSD+0.0001 || currentPortfolioRisk+proposedRisk>EffectivePortfolioRiskCapUSD()+0.0001)
   {
      g_lastExecutionResult="BLOCKED_PORTFOLIO_OPEN_RISK_CAP";
      Print("ORDER BLOCKED | reason=PORTFOLIO_OPEN_RISK_CAP | openRiskUSD=",DoubleToString(currentPortfolioRisk,2),
            " proposedRiskUSD=",DoubleToString(proposedRisk,2)," capUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),2),
            " | no order sent; existing positions unchanged.");
      return false;
   }

   int type=(direction>0?OP_BUY:OP_SELL);
   double price=(direction>0?Ask:Bid);
   double sl=(direction>0?price-stopDistance:price+stopDistance);
   double tp=(direction>0?price+targetDistance:price-targetDistance);
   if(!ValidatePositiveExpectedNetProfit(Symbol(),lots,g_currentExpectedR,stopDistance,targetDistance,
                                         (direction>0?"BUY":"SELL"),"CHART_LOCAL_BEST_MODEL"))
   {
      g_lastExecutionResult="BLOCKED_GLOBAL_POSITIVE_NET_EXPECTANCY_GATE";
      return false;
   }
   int stopLevel=(int)MarketInfo(Symbol(),MODE_STOPLEVEL);
   double minStop=stopLevel*Point;
   if(MathAbs(price-sl)<minStop || MathAbs(tp-price)<minStop)
   {
      g_lastExecutionResult="BLOCKED_BROKER_STOP_LEVEL";
      Print("ORDER BLOCKED | reason=BROKER_STOP_LEVEL | stopLevelPoints=",stopLevel,
            " minimumDistance=",DoubleToString(minStop,Digits)," stopDistance=",DoubleToString(stopDistance,Digits),
            " targetDistance=",DoubleToString(targetDistance,Digits)," | action=NO_ORDER; SL/TP would violate broker minimum distance.");
      return false;
   }
   price=NormalizeDouble(price,Digits); sl=NormalizeDouble(sl,Digits); tp=NormalizeDouble(tp,Digits);
   // Final execution-time guard protects the invariant across every chart-local entry path.
   int finalAssetPositions=CountOpenTradesForSymbol();
   if(finalAssetPositions>0)
   {
      g_lastExecutionResult="BLOCKED_ONE_POSITION_PER_CANONICAL_ASSET_FINAL_CHECK";
      Print("ORDER BLOCKED | reason=ONE_POSITION_PER_CANONICAL_ASSET | canonicalAsset=",CanonicalAssetKey(Symbol()),
            " existingPositions=",finalAssetPositions," | final pre-OrderSend check; no order sent; existing positions unchanged.");
      return false;
   }
   string symbolGuardReason="";
   string expectedAssetKey=CanonicalAssetKey(Symbol());
   if(!ValidateExecutionAssetSymbol(Symbol(),expectedAssetKey,symbolGuardReason) || !IsAllowedMultiAssetSymbol())
   {
      g_lastExecutionResult="BLOCKED_ASSET_SYMBOL_MISMATCH";
      Print("ORDER BLOCKED | requestedSymbol=",Symbol()," canonicalAsset=",expectedAssetKey,
            " reason=ASSET_SYMBOL_MISMATCH_OR_INVALID_QUOTE detail=",symbolGuardReason,
            " allowedAsset=",(IsAllowedMultiAssetSymbol()?"true":"false")," | no order sent.");
      return false;
   }
   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,InpSlippagePoints,sl,tp,"Bitey SBT v1.76.0 "+expectedAssetKey,InpMagic,0,clrNONE);
   if(ticket<0)
   {
      int sendError=GetLastError();
      g_lastExecutionResult="ORDER_SEND_ERROR_"+IntegerToString(sendError);
      Print("ORDER ERROR | code=",sendError," description=",TradeErrorDescription(sendError),
            " direction=",(direction>0?"BUY":"SELL")," lots=",DoubleToString(lots,3),
            " requestedRiskUSD=",DoubleToString(riskUSD,2)," price=",DoubleToString(price,Digits),
            " SL=",DoubleToString(sl,Digits)," TP=",DoubleToString(tp,Digits),
            " spreadPoints=",DoubleToString(MarketInfo(Symbol(),MODE_SPREAD),1),
            " symbolTradeAllowed=",(MarketInfo(Symbol(),MODE_TRADEALLOWED)!=0?"true":"false"),
            " terminalTradeAllowed=",(IsTradeAllowed()?"true":"false"),
            " accountTradeAllowed=",(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0?"true":"false"),
            " accountExpertAllowed=",(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)!=0?"true":"false"),
            " expertEnabled=",(IsExpertEnabled()?"true":"false"),
            " accountServer=",AccountServer()," accountCompany=",AccountCompany(),
            " freeMargin=",DoubleToString(AccountFreeMargin(),2),
            " action=do_not_bypass_or_retry_133; compare accountTradeAllowed/accountExpertAllowed with broker permissions; verify symbol contract, account authorization, and trading session | order was not confirmed open.");
      return false;
   }
   double actualRiskUSD=EstimateOrderRiskUSD(Symbol(),lots,stopDistance);
   if(actualRiskUSD<0.0)
   {
      Print("ORDER RISK AUDIT WARNING | ticket=",ticket," reason=POST_ENTRY_RISK_SPEC_INVALID estimatedRiskUSD=UNKNOWN; inspect broker tick specification immediately.");
      actualRiskUSD=riskUSD; // Preserve an auditable conservative fallback; do not expand any risk budget.
   }
   if(OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))
   {
      bool rb=(OrderStopLoss()>0.0 && OrderTakeProfit()>0.0 && MathAbs(OrderStopLoss()-sl)<=MathMax(Point,MarketInfo(Symbol(),MODE_TICKSIZE))*1.5 && MathAbs(OrderTakeProfit()-tp)<=MathMax(Point,MarketInfo(Symbol(),MODE_TICKSIZE))*1.5);
      double rbRisk=(OrderStopLoss()>0.0?EstimateOrderRiskUSD(OrderSymbol(),OrderLots(),MathAbs(OrderOpenPrice()-OrderStopLoss())):-1.0);
      Print("ORDER SLTP READBACK AUDIT | source=CHART ticket=",ticket," symbol=",OrderSymbol()," magic=",OrderMagicNumber(),
         " requestedSL=",DoubleToString(sl,Digits)," confirmedSL=",DoubleToString(OrderStopLoss(),Digits),
         " requestedTP=",DoubleToString(tp,Digits)," confirmedTP=",DoubleToString(OrderTakeProfit(),Digits),
         " readbackMatch=",(rb?"true":"false")," stopRiskUSD=",(rbRisk>=0.0?DoubleToString(rbRisk,2):"UNKNOWN"),
         " status=",(rb?"SERVER_READBACK_CONFIRMED":"WARNING_REVIEW_IMMEDIATELY"));
   }
   else Print("ORDER SLTP READBACK AUDIT | source=CHART ticket=",ticket," status=SELECT_TICKET_FAILED error=",GetLastError());
   StoreEntryExperience(ticket,direction,actualRiskUSD);
   g_lastExecutionResult="ORDER_OPENED_TICKET_"+IntegerToString(ticket);
   Print("ORDER OPENED | ticket=",ticket," direction=",(direction>0?"BUY":"SELL"),
         " lots=",DoubleToString(lots,3)," riskBudgetUSD=",DoubleToString(riskUSD,2),
         " estimatedStopRiskUSD=",DoubleToString(actualRiskUSD,2),
         " entry=",DoubleToString(price,Digits)," SL=",DoubleToString(sl,Digits)," TP=",DoubleToString(tp,Digits),
         " strategy=",g_currentBestStrategy," | reason=",(StringFind(g_currentBestStrategy,"ONE_SHOT_TEST")>=0?"one-shot functional test passed all risk and broker gates":"directional signal passed evidence and all pre-trade gates"),".");
   return true;
}

string PortfolioEntryLockKey()
{
   return "BiteyEntryLock_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic);
}

bool AcquirePortfolioEntryLock()
{
   string key=PortfolioEntryLockKey();
   if(!GlobalVariableCheck(key)) GlobalVariableSet(key,0.0);
   for(int attempt=0;attempt<4;attempt++)
   {
      double oldValue=GlobalVariableGet(key);
      double nowValue=(double)TimeCurrent();
      if(oldValue!=0.0 && nowValue-oldValue<15.0) return false;
      if(GlobalVariableSetOnCondition(key,nowValue,oldValue)) return true;
   }
   return false;
}

void ReleasePortfolioEntryLock()
{
   string key=PortfolioEntryLockKey();
   if(GlobalVariableCheck(key)) GlobalVariableSet(key,0.0);
}

bool SendOrder(int direction)
{
   if(!AcquirePortfolioEntryLock())
   {
      g_lastExecutionResult="BLOCKED_PORTFOLIO_ENTRY_LOCK_BUSY";
      Print("ORDER BLOCKED | reason=PORTFOLIO_ENTRY_LOCK_BUSY | another chart instance is evaluating/submitting an order; retry only on a later valid evaluation.");
      return false;
   }
   bool result=SendOrderUnlocked(direction);
   ReleasePortfolioEntryLock();
   return result;
}

void AuditModelSignalFrequency()
{
   // Diagnostic only: counts historical signal triggers, never changes evidence thresholds or trade permission.
   int buyCount[MODEL_COUNT];
   int sellCount[MODEL_COUNT];
   // Explicitly initialize both fixed arrays before any possible read.
   ArrayInitialize(buyCount,0);
   ArrayInitialize(sellCount,0);
   int available=MathMin(MathMax(1,InpSignalAuditBars),Bars-InpTrendEMA-InpDonchianPeriod-InpMomentumLookback-20);
   if(available<1)
   {
      Print("MODEL SIGNAL AUDIT | status=SKIPPED reason=INSUFFICIENT_BARS bars=",Bars,
            " required=",(InpTrendEMA+InpDonchianPeriod+InpMomentumLookback+21));
      return;
   }
   int t=0,m=0,d=0,r=0,sr=0,a=0,sb=0,rd=0,ht=0,vw=0,br=0,fp=0,vs=0,lr=0,mc=0,be=0;
   int validBars=0;
   for(int shift=1;shift<=available;shift++)
   {
      if(!GetModelSignals(shift,t,m,d,r,sr,a,sb,rd,ht,vw,br,fp,vs,lr,mc,be)) continue;
      validBars++;
      if(vw>0) buyCount[9]++; else if(vw<0) sellCount[9]++;
      if(br>0) buyCount[10]++; else if(br<0) sellCount[10]++;
      if(fp>0) buyCount[11]++; else if(fp<0) sellCount[11]++;
      if(vs>0) buyCount[12]++; else if(vs<0) sellCount[12]++;
      if(lr>0) buyCount[13]++; else if(lr<0) sellCount[13]++;
      if(mc>0) buyCount[14]++; else if(mc<0) sellCount[14]++;
      if(be>0) buyCount[15]++; else if(be<0) sellCount[15]++;
      if(t>0) buyCount[0]++; else if(t<0) sellCount[0]++;
      if(m>0) buyCount[1]++; else if(m<0) sellCount[1]++;
      if(d>0) buyCount[2]++; else if(d<0) sellCount[2]++;
      if(r>0) buyCount[3]++; else if(r<0) sellCount[3]++;
      if(sr>0) buyCount[4]++; else if(sr<0) sellCount[4]++;
      if(a>0) buyCount[5]++; else if(a<0) sellCount[5]++;
      if(sb>0) buyCount[6]++; else if(sb<0) sellCount[6]++;
      if(rd>0) buyCount[7]++; else if(rd<0) sellCount[7]++;
      if(ht>0) buyCount[8]++; else if(ht<0) sellCount[8]++;
   }
   Print("MODEL SIGNAL AUDIT | source=GetModelSignals_SHARED_WITH_LIVE_ENGINE | lookbackClosedBars=",available," validBars=",validBars,
         " | counts are triggers before evidence/risk gates; counts are not trade results; no thresholds changed.");
   for(int model=0;model<MODEL_COUNT;model++)
      Print("MODEL SIGNAL FREQUENCY | model=",g_modelNames[model],
            " buyTriggers=",buyCount[model]," sellTriggers=",sellCount[model],
            " totalTriggers=",(buyCount[model]+sellCount[model]),
            " triggerRatePct=",DoubleToString(validBars>0?100.0*(buyCount[model]+sellCount[model])/validBars:0.0,2),
            " lookback=",validBars," metric=TRIGGER_FREQUENCY_NOT_PROFITABILITY");
}

void AuditRangeSignalConditions()
{
   // Diagnostic only: counts which exact condition prevents MEANREV/STRICT_RANGE triggers.
   int available=MathMin(MathMax(1,InpSignalAuditBars),Bars-InpTrendEMA-InpDonchianPeriod-InpMomentumLookback-20);
   if(available<1) return;
   int valid=0;
   int meanAdx=0,meanBuyRsi=0,meanSellRsi=0;
   int srAdx=0,srEma=0,srBoth=0;
   int srBuyEdge=0,srBuyRsi=0,srBuyFinal=0;
   int srSellEdge=0,srSellRsi=0,srSellFinal=0;
   int lookback=MathMax(3,InpStrictRangeLookback);
   for(int sh=1;sh<=available;sh++)
   {
      double c=iClose(Symbol(),Period(),sh),o=iOpen(Symbol(),Period(),sh);
      double atr=GetATR(sh);
      double ef=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh);
      double es=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh);
      double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh);
      double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,sh);
      if(c<=0 || atr<=0 || ef<=0 || es<=0) continue;
      valid++;
      if(adx<=InpMeanRevADXMax)
      {
         meanAdx++;
         if(rsi<=InpMeanRevRSIBuy) meanBuyRsi++;
         if(rsi>=InpMeanRevRSISell) meanSellRsi++;
      }
      double rh=-1.0e100,rl=1.0e100;
      for(int k=sh+1;k<=sh+lookback;k++)
      {
         double h=iHigh(Symbol(),Period(),k),l=iLow(Symbol(),Period(),k);
         if(h>rh) rh=h;
         if(l<rl) rl=l;
      }
      bool adxOK=(adx<=InpStrictRangeADXMax);
      bool emaOK=(MathAbs(ef-es)<=InpStrictRangeEMAGapATR*atr);
      if(adxOK) srAdx++;
      if(emaOK) srEma++;
      if(adxOK && emaOK)
      {
         srBoth++;
         bool buyEdge=(c<=rl+InpStrictRangeEdgeATR*atr);
         bool sellEdge=(c>=rh-InpStrictRangeEdgeATR*atr);
         if(buyEdge)
         {
            srBuyEdge++;
            if(rsi<=InpStrictRangeBuyRSI)
            {
               srBuyRsi++;
               srBuyFinal++;
            }
         }
         if(sellEdge)
         {
            srSellEdge++;
            if(rsi>=InpStrictRangeSellRSI)
            {
               srSellRsi++;
               srSellFinal++;
            }
         }
      }
   }
   Print("RANGE CONDITION AUDIT | lookback=",available," validBars=",valid,
         " | MEANREV adxEligible=",meanAdx," buyRSIEligible=",meanBuyRsi," sellRSIEligible=",meanSellRsi,
         " | STRICT_RANGE adxEligible=",srAdx," emaCompressionEligible=",srEma," bothEligible=",srBoth,
         " buyEdge=",srBuyEdge," buyEdgeAndRSI=",srBuyRsi," buyFinalAfterRSI=",srBuyFinal,
         " sellEdge=",srSellEdge," sellEdgeAndRSI=",srSellRsi," sellFinalAfterRSI=",srSellFinal,
         " | v1.63: continuous Market Watch ranking, no daily profit target or entry quota, fixed USD500, canonical one-position guard, SL/TP-only management; daily loss/aggregate/per-trade risk gates preserved.");
}

// v1.44 diagnostic-only audit: explain why the current completed candle did not
// trigger a model. This function must never create/alter a signal or relax a gate.
string AuditFlag(bool ok)
{
   return (ok ? "PASS" : "FAIL");
}

void AuditAdd(string &out,string label,bool ok)
{
   if(out!="") out+=";";
   out+=label+"="+AuditFlag(ok);
}

// v1.46: per-model condition audit mirrors the live signal formulas. Diagnostic only:
// it does not assign signals, modify evidence, relax gates, or authorize an order.
void AuditDetailedModelConditions(int model,int sh,int actualSignal)
{
   double c=iClose(Symbol(),Period(),sh), o=iOpen(Symbol(),Period(),sh);
   double h=iHigh(Symbol(),Period(),sh), l=iLow(Symbol(),Period(),sh);
   double c2=iClose(Symbol(),Period(),sh+1);
   double atr=GetATR(sh);
   double ef=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh);
   double es=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh);
   double et=iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,sh);
   double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh);
   double pdi=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_PLUSDI,sh);
   double mdi=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MINUSDI,sh);
   double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,sh);
   if(c<=0 || c2<=0 || atr<=0 || ef<=0 || es<=0 || et<=0)
   {
      Print("MODEL TRIGGER AUDIT | model=",g_modelNames[model]," currentSignal=",actualSignal,
            " status=SKIPPED reason=INVALID_INDICATOR_DATA | diagnosticOnly=true");
      return;
   }
   string buy="",sell="";
   double momOld=iClose(Symbol(),Period(),sh+InpMomentumLookback);
   double mom=(momOld>0?(c-momOld)/atr:0.0);
   double priorHigh=-1.0e100,priorLow=1.0e100;
   for(int k=sh+1;k<=sh+InpDonchianPeriod;k++) { priorHigh=MathMax(priorHigh,iHigh(Symbol(),Period(),k)); priorLow=MathMin(priorLow,iLow(Symbol(),Period(),k)); }
   double buffer=MathMax(0.0,InpBreakoutBufferATR)*atr;
   double rh=-1.0e100,rl=1.0e100;
   int srN=MathMax(3,InpStrictRangeLookback);
   for(int sr=sh+1;sr<=sh+srN;sr++) { rh=MathMax(rh,iHigh(Symbol(),Period(),sr)); rl=MathMin(rl,iLow(Symbol(),Period(),sr)); }
   double rangeSum=0.0;
   for(int n=sh+1;n<=sh+10;n++) rangeSum+=iHigh(Symbol(),Period(),n)-iLow(Symbol(),Period(),n);
   double avgRange=rangeSum/10.0, candleRange=h-l;
   int hour=TimeHour(iTime(Symbol(),Period(),sh));
   double oldLow=1.0e100,oldHigh=-1.0e100; int lowShift=sh+6,highShift=sh+6;
   for(int d=sh+2;d<=sh+6;d++) { if(iLow(Symbol(),Period(),d)<oldLow){oldLow=iLow(Symbol(),Period(),d);lowShift=d;} if(iHigh(Symbol(),Period(),d)>oldHigh){oldHigh=iHigh(Symbol(),Period(),d);highShift=d;} }
   double oldRsiLow=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,lowShift);
   double oldRsiHigh=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,highShift);
   int htfShift=iBarShift(Symbol(),PERIOD_H4,iTime(Symbol(),Period(),sh),false); if(htfShift<1) htfShift=1;
   double h4Fast=iMA(Symbol(),PERIOD_H4,20,0,MODE_EMA,PRICE_CLOSE,htfShift);
   double h4Slow=iMA(Symbol(),PERIOD_H4,50,0,MODE_EMA,PRICE_CLOSE,htfShift);
   double pv=0.0,vol=0.0; int vwN=MathMax(5,MathMin(InpVWAPLookback,100));
   for(int vw=sh;vw<sh+vwN && vw<Bars;vw++){double typ=(iHigh(Symbol(),Period(),vw)+iLow(Symbol(),Period(),vw)+iClose(Symbol(),Period(),vw))/3.0;double tv=(double)iVolume(Symbol(),Period(),vw);if(typ>0&&tv>0){pv+=typ*tv;vol+=tv;}}
   double vwap=(vol>0?pv/vol:0.0);
   double priorTop=-1.0e100,priorBottom=1.0e100; int rtN=MathMax(5,MathMin(InpRetestLookback,40));
   for(int rt=sh+2;rt<=sh+rtN+1;rt++){priorTop=MathMax(priorTop,iHigh(Symbol(),Period(),rt));priorBottom=MathMin(priorBottom,iLow(Symbol(),Period(),rt));}
   double tolerance=MathMax(0.0,InpRetestToleranceATR)*atr;
   double swingHigh=-1.0e100,swingLow=1.0e100; int fibN=MathMax(10,MathMin(InpFibLookback,100));
   for(int fb=sh+1;fb<=sh+fibN;fb++){swingHigh=MathMax(swingHigh,iHigh(Symbol(),Period(),fb));swingLow=MathMin(swingLow,iLow(Symbol(),Period(),fb));}
   double swingRange=swingHigh-swingLow;
   double upperNow=iBands(Symbol(),Period(),20,2.0,0,PRICE_CLOSE,MODE_UPPER,sh), lowerNow=iBands(Symbol(),Period(),20,2.0,0,PRICE_CLOSE,MODE_LOWER,sh);
   double upperPrev=iBands(Symbol(),Period(),20,2.0,0,PRICE_CLOSE,MODE_UPPER,sh+1), lowerPrev=iBands(Symbol(),Period(),20,2.0,0,PRICE_CLOSE,MODE_LOWER,sh+1);
   double widthAvg=0.0; int widthCount=0;
   for(int bw=sh+2;bw<sh+12 && bw<Bars;bw++){double bu=iBands(Symbol(),Period(),20,2.0,0,PRICE_CLOSE,MODE_UPPER,bw);double bl=iBands(Symbol(),Period(),20,2.0,0,PRICE_CLOSE,MODE_LOWER,bw);if(bu>bl&&bl>0){widthAvg+=(bu-bl);widthCount++;}}
   int lrN=MathMax(5,MathMin(InpRegressionLookback,50)); double sumX=0,sumY=0,sumXY=0,sumXX=0;
   for(int lr=0;lr<lrN;lr++){double x=(double)lr;double y=iClose(Symbol(),Period(),sh+lrN-1-lr);sumX+=x;sumY+=y;sumXY+=x*y;sumXX+=x*x;}
   double denom=lrN*sumXX-sumX*sumX; double slope=(denom!=0?(lrN*sumXY-sumX*sumY)/denom:0.0);
   if(model==MODEL_TREND)
   {
      AuditAdd(buy,"adxTrendMin",adx>=InpTrendADXMin); AuditAdd(buy,"closeAboveTrendEMA",c>et); AuditAdd(buy,"fastAboveSlowEMA",ef>es); AuditAdd(buy,"plusDIAboveMinusDI",pdi>mdi);
      AuditAdd(buy,"pullbackNearSlowEMA",MathAbs(c-es)<=0.25*atr); AuditAdd(buy,"pullbackDirection",c>et&&pdi>mdi);
      AuditAdd(sell,"adxTrendMin",adx>=InpTrendADXMin); AuditAdd(sell,"closeBelowTrendEMA",c<et); AuditAdd(sell,"fastBelowSlowEMA",ef<es); AuditAdd(sell,"minusDIAbovePlusDI",mdi>pdi);
      AuditAdd(sell,"pullbackNearSlowEMA",MathAbs(c-es)<=0.25*atr); AuditAdd(sell,"pullbackDirection",c<et&&mdi>pdi);
   }
   else if(model==MODEL_MOMENTUM)
   {
      AuditAdd(buy,"momentumATRThreshold",mom>=InpMomentumATRThreshold); AuditAdd(buy,"closeAboveSlowEMA",c>es); AuditAdd(buy,"continuationEnabled",InpMomentumTrendContinuation); AuditAdd(buy,"continuationADX",adx>=InpTrendADXMin); AuditAdd(buy,"continuationTrend",c>et&&ef>es&&c>es&&pdi>mdi); AuditAdd(buy,"continuationRSI",rsi<InpContinuationBuyRSIMax);
      AuditAdd(sell,"momentumATRThreshold",mom<=-InpMomentumATRThreshold); AuditAdd(sell,"closeBelowSlowEMA",c<es); AuditAdd(sell,"continuationEnabled",InpMomentumTrendContinuation); AuditAdd(sell,"continuationADX",adx>=InpTrendADXMin); AuditAdd(sell,"continuationTrend",c<et&&ef<es&&c<es&&mdi>pdi); AuditAdd(sell,"continuationRSI",rsi>InpContinuationSellRSIMin);
   }
   else if(model==MODEL_DONCHIAN){AuditAdd(buy,"closeAbovePriorHighPlusBuffer",c>priorHigh+buffer);AuditAdd(sell,"closeBelowPriorLowMinusBuffer",c<priorLow-buffer);}
   else if(model==MODEL_MEANREV){AuditAdd(buy,"ADXWeakTrend",adx<=InpMeanRevADXMax);AuditAdd(buy,"RSIAtBuyExtreme",rsi<=InpMeanRevRSIBuy);AuditAdd(sell,"ADXWeakTrend",adx<=InpMeanRevADXMax);AuditAdd(sell,"RSIAtSellExtreme",rsi>=InpMeanRevRSISell);}
   else if(model==MODEL_STRICT_RANGE){bool adxOK=adx<=InpStrictRangeADXMax,emaOK=MathAbs(ef-es)<=InpStrictRangeEMAGapATR*atr;AuditAdd(buy,"ADXRange",adxOK);AuditAdd(buy,"EMACompression",emaOK);AuditAdd(buy,"NearRangeLow",c<=rl+InpStrictRangeEdgeATR*atr);AuditAdd(buy,"RSIBuyGate",rsi<=InpStrictRangeBuyRSI);AuditAdd(sell,"ADXRange",adxOK);AuditAdd(sell,"EMACompression",emaOK);AuditAdd(sell,"NearRangeHigh",c>=rh-InpStrictRangeEdgeATR*atr);AuditAdd(sell,"RSISellGate",rsi>=InpStrictRangeSellRSI);}
   else if(model==MODEL_ATR_BREAKOUT){AuditAdd(buy,"rangeExpansion",avgRange>0&&candleRange>=1.35*avgRange);AuditAdd(buy,"rangeAtLeast0_8ATR",candleRange>=0.80*atr);AuditAdd(buy,"bullishCandle",c>o);AuditAdd(buy,"closeAbovePreviousClose",c>c2);AuditAdd(sell,"rangeExpansion",avgRange>0&&candleRange>=1.35*avgRange);AuditAdd(sell,"rangeAtLeast0_8ATR",candleRange>=0.80*atr);AuditAdd(sell,"bearishCandle",c<o);AuditAdd(sell,"closeBelowPreviousClose",c<c2);}
   else if(model==MODEL_SESSION_BIAS){AuditAdd(buy,"sessionHour7to19",hour>=7&&hour<20);AuditAdd(buy,"closeAboveTrendEMA",c>et);AuditAdd(buy,"fastAboveSlowEMA",ef>es);AuditAdd(buy,"closeAbovePreviousClose",c>c2);AuditAdd(sell,"sessionHour7to19",hour>=7&&hour<20);AuditAdd(sell,"closeBelowTrendEMA",c<et);AuditAdd(sell,"fastBelowSlowEMA",ef<es);AuditAdd(sell,"closeBelowPreviousClose",c<c2);}
   else if(model==MODEL_RSI_DIVERGENCE){AuditAdd(buy,"priceLowerLow",l<oldLow);AuditAdd(buy,"RSIHigherThanPriorLowBy3",rsi>oldRsiLow+3.0);AuditAdd(sell,"priceHigherHigh",h>oldHigh);AuditAdd(sell,"RSILowerThanPriorHighBy3",rsi<oldRsiHigh-3.0);}
   else if(model==MODEL_HTF_TREND){AuditAdd(buy,"H4FastAboveSlow",h4Fast>h4Slow);AuditAdd(buy,"closeAboveSlowEMA",c>es);AuditAdd(sell,"H4FastBelowSlow",h4Fast<h4Slow);AuditAdd(sell,"closeBelowSlowEMA",c<es);}
   else if(model==MODEL_VWAP_DEVIATION){AuditAdd(buy,"VWAPAvailable",vol>0);AuditAdd(buy,"belowVWAPDeviation",c<vwap-InpVWAPDeviationATR*atr);AuditAdd(buy,"RSIBelow45",rsi<45.0);AuditAdd(sell,"VWAPAvailable",vol>0);AuditAdd(sell,"aboveVWAPDeviation",c>vwap+InpVWAPDeviationATR*atr);AuditAdd(sell,"RSIAbove55",rsi>55.0);}
   else if(model==MODEL_BREAK_RETEST){AuditAdd(buy,"previousCloseBrokePriorTop",c2>priorTop);AuditAdd(buy,"lowRetestedTop",l<=priorTop+tolerance);AuditAdd(buy,"closeReclaimedTop",c>priorTop);AuditAdd(sell,"previousCloseBrokePriorBottom",c2<priorBottom);AuditAdd(sell,"highRetestedBottom",h>=priorBottom-tolerance);AuditAdd(sell,"closeLostBottom",c<priorBottom);}
   else if(model==MODEL_FIB_PULLBACK){double fromHigh=(swingRange>0?(swingHigh-c)/swingRange:-1),fromLow=(swingRange>0?(c-swingLow)/swingRange:-1);AuditAdd(buy,"swingRangeGreaterATR",swingRange>atr);AuditAdd(buy,"ADXTrendMin",adx>=InpTrendADXMin);AuditAdd(buy,"bullTrend",c>et&&ef>es);AuditAdd(buy,"retracement38to62",fromHigh>=0.382&&fromHigh<=0.618);AuditAdd(buy,"bullishCandle",c>o);AuditAdd(sell,"swingRangeGreaterATR",swingRange>atr);AuditAdd(sell,"ADXTrendMin",adx>=InpTrendADXMin);AuditAdd(sell,"bearTrend",c<et&&ef<es);AuditAdd(sell,"retracement38to62",fromLow>=0.382&&fromLow<=0.618);AuditAdd(sell,"bearishCandle",c<o);}
   else if(model==MODEL_VOL_SQUEEZE){double wn=upperNow-lowerNow,wp=upperPrev-lowerPrev;AuditAdd(buy,"bandWidthData",widthCount>0&&wp>0);AuditAdd(buy,"widthExpanding",wn>wp);AuditAdd(buy,"priorWidthCompressed",widthCount>0&&wp<(widthAvg/MathMax(1,widthCount))*InpSqueezeWidthFactor);AuditAdd(buy,"closeAboveUpperBand",c>upperNow);AuditAdd(buy,"bullishCandle",c>o);AuditAdd(sell,"bandWidthData",widthCount>0&&wp>0);AuditAdd(sell,"widthExpanding",wn>wp);AuditAdd(sell,"priorWidthCompressed",widthCount>0&&wp<(widthAvg/MathMax(1,widthCount))*InpSqueezeWidthFactor);AuditAdd(sell,"closeBelowLowerBand",c<lowerNow);AuditAdd(sell,"bearishCandle",c<o);}
   else if(model==MODEL_LINEAR_REGRESSION){AuditAdd(buy,"regressionSlopeATR",denom!=0&&slope/atr>=InpRegressionSlopeATR);AuditAdd(buy,"closeAboveSlowEMA",c>es);AuditAdd(sell,"regressionSlopeATR",denom!=0&&slope/atr<=-InpRegressionSlopeATR);AuditAdd(sell,"closeBelowSlowEMA",c<es);}
   else if(model==MODEL_MACD_CONFIRM)
   {
      double mm=iMACD(Symbol(),Period(),12,26,9,PRICE_CLOSE,MODE_MAIN,sh);
      double ms=iMACD(Symbol(),Period(),12,26,9,PRICE_CLOSE,MODE_SIGNAL,sh);
      double mmp=iMACD(Symbol(),Period(),12,26,9,PRICE_CLOSE,MODE_MAIN,sh+1);
      AuditAdd(buy,"MACDMainAboveSignal",mm>ms); AuditAdd(buy,"MACDRising",mm>mmp); AuditAdd(buy,"MACDNonNegative",mm>=0); AuditAdd(buy,"closeAboveSlowEMA",c>es);
      AuditAdd(sell,"MACDMainBelowSignal",mm<ms); AuditAdd(sell,"MACDFalling",mm<mmp); AuditAdd(sell,"MACDNonPositive",mm<=0); AuditAdd(sell,"closeBelowSlowEMA",c<es);
   }
   else if(model==MODEL_BOLLINGER_EXPANSION)
   {
      double widthNowLocal=upperNow-lowerNow, widthPrevLocal=upperPrev-lowerPrev;
      AuditAdd(buy,"bandsExpanding",widthNowLocal>widthPrevLocal); AuditAdd(buy,"closeAboveUpperBand",c>upperNow); AuditAdd(buy,"bullishCandle",c>o);
      AuditAdd(sell,"bandsExpanding",widthNowLocal>widthPrevLocal); AuditAdd(sell,"closeBelowLowerBand",c<lowerNow); AuditAdd(sell,"bearishCandle",c<o);
   }
   Print("MODEL TRIGGER AUDIT | model=",g_modelNames[model]," currentSignal=",(actualSignal>0?"BUY":(actualSignal<0?"SELL":"NONE")),
         " | BUY[",buy,"] SELL[",sell,"] | conditionPassesAreNotOrders=true diagnosticOnly=true gatesChanged=false");
}

void AuditCurrentSignalConditions()
{
   int sh=1;
   double c=iClose(Symbol(),Period(),sh), o=iOpen(Symbol(),Period(),sh);
   double h=iHigh(Symbol(),Period(),sh), l=iLow(Symbol(),Period(),sh);
   double cOld=iClose(Symbol(),Period(),sh+InpMomentumLookback);
   double atr=GetATR(sh);
   double ef=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh);
   double es=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh);
   double et=iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,sh);
   double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh);
   double pdi=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_PLUSDI,sh);
   double mdi=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MINUSDI,sh);
   double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,sh);
   if(c<=0 || cOld<=0 || atr<=0 || ef<=0 || es<=0 || et<=0) {
      Print("CURRENT SIGNAL CONDITION AUDIT | status=SKIPPED reason=INVALID_INDICATOR_DATA");
      return;
   }
   double mom=(c-cOld)/atr;
   double priorHigh=-1.0e100,priorLow=1.0e100;
   for(int k=sh+1;k<=sh+InpDonchianPeriod;k++) {
      priorHigh=MathMax(priorHigh,iHigh(Symbol(),Period(),k));
      priorLow=MathMin(priorLow,iLow(Symbol(),Period(),k));
   }
   double buffer=MathMax(0.0,InpBreakoutBufferATR)*atr;
   double rangeSum=0.0;
   for(int n=sh+1;n<=sh+10;n++) rangeSum+=iHigh(Symbol(),Period(),n)-iLow(Symbol(),Period(),n);
   double avgRange=rangeSum/10.0;
   double candleRange=h-l;
   bool trendBuy=(adx>=InpTrendADXMin && c>et && ef>es && pdi>mdi);
   bool trendSell=(adx>=InpTrendADXMin && c<et && ef<es && mdi>pdi);
   bool momBuy=((mom>=InpMomentumATRThreshold && c>es) ||
      (InpMomentumTrendContinuation && adx>=InpTrendADXMin && c>et && ef>es && c>es && pdi>mdi && rsi<InpContinuationBuyRSIMax));
   bool momSell=((mom<=-InpMomentumATRThreshold && c<es) ||
      (InpMomentumTrendContinuation && adx>=InpTrendADXMin && c<et && ef<es && c<es && mdi>pdi && rsi>InpContinuationSellRSIMin));
   bool donBuy=(c>priorHigh+buffer), donSell=(c<priorLow-buffer);
   bool meanBuy=(adx<=InpMeanRevADXMax && rsi<=InpMeanRevRSIBuy);
   bool meanSell=(adx<=InpMeanRevADXMax && rsi>=InpMeanRevRSISell);
   bool atrBuy=(avgRange>0 && candleRange>=1.35*avgRange && candleRange>=0.80*atr && c>o && c>iClose(Symbol(),Period(),sh+1));
   bool atrSell=(avgRange>0 && candleRange>=1.35*avgRange && candleRange>=0.80*atr && c<o && c<iClose(Symbol(),Period(),sh+1));
   int hour=TimeHour(iTime(Symbol(),Period(),sh));
   bool sessionBuy=(hour>=7 && hour<20 && c>et && ef>es && c>iClose(Symbol(),Period(),sh+1));
   bool sessionSell=(hour>=7 && hour<20 && c<et && ef<es && c<iClose(Symbol(),Period(),sh+1));
   Print("CURRENT SIGNAL CONDITION AUDIT | closedBar=",TimeToString(iTime(Symbol(),Period(),sh),TIME_DATE|TIME_MINUTES),
      " regime=",CurrentRegime(c,et,adx)," ADX=",DoubleToString(adx,2)," RSI=",DoubleToString(rsi,2),
      " momentumATR=",DoubleToString(mom,3)," requiredAbsMomentumATR=",DoubleToString(InpMomentumATRThreshold,2),
      " trendBuy/Sell=",(trendBuy?1:0),"/",(trendSell?1:0),
      " momentumBuy/Sell=",(momBuy?1:0),"/",(momSell?1:0),
      " donchianBuy/Sell=",(donBuy?1:0),"/",(donSell?1:0),
      " meanRevBuy/Sell=",(meanBuy?1:0),"/",(meanSell?1:0),
      " atrExpansionRatio=",DoubleToString(avgRange>0?candleRange/avgRange:0.0,3),
      " atrBreakoutBuy/Sell=",(atrBuy?1:0),"/",(atrSell?1:0),
      " sessionBuy/Sell=",(sessionBuy?1:0),"/",(sessionSell?1:0),
      " | diagnosticOnly=true gatesChanged=false");
}

void PrintEvidence(string modelName,string direction,DirectionEvidence &e,int signal)
{
   Print("MODEL EVIDENCE | model=",modelName," direction=",direction,
         " signal=",signal," samples=",e.samples," winRate=",DoubleToString(e.winRate,3),
         " avgR=",DoubleToString(e.avgR,3)," result=",(EvidencePass(e)?"PASS":"REJECT"),
         " reason=",EvidenceRejectReason(e));
}

// Reliability-shrunk historical expectancy in R.
// A high average from a tiny sample is discounted; this ranks eligible models,
// it does not override any evidence, account, spread, stop-loss or capital gate.
double StrategySelectionScore(DirectionEvidence &e)
{
   if(e.samples<=0) return -1.0e100;
   double reliability=(double)e.samples/((double)e.samples+12.0);
   return e.avgR*reliability;
}

// Experimental regime context: compare the current closed-bar regime with
// the recent regime. It adjusts ranking only; it never overrides evidence gates.
double RegimeAwareScore(int model,double baseScore,int direction,double closePrice,double emaTrend,double adx)
{
   if(!InpUseRegimeAwareSelection) return baseScore;
   string regime=CurrentRegime(closePrice,emaTrend,adx);
   bool trendModel=(model==MODEL_TREND || model==MODEL_MOMENTUM || model==MODEL_DONCHIAN ||
                    model==MODEL_ATR_BREAKOUT || model==MODEL_HTF_TREND || model==MODEL_BREAK_RETEST ||
                    model==MODEL_FIB_PULLBACK || model==MODEL_VOL_SQUEEZE || model==MODEL_LINEAR_REGRESSION ||
                    model==MODEL_MACD_CONFIRM || model==MODEL_BOLLINGER_EXPANSION);
   bool rangeModel=(model==MODEL_MEANREV || model==MODEL_STRICT_RANGE || model==MODEL_VWAP_DEVIATION ||
                    model==MODEL_RSI_DIVERGENCE);
   double factor=1.0;
   if(StringFind(regime,"RANGE")>=0)
   {
      if(trendModel) factor=0.85;
      if(rangeModel) factor=1.10;
   }
   else if(StringFind(regime,"TREND")>=0)
   {
      if(trendModel) factor=1.10;
      if(rangeModel) factor=0.85;
   }
   // Markov-inspired persistence context: use recent direction continuity as a
   // small confidence modifier, not as an independent trade signal.
   if(InpUseMarkovRegimeContext && direction!=0)
   {
      int same=0,opposite=0;
      int n=MathMin(12,Bars-2);
      for(int k=2;k<n+2;k++)
      {
         double c=iClose(Symbol(),Period(),k);
         double e=iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,k);
         double ax=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,k);
         if(c<=0 || e<=0) continue;
         int historicalDirection=(ax>=InpTrendADXMin?(c>e?1:(c<e?-1:0)):0);
         if(historicalDirection==direction) same++;
         else if(historicalDirection==-direction) opposite++;
      }
      if(same+opposite>=4)
      {
         double persistence=(double)same/(double)(same+opposite);
         factor*=0.90+0.20*persistence; // bounded 0.90..1.10
      }
   }
   return baseScore*factor;
}

void EvaluateEngine()
{
   // Capture the active chart bar locally; ProcessEngine owns the caller-scope barTime.
   datetime barTime=iTime(Symbol(),Period(),0);
   if(barTime<=0)
   {
      Print("DECISION NOT EXECUTED | reason=CURRENT_BAR_TIME_UNAVAILABLE | action=NO_ORDER");
      return;
   }
   g_currentProvisionalEntry=false;
   int trend=0,momentum=0,donchian=0,meanrev=0,strictRange=0;
   int atrBreakout=0,sessionBias=0,rsiDivergence=0,htfTrend=0;
   int vwapDeviation=0,breakRetest=0,fibPullback=0,volSqueeze=0,linearRegression=0,macdConfirm=0,bollingerExpansion=0;
   if(!GetModelSignals(1,trend,momentum,donchian,meanrev,strictRange,atrBreakout,sessionBias,rsiDivergence,htfTrend,
                       vwapDeviation,breakRetest,fibPullback,volSqueeze,linearRegression,macdConfirm,bollingerExpansion))
   {
      Print("PROCESS DATA_GATE | rejected=true | reason=insufficient history or invalid indicator data | Bars=",Bars,
            " requiredAtLeast=",(InpTrendEMA+InpDonchianPeriod+InpForwardHorizonBars+20),
            " | action=NO_ORDER; wait for more valid bars/quotes.");
      return;
   }

   AuditModelSignalFrequency();
   AuditRangeSignalConditions();
   AuditCurrentSignalConditions(); // v1.44: explain current-bar trigger misses without changing trade logic.
   double close1=iClose(Symbol(),Period(),1);
   double emaFast1=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double emaSlow1=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double emaTrend1=iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double rsi1=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,1);
   double adx1=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
   double plusDI1=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_PLUSDI,1);
   double minusDI1=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MINUSDI,1);
   double atr1=GetATR(1);
   if(InpPrintDiagnostics)
      Print("BITEY DIAGNOSTIC | close=",DoubleToString(close1,Digits),
            " EMAfast=",DoubleToString(emaFast1,Digits)," EMAslow=",DoubleToString(emaSlow1,Digits),
            " EMAtrend=",DoubleToString(emaTrend1,Digits)," RSI=",DoubleToString(rsi1,2),
            " ADX=",DoubleToString(adx1,2)," +DI=",DoubleToString(plusDI1,2),
            " -DI=",DoubleToString(minusDI1,2)," ATR=",DoubleToString(atr1,Digits),
            " signals T=",trend," M=",momentum," D=",donchian," R=",meanrev," SR=",strictRange,
            " spreadPts=",(int)MarketInfo(Symbol(),MODE_SPREAD));

   // Refresh campaign/governor state before applying evidence thresholds.
   UpdateRiskGovernor();
   DirectionEvidence buy[MODEL_COUNT],sell[MODEL_COUNT];
   int signals[MODEL_COUNT];
   string bestBuyCandidate="NONE",bestSellCandidate="NONE";
   double bestBuyScore=-1.0e100,bestSellScore=-1.0e100;
   bool bestBuyProvisional=false,bestSellProvisional=false;
   for(int initIndex=0;initIndex<MODEL_COUNT;initIndex++)
   {
      signals[initIndex]=0;
      ResetEvidence(buy[initIndex]);
      ResetEvidence(sell[initIndex]);
   }
   signals[0]=trend; signals[1]=momentum; signals[2]=donchian; signals[3]=meanrev; signals[4]=strictRange;
   signals[5]=atrBreakout; signals[6]=sessionBias; signals[7]=rsiDivergence; signals[8]=htfTrend;
   signals[9]=vwapDeviation; signals[10]=breakRetest; signals[11]=fibPullback;
   signals[12]=volSqueeze; signals[13]=linearRegression; signals[14]=macdConfirm; signals[15]=bollingerExpansion;

   // v1.46: audit each model's actual BUY and SELL subconditions on the same completed bar.
   for(int auditModel=0;auditModel<MODEL_COUNT;auditModel++)
      AuditDetailedModelConditions(auditModel,1,signals[auditModel]);

   int buyVotes=0,sellVotes=0;
   double buyStrength=0.0,sellStrength=0.0; // Aggregated historical edge of currently signalled, evidence-qualified models.
   int rawBuySignals=0,rawSellSignals=0;
   int rejectedBuySignals=0,rejectedSellSignals=0;
   // Build telemetry JSON while each evidence record is freshly computed.
   // Avoid a later dynamic-index read of the structure arrays, which triggers
   // conservative "possible use of uninitialized variable" warnings in MQL4.
   string modelsJson="[";
   for(int m=0;m<MODEL_COUNT;m++)
   {
      BuildEvidence(m,1,buy[m]);
      BuildEvidence(m,-1,sell[m]);
      bool thisBuyPass=EvidencePass(buy[m]);
      bool thisSellPass=EvidencePass(sell[m]);
      double thisBuyAvgR=buy[m].avgR;
      double thisSellAvgR=sell[m].avgR;
      if(signals[m]>0)
      {
         rawBuySignals++;
         if(thisBuyPass)
         {
            buyVotes++;
            // Use reliability-adjusted expected R, not raw average R or vote count alone.
            double candidateBuyScore=RegimeAwareScore(m,StrategySelectionScore(buy[m]),1,close1,emaTrend1,adx1);
            buyStrength += MathMax(0.0,candidateBuyScore) * (0.5 + buy[m].winRate);
            if(candidateBuyScore>bestBuyScore)
            {
               bestBuyScore=candidateBuyScore;
               bestBuyCandidate=g_modelNames[m];
               bestBuyProvisional=IsProvisionalEvidence(buy[m]);
            }
         }
         else rejectedBuySignals++;
      }
      if(signals[m]<0)
      {
         rawSellSignals++;
         if(thisSellPass)
         {
            sellVotes++;
            double candidateSellScore=RegimeAwareScore(m,StrategySelectionScore(sell[m]),-1,close1,emaTrend1,adx1);
            sellStrength += MathMax(0.0,candidateSellScore) * (0.5 + sell[m].winRate);
            if(candidateSellScore>bestSellScore)
            {
               bestSellScore=candidateSellScore;
               bestSellCandidate=g_modelNames[m];
               bestSellProvisional=IsProvisionalEvidence(sell[m]);
            }
         }
         else rejectedSellSignals++;
      }
      if(InpPrintDiagnostics)
      {
         PrintEvidence(g_modelNames[m],"BUY",buy[m],(signals[m]>0?1:0));
         PrintEvidence(g_modelNames[m],"SELL",sell[m],(signals[m]<0?-1:0));
      }
      WriteEvidenceRow(g_modelNames[m],"BUY",buy[m],(signals[m]>0?1:0),EvidenceRejectReason(buy[m]));
      WriteEvidenceRow(g_modelNames[m],"SELL",sell[m],(signals[m]<0?-1:0),EvidenceRejectReason(sell[m]));

      // v1.22 decision audit (preserved from v1.19): explicitly show whether the model is silent,
      // has a live directional signal, and which evidence rule blocks each side.
      // This is diagnostic only; it does not change signal or risk thresholds.
      string currentSignal="NONE";
      if(signals[m]>0) currentSignal="BUY";
      else if(signals[m]<0) currentSignal="SELL";
      Print("MODEL DECISION AUDIT | model=",g_modelNames[m],
            " currentSignal=",currentSignal,
            " | BUY evidence=", (thisBuyPass?"PASS":"REJECT"),
            " n=",buy[m].samples," winRate=",DoubleToString(buy[m].winRate,3),
            " avgR=",DoubleToString(buy[m].avgR,3),
            " reason=",EvidenceRejectReason(buy[m]),
            " | SELL evidence=", (thisSellPass?"PASS":"REJECT"),
            " n=",sell[m].samples," winRate=",DoubleToString(sell[m].winRate,3),
            " avgR=",DoubleToString(sell[m].avgR,3),
            " reason=",EvidenceRejectReason(sell[m]),
            " | interpretation=", (signals[m]==0?"NO_CURRENT_SIGNAL_CHECK_TRIGGER_CONDITIONS":
                                  (signals[m]>0?(thisBuyPass?"BUY_SIGNAL_EVIDENCE_OK":"BUY_SIGNAL_BLOCKED_BY_EVIDENCE"):
                                                 (thisSellPass?"SELL_SIGNAL_EVIDENCE_OK":"SELL_SIGNAL_BLOCKED_BY_EVIDENCE"))));

      if(m>0) modelsJson+=",";
      modelsJson+="{\"name\":\""+g_modelNames[m]+"\",\"signal\":"+IntegerToString(signals[m])+",";
      modelsJson+="\"buy\":"+EvidenceToJson(buy[m])+",";
      modelsJson+="\"sell\":"+EvidenceToJson(sell[m])+"}";
   }
   modelsJson+="]";

   int requiredVotes=RequiredModelVotes();
   if(rawBuySignals==0 && rawSellSignals==0)
   {
      string regimeNow=CurrentRegime(close1,emaTrend1,adx1);
      double momentumOldClose=iClose(Symbol(),Period(),1+InpMomentumLookback);
      double momentumNow=(momentumOldClose>0.0 && atr1>0.0 ? (close1-momentumOldClose)/atr1 : 0.0);
      Print("NO RAW DIRECTIONAL SIGNAL | symbol=",Symbol()," timeframe=",Period(),
            " | closedBar=",TimeToString(iTime(Symbol(),Period(),1),TIME_DATE|TIME_MINUTES),
            " | regime=",regimeNow," ADX=",DoubleToString(adx1,2)," requiredTrendADX=",DoubleToString(InpTrendADXMin,2),
            " momentumATR=",DoubleToString(momentumNow,3)," threshold=",DoubleToString(InpMomentumATRThreshold,3),
            " | close=",DoubleToString(close1,Digits)," EMAfast=",DoubleToString(emaFast1,Digits),
            " EMAslow=",DoubleToString(emaSlow1,Digits)," EMAtrend=",DoubleToString(emaTrend1,Digits),
            " RSI=",DoubleToString(rsi1,2)," +DI=",DoubleToString(plusDI1,2)," -DI=",DoubleToString(minusDI1,2),
            " | modelsChecked=",MODEL_COUNT," rawBUY=0 rawSELL=0 evidenceRejectedBUY=0 evidenceRejectedSELL=0",
            " | action=WAIT_NO_ORDER; inspect MODEL TRIGGER AUDIT lines for exact failed subconditions; evidence/risk gates unchanged.");
   }
   int decision=0;
   string decisionText="WAIT: no raw directional signal";
   string conflictResolution="NONE";
   if(buyVotes>=requiredVotes && sellVotes==0) { decision=1; decisionText="BUY candidate; evidence passed"; }
   else if(sellVotes>=requiredVotes && buyVotes==0) { decision=-1; decisionText="SELL candidate; evidence passed"; }
   else if(buyVotes>0 && sellVotes>0)
   {
      // Conflict rule: when both sides have qualified votes, permit the clearly
      // superior side to win with at least one qualified current signal. Requiring
      // the full multi-vote threshold on the winning side as well would make a
      // genuine 1-vs-1 conflict impossible to resolve even with a decisive edge.
      // The evidence checks for every counted vote remain unchanged; near-ties WAIT.
      double scoreHigh=MathMax(bestBuyScore,bestSellScore);
      double scoreLow=MathMin(bestBuyScore,bestSellScore);
      double requiredEdge=MathMax(0.02,MathAbs(scoreHigh)*0.15);
      bool scoreClearlyWins=(scoreHigh>0.0 && (scoreHigh-scoreLow)>=requiredEdge);
      if(scoreClearlyWins && bestBuyScore>bestSellScore && buyVotes>0)
      {
         decision=1; conflictResolution="BUY_BEST_EXPECTED_EDGE";
         decisionText="BUY selected by highest reliability-adjusted expected R model: "+bestBuyCandidate;
      }
      else if(scoreClearlyWins && bestSellScore>bestBuyScore && sellVotes>0)
      {
         decision=-1; conflictResolution="SELL_BEST_EXPECTED_EDGE";
         decisionText="SELL selected by highest reliability-adjusted expected R model: "+bestSellCandidate;
      }
      else
      {
         decisionText="WAIT: best-model edge is too close or winning side lacks required qualified votes";
      }
      Print("CONFLICT RESOLUTION | BUY votes=",buyVotes," bestModel=",bestBuyCandidate,
            " bestExpectedRScore=",DoubleToString(bestBuyScore,4)," aggregateScore=",DoubleToString(buyStrength,4),
            " | SELL votes=",sellVotes," bestModel=",bestSellCandidate,
            " bestExpectedRScore=",DoubleToString(bestSellScore,4)," aggregateScore=",DoubleToString(sellStrength,4),
            " | requiredVotes=",requiredVotes," | minEdge=",DoubleToString(requiredEdge,4),
            " | method=",conflictResolution," | decision=",(decision>0?"BUY":(decision<0?"SELL":"WAIT")),
            " | rule=highest reliability-adjusted model expectancy; >=15% or 0.02R margin; winning side needs >=1 qualified current vote; non-conflict needs configured vote threshold; all evidence and trade-risk gates retained");
   }
   else if(rawBuySignals+rawSellSignals>0 && buyVotes+sellVotes==0)
      decisionText="WAIT: directional signal rejected by historical evidence";
   else if(buyVotes>0 && buyVotes<requiredVotes) decisionText="WAIT: BUY evidence passed but vote threshold not met";
   else if(sellVotes>0 && sellVotes<requiredVotes) decisionText="WAIT: SELL evidence passed but vote threshold not met";

   Print("PROCESS BAR EVALUATED | closedBarTime=",TimeToString(iTime(Symbol(),Period(),1),TIME_DATE|TIME_MINUTES),
         " | historyBars=",Bars," | ATR=",DoubleToString(atr1,Digits)," | regime=",CurrentRegime(close1,emaTrend1,adx1),
         " | evaluating 16 chart-local models with closed-bar data; the cross-asset ranking separately uses 16 model-family proxies; momentumThresholdATR=",DoubleToString(InpMomentumATRThreshold,2),
         " trendContinuation=",(InpMomentumTrendContinuation?"true":"false"),
         " donchianBufferATR=",DoubleToString(InpBreakoutBufferATR,2),".");
   Print("BITEY SBT v1.77.0 MULTI-ASSET | governor=",GovernorStateName(g_governorState)," campaignNetUSD=",DoubleToString(g_campaignNetUSD,2)," requiredVotes=",requiredVotes," | ",Symbol()," TF=",Period()," BUY votes=",buyVotes," SELL votes=",sellVotes,
         " | TREND=",trend," MOMENTUM=",momentum," DONCHIAN=",donchian," MEANREV=",meanrev,
         " STRICT_RANGE=",strictRange," ATR_BREAKOUT=",atrBreakout," SESSION_BIAS=",sessionBias,
         " RSI_DIVERGENCE=",rsiDivergence," HTF_TREND=",htfTrend,
         " | rawSignals BUY/SELL=",rawBuySignals,"/",rawSellSignals,
         " evidenceRejected BUY/SELL=",rejectedBuySignals,"/",rejectedSellSignals,
         " | DECISION=",decisionText);

   string bestStrategy="NONE";
   double bestScore=0.0; // Always initialized for telemetry, including WAIT and one-shot paths.
   if(decision>0)
   {
      bestStrategy=bestBuyCandidate;
      bestScore=bestBuyScore;
      g_currentProvisionalEntry=bestBuyProvisional;
   }
   else if(decision<0)
   {
      bestStrategy=bestSellCandidate;
      bestScore=bestSellScore;
      g_currentProvisionalEntry=bestSellProvisional;
   }
   Print("BEST MODEL SELECTION | decision=",(decision>0?"BUY":(decision<0?"SELL":"WAIT")),
         " | selectedModel=",bestStrategy," | selectedExpectedRScore=",DoubleToString(bestScore,4),
         " | BUY best=",bestBuyCandidate," score=",(bestBuyScore < -1.0e90 ? "N/A" : DoubleToString(bestBuyScore,4)),
         " | SELL best=",bestSellCandidate," score=",(bestSellScore < -1.0e90 ? "N/A" : DoubleToString(bestSellScore,4)),
         " | scoreFormula=reliability_shrunk_avgR_then_regime_and_optional_markov_adjustment; score is historical estimate, not a profit guarantee");
   if(g_currentProvisionalEntry)
      Print("EVIDENCE TIER | status=PROVISIONAL_STRONG_EDGE | strategy=",bestStrategy,
            " | entry risk capped at 50% of normal risk | this is exploratory evidence, not proof of edge.");

   string gateReason="";
   if(InpOneShotTestMode)
   {
      // Account classification is factual telemetry only. The one-shot test can run on demo or real accounts.
      // Never falsify IsDemo(); actual terminal/account/symbol permissions and all risk gates remain mandatory.
      Print("ONE-SHOT ACCOUNT CLASSIFICATION | terminalIsDemo=",(IsDemo()?"true":"false"),
            " | server=",AccountServer()," | classification=informational_only",
            " | WARNING=one-shot test may place a REAL order; broker permissions and risk gates still apply.");
      string testKey=OneShotTestKey();
      if(GlobalVariableCheck(testKey))
      {
         Print("TEST MODE COMPLETE | one-shot attempt already recorded for this account/magic/symbol; no further orders will be sent while test mode remains enabled. key=",testKey);
         SendSbtSnapshot(0,"ONE_SHOT_TEST_ALREADY_ATTEMPTED",buyVotes,sellVotes,trend,momentum,donchian,meanrev,strictRange,
                         modelsJson,"ONE_SHOT_TEST",0.0,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                         false,"ONE_SHOT_ALREADY_USED","ONE_SHOT_TEST_ALREADY_ATTEMPTED");
         return;
      }
      decision=(InpTestOrderDirection==TEST_ORDER_BUY?1:-1);
      decisionText=(decision>0?"ONE-SHOT TEST BUY: signal/evidence selection bypassed":"ONE-SHOT TEST SELL: signal/evidence selection bypassed");
      bestStrategy="ONE_SHOT_TEST";
      g_currentProvisionalEntry=false;
      Print("TEST ORDER ARMED | direction=",(decision>0?"BUY":"SELL"),
            " | signal/evidence selection bypassed for one test only; all TradeGate, lot/risk, spread, daily-loss, position-count, broker permission and SL/TP checks remain active.");
   }
   if(decision==0)
   {
      if(rawBuySignals+rawSellSignals==0) gateReason="NO_RAW_DIRECTIONAL_SIGNAL";
      else if(buyVotes+sellVotes==0) gateReason="SIGNAL_REJECTED_BY_HISTORICAL_EVIDENCE";
      else gateReason="QUALIFIED_VOTES_BELOW_REQUIRED_THRESHOLD_OR_CONFLICT";
      string nextAction="WAIT_FOR_NEXT_CLOSED_BAR_AND_RECHECK";
      if(rawBuySignals+rawSellSignals==0)
         nextAction="CHECK_MODEL_SIGNAL_FREQUENCY_AND_RANGE_CONDITION_AUDIT; DO_NOT_LOWER_EVIDENCE_GATES";
      else if(buyVotes+sellVotes==0)
         nextAction="READ_MODEL_DECISION_AUDIT_FOR_EACH_SIGNAL_REJECTION; GATHER_FORWARD_EVIDENCE; DO_NOT_FORCE_ENTRY";
      else if(buyVotes>0 && sellVotes>0)
         nextAction="WAIT_FOR_DIRECTIONAL_CONSENSUS; DO_NOT_TRADE_CONFLICT";
      else
         nextAction="WAIT_FOR_REQUIRED_QUALIFIED_VOTES; KEEP_REQUIRED_VOTES_AND_RISK_GATES";
      Print("NO ENTRY | reason=",gateReason," | rawSignals BUY/SELL=",rawBuySignals,"/",rawSellSignals,
            " evidenceRejected BUY/SELL=",rejectedBuySignals,"/",rejectedSellSignals," | signals T/M/D/R/SR=",
            trend,"/",momentum,"/",donchian,"/",meanrev,"/",strictRange,
            " | qualifiedVotes BUY/SELL=",buyVotes,"/",sellVotes," requiredVotes=",requiredVotes,
            " | evidenceRules minSamples=",InpMinEvidenceSamples," minWinRate=",DoubleToString(InpMinEvidenceWinRate,3),
            " minAvgR_gt=",DoubleToString(InpMinEvidenceAvgR,3)," governor=",GovernorStateName(g_governorState),
            " | explanation=",decisionText," | nextAction=",nextAction,
            " | action=no order; preserve evidence and risk gates.");
      SendSbtSnapshot(decision,decisionText,buyVotes,sellVotes,trend,momentum,donchian,meanrev,strictRange,
                      modelsJson,bestStrategy,bestScore,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                      false,gateReason,gateReason);
      return;
   }
   // Permit up to EffectiveMaxOpenTrades() concurrent positions, including same-direction entries on this symbol.
   // Never stack into an opposite-direction incumbent; a single opposing position may use guarded replacement.
   int sameSymbolOpenNow=CountOpenTradesForSymbol();
   bool anySameDirection=false;
   bool anyOppositeDirection=false;
   int currentTicket=-1;
   int currentDirection=0;
   for(int p=OrdersTotal()-1;p>=0;p--)
   {
      if(!OrderSelect(p,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      int posDirection=(OrderType()==OP_BUY?1:-1);
      if(posDirection==decision) anySameDirection=true; else anyOppositeDirection=true;
      if(currentTicket<0) { currentTicket=OrderTicket(); currentDirection=posDirection; }
   }

   bool replacedPosition=false;
   if(sameSymbolOpenNow==1 && anyOppositeDirection)
   {
      double incumbentDirectionScore=(decision>0?bestSellScore:bestBuyScore);
      replacedPosition=false; // SL/TP-only policy: never close/reopen an incumbent position.
      if(replacedPosition)
         Print("POSITION REPLACEMENT FLOW | old position closed; new order will be attempted only after all standard gates are rechecked.");
   }
   else if(sameSymbolOpenNow>0 && anyOppositeDirection)
   {
      string mixedResult="MIXED_OR_MULTIPLE_INCUMBENTS_NO_AUTOMATIC_REPLACEMENT";
      Print("POSITION DECISION | action=KEEP_CURRENT | reason=OPPOSITE_SIGNAL_WITH_MULTIPLE_OR_MIXED_POSITIONS",
            " | openOnSymbol=",sameSymbolOpenNow," candidateDirection=",(decision>0?"BUY":"SELL"),
            " | no hedge/stack/replacement; existing positions remain under SL/TP supervision.");
      SendSbtSnapshot(decision,decisionText,buyVotes,sellVotes,trend,momentum,donchian,meanrev,strictRange,
                      modelsJson,bestStrategy,bestScore,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                      false,mixedResult,mixedResult+": manual/model review required before reversing multiple positions");
      return;
   }

   if(!replacedPosition && sameSymbolOpenNow>0 && !anyOppositeDirection)
   {
      // Strict portfolio invariant: one live position per canonical asset, even when
      // the new signal points in the same direction. No averaging-in or same-side stacking.
      Print("POSITION DEDUPLICATION | action=NO_ENTRY | reason=ONE_POSITION_PER_CANONICAL_ASSET",
            " | existingPositionsOnAsset=",sameSymbolOpenNow,
            " canonicalAsset=",CanonicalAssetKey(Symbol()),
            " candidate=",(decision>0?"BUY":"SELL")," strategy=",bestStrategy,
            " | incumbent remains open; adaptive SL/TP supervision continues; no additional order sent.");
      SendSbtSnapshot(decision,decisionText,buyVotes,sellVotes,trend,momentum,donchian,meanrev,strictRange,
                      modelsJson,bestStrategy,bestScore,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                      false,"ONE_POSITION_PER_CANONICAL_ASSET","incumbent retained; same-direction stacking disabled");
      return;
   }
   else if(!replacedPosition && sameSymbolOpenNow>0 && anyOppositeDirection)
   {
      string oppositeResult=(InpPositionReplacementAuditOnly ? "AUDIT_ONLY_OPPOSITE_CANDIDATE_NOT_EXECUTED" : "OPPOSITE_CANDIDATE_REJECTED_OR_CLOSE_NOT_COMPLETED");
      Print("OPPOSITE CANDIDATE AUDIT | status=NOT_EXECUTED | action=KEEP_CURRENT",
            " | ticket=",currentTicket," existingDirection=",(currentDirection>0?"BUY":"SELL"),
            " candidateDirection=",(decision>0?"BUY":"SELL")," strategy=",bestStrategy,
            " | reason=",oppositeResult,
            " | existing position remains open; no opposite-direction order sent.");
      SendSbtSnapshot(decision,decisionText,buyVotes,sellVotes,trend,momentum,donchian,meanrev,strictRange,
                      modelsJson,bestStrategy,bestScore,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                      false,oppositeResult,oppositeResult+": existing position retained; no opposite order sent");
      return;
   }
   if(!replacedPosition && CountOpenTradesForSymbol()==0 && g_lastEntryAttemptBarTime==barTime)
   {
      string priorResult=g_lastEntryAttemptResult;
      if(priorResult=="NO_PREVIOUS_ATTEMPT" || priorResult=="")
         priorResult="PREVIOUS_SESSION_STATUS:"+EntryAttemptStatusName(g_lastEntryAttemptStatus);
      Print("ENTRY DEDUPLICATION | action=NO_ENTRY | previousAttemptBar=",TimeToString(g_lastEntryAttemptBarTime,TIME_DATE|TIME_MINUTES),
            " previousAttemptResult=",priorResult,
            " persistedStatus=",EntryAttemptStatusName(g_lastEntryAttemptStatus),
            " retryPolicy=WAIT_NEXT_NEW_BAR_AND_FULL_REVALIDATION retryAllowed=false",
            " | reason=one attempt already occurred on this bar; no same-bar resend; risk/evidence/position gates unchanged.");
      return;
   }
   if(!replacedPosition && CountOpenTradesForSymbol()==0 && g_lastEntryAttemptBarTime>0 && g_lastEntryAttemptBarTime!=barTime)
   {
      Print("ENTRY RETRY POLICY | previousAttemptBar=",TimeToString(g_lastEntryAttemptBarTime,TIME_DATE|TIME_MINUTES),
            " previousAttemptResult=",g_lastEntryAttemptResult,
            " persistedStatus=",EntryAttemptStatusName(g_lastEntryAttemptStatus),
            " currentBar=",TimeToString(barTime,TIME_DATE|TIME_MINUTES),
            " retryAllowed=true scope=NEW_BAR_REEVALUATION_ONLY",
            " | all signal, quote, spread, lot, SL/TP, daily-loss, position, portfolio-risk and broker gates must pass again; no blind resend.");
   }
   if(!TradeGate(gateReason))
   {
      Print("DECISION NOT EXECUTED | candidate=",(decision>0?"BUY":"SELL")," | strategy=",bestStrategy,
            " | reason=",gateReason," | signal qualified but pre-trade risk/permission gate rejected it.");
      SendSbtSnapshot(decision,decisionText,buyVotes,sellVotes,trend,momentum,donchian,meanrev,strictRange,
                      modelsJson,bestStrategy,bestScore,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                      false,gateReason,"VALID_SIGNAL_BLOCKED_BY_RISK_GATE: "+gateReason);
      return;
   }
   g_currentBestStrategy=bestStrategy;
   g_currentExpectedR=bestScore;
   g_currentStateId=BuildStateId(close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1);
   g_currentRiskBudgetUSD=EffectiveRiskBudgetUSD();
   if(InpOneShotTestMode)
   {
      // Persist before OrderSend so a broker rejection cannot cause repeated test orders.
      GlobalVariableSet(OneShotTestKey(),(double)TimeCurrent());
      GlobalVariablesFlush();
      Print("TEST ORDER ATTEMPT | one-shot marker persisted before OrderSend; no automatic retry will occur.");
   }
   // Persist the attempt marker BEFORE OrderSend. A restart/reconnect must not cause a same-bar resend.
   g_lastEntryAttemptBarTime=barTime;
   g_lastEntryAttemptStatus=1;
   g_lastEntryAttemptResult="ATTEMPT_IN_PROGRESS";
   GlobalVariableSet(EntryAttemptBarKey(),(double)barTime);
   GlobalVariableSet(EntryAttemptStatusKey(),1.0);
   GlobalVariablesFlush();
   Print("ENTRY ATTEMPT START | bar=",TimeToString(barTime,TIME_DATE|TIME_MINUTES),
         " direction=",(decision>0?"BUY":"SELL"),
         " | retryPolicy=no same-bar retry; next-bar reevaluation only after full risk revalidation.");
   // Evidence is attached to the execution attempt, not inferred later from a broker open message.
   RefreshRates();
   Print("TRADE EVIDENCE PACKET | schema=1 phase=PRE_ORDER source=CHART_LOCAL",
         " eaVersion=1.770 symbol=",Symbol()," canonicalAsset=",CanonicalAssetKey(Symbol()),
         " timeframe=",Period()," closedBarTime=",TimeToString(iTime(Symbol(),Period(),1),TIME_DATE|TIME_SECONDS),
         " decision=",(decision>0?"BUY":"SELL")," selectedModel=",bestStrategy,
         " expectedRScore=",DoubleToString(bestScore,6),
         " qualifiedVotesBuy=",buyVotes," qualifiedVotesSell=",sellVotes,
         " requiredVotes=",RequiredModelVotes(),
         " modelEvidenceJSON=",modelsJson,
         " bid=",DoubleToString(Bid,Digits)," ask=",DoubleToString(Ask,Digits),
         " spreadPoints=",DoubleToString(MarketInfo(Symbol(),MODE_SPREAD),1),
         " quoteTime=",TimeToString((datetime)MarketInfo(Symbol(),MODE_TIME),TIME_DATE|TIME_SECONDS),
         " quoteAgeSeconds=",(int)(TimeCurrent()-(datetime)MarketInfo(Symbol(),MODE_TIME)),
         " atr=",DoubleToString(atr1,Digits+2)," regime=",CurrentRegime(close1,emaTrend1,adx1),
         " capitalUSD=",DoubleToString(EffectiveOperatingCapitalUSD(),2),
         " riskBudgetUSD=",DoubleToString(EffectiveRiskBudgetUSD(),4),
         " openPositionsBefore=",CountOpenTrades(),
         " openRiskBeforeUSD=",DoubleToString(PortfolioOpenRiskUSD(),4),
         " portfolioRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),4),
         " dailyNetUSD=",DoubleToString(TodayNetProfit(),4),
         " dailyLossLimitUSD=",DoubleToString(EffectiveDailyLossLimitUSD(),2),
         " brokerMinLot=",DoubleToString(MarketInfo(Symbol(),MODE_MINLOT),4),
         " lotStep=",DoubleToString(MarketInfo(Symbol(),MODE_LOTSTEP),4),
         " tickValue=",DoubleToString(MarketInfo(Symbol(),MODE_TICKVALUE),8),
         " tickSize=",DoubleToString(TickSizePriceForSymbol(Symbol()),10),
         " evidenceScope=PER_MODEL_DIRECTIONAL_IN_SAMPLE; holdoutEvidenceMustBeReadFrom_CROSS_ASSET_EVIDENCE_AUDIT");
   bool orderOpened=SendOrder(decision);
   g_lastEntryAttemptStatus=(orderOpened?2:3);
   g_lastEntryAttemptResult=g_lastExecutionResult;
   GlobalVariableSet(EntryAttemptStatusKey(),(double)g_lastEntryAttemptStatus);
   GlobalVariablesFlush();
   Print("ENTRY ATTEMPT RESULT | bar=",TimeToString(barTime,TIME_DATE|TIME_MINUTES),
         " direction=",(decision>0?"BUY":"SELL"),
         " opened=",(orderOpened?"true":"false"),
         " result=",g_lastEntryAttemptResult,
         " persistedStatus=",EntryAttemptStatusName(g_lastEntryAttemptStatus),
         " retryPolicy=WAIT_NEXT_NEW_BAR_AND_FULL_REVALIDATION retryAllowed=false_for_current_bar");
   Print("TRADE EVIDENCE PACKET | schema=1 phase=POST_ORDER source=CHART_LOCAL",
         " eaVersion=1.740 symbol=",Symbol()," canonicalAsset=",CanonicalAssetKey(Symbol()),
         " timeframe=",Period()," closedBarTime=",TimeToString(iTime(Symbol(),Period(),1),TIME_DATE|TIME_SECONDS),
         " decision=",(decision>0?"BUY":"SELL")," selectedModel=",bestStrategy,
         " expectedRScore=",DoubleToString(bestScore,6),
         " opened=",(orderOpened?"true":"false")," executionResult=",g_lastExecutionResult,
         " openPositionsAfter=",CountOpenTrades(),
         " openRiskAfterUSD=",DoubleToString(PortfolioOpenRiskUSD(),4),
         " portfolioRiskCapUSD=",DoubleToString(EffectivePortfolioRiskCapUSD(),4),
         " dailyNetUSD=",DoubleToString(TodayNetProfit(),4),
         " evidenceJSON=",modelsJson,
         " nextAction=",(orderOpened?"VERIFY_TICKET_READBACK_AND_POSITION_INVENTORY":"RETAIN_REJECTION_REASON_NO_BLIND_RETRY"));
   if(orderOpened) AuditExistingPositionSupervision("POST_CHART_LOCAL_ENTRY");
   SendSbtSnapshot(decision,decisionText,buyVotes,sellVotes,trend,momentum,donchian,meanrev,strictRange,
                   modelsJson,bestStrategy,bestScore,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                   true,"OK",g_lastExecutionResult);
}
