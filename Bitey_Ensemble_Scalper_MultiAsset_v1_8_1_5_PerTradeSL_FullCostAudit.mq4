//+------------------------------------------------------------------+
//| Bitey_Ensemble_Scalper_MultiAsset_v1_8_1_5_PerTradeSL_FullCostAudit.mq4
//| v1.8.1.5 EXPERIMENTAL = per-trade SL risk, no account-period loss brakes, detailed cost audit:        |
//|  1 Adaptive stop: widen the stop (up to InpStopATRMax x ATR) until   |
//|    cost-R <= InpTargetCostR; lots shrink so risk stays constant.     |
//|  2 Selectivity: InpMinScore gate and InpMaxTradesPerDay cap.         |
//|  3 Let winners run: RR 2.0 in trend regime, 1.5 in range regime.     |
//|  4 InpMaxCostR 0.20 -> 0.15.                                         |
//|  5 Cheap assets first: ranking subtracts InpCostRankExtra x cost-R.  |
//|  6 Optional limit entries (InpUseLimitEntry, default OFF): resting   |
//|    order at the touch price to save the spread; unfilled orders are  |
//|    deleted after InpLimitExpireBars bars. Beware adverse selection.  |
//|  Profit selector (InpUseProfitSelector): per-symbol realized net     |
//|    edge in R (shrunk toward a prior) feeds the ranking and a soft    |
//|    ban; every ranked pick is logged to the ActionLog (SELECTOR).     |
//| Inherited: 1.8.0.8 equity-token session, prefilter, crypto priority, |
//|  30 evaluators / 2 assemblies, audit CSV, adaptive exits, guards.    |
//| Not compiled or performance-validated; test in the MT4 tester first. |
//+------------------------------------------------------------------+
#property strict
#property version   "1.815"
#property description "Experimental multi-asset ensemble / per-trade SL / full cost audit / no daily or monthly loss brake; not validated"

input int              InpMagic                 = 21102027;  // Declared first: the CSV module below uses it
bool g_csvFailed = false;   // true while the last audit CSV open failed
#define BITEY_CSV_DELIMITER ';'
string BiteyCsvStamp()
{
   return TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
}
int BiteyCsvOpenAppend(const string fileName, const string header)
{
   int h = FileOpen(fileName, FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,
                    BITEY_CSV_DELIMITER);
   if(h == INVALID_HANDLE)
   {
      Print("BITEY_CSV_ERROR|open|", fileName, "|err=", GetLastError());
      g_csvFailed = true;
      return INVALID_HANDLE;
   }
   g_csvFailed = false;
   if(FileSize(h) == 0)
   {
      FileWriteString(h, header + "\r\n");
      FileFlush(h);
   }
   FileSeek(h, 0, SEEK_END);
   return h;
}
void BiteyCsvClose(int h)
{
   if(h != INVALID_HANDLE)
   {
      FileFlush(h);
      FileClose(h);
   }
}
void BiteyCsvLogAction(
   const string decisionId, const string eaVersion, const string symbol,
   const string stage, const string action, const int ticket,
   const string direction, const double score, const string reason)
{
   string fn = "Bitey_ActionLog.csv";
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;symbol;stage;action;ticket;direction;score;reason");
   if(h == INVALID_HANDLE) return;
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, symbol, stage, action,
      ticket, direction, DoubleToString(score, 6), reason);
   BiteyCsvClose(h);
}
void BiteyCsvLogEvaluatorVote(
   const string decisionId, const string eaVersion, const string symbol,
   const int timeframe, const string modelId, const string modelFamily,
   const string direction, const double rawScore, const double modelWeight,
   const double confidence, const bool signalValid, const string reason)
{
   string fn = "Bitey_EvaluatorVotes.csv";
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;symbol;timeframe;model_id;model_family;direction;raw_score;model_weight;confidence;signal_valid;reason");
   if(h == INVALID_HANDLE) return;
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, symbol, timeframe,
      modelId, modelFamily, direction, DoubleToString(rawScore, 6),
      DoubleToString(modelWeight, 6), DoubleToString(confidence, 6),
      (signalValid ? "true" : "false"), reason);
   BiteyCsvClose(h);
}
void BiteyCsvLogAssetAssembly(
   const string decisionId, const string eaVersion, const string symbol,
   const int timeframe, const double opportunityScore, const double expectedNet,
   const double estimatedCost, const int validModels, const int buyVotes,
   const int sellVotes, const bool selected, const string reason)
{
   string fn = "Bitey_AssetAssembly.csv";
   // Estimates are per 1.00 lot (account currency); filled only after the evaluators ran.
   double ec = estimatedCost, en = expectedNet;
   if(ec <= 0.0 && validModels > 0)
   {
      double sc0, cm0;
      EstCostPerLot(symbol, sc0, cm0);
      ec = sc0 + cm0;
      en = ExpectedNetPerLot(symbol);
   }
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;symbol;timeframe;opportunity_score;expected_net_estimate;estimated_cost;valid_models;buy_votes;sell_votes;selected;reason");
   if(h == INVALID_HANDLE) return;
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, symbol, timeframe,
      DoubleToString(opportunityScore, 6), DoubleToString(en, 2),
      DoubleToString(ec, 2), validModels, buyVotes, sellVotes,
      (selected ? "true" : "false"), reason);
   BiteyCsvClose(h);
}
void BiteyCsvLogTradeAssembly(
   const string decisionId, const string eaVersion, const string symbol,
   const int timeframe, const string direction, const double consensusScore,
   const double confidence, const int supportingModels, const int opposingModels,
   const double estimatedSpreadCost, const double estimatedCommission,
   const double estimatedSlippage, const bool approved, const string reason)
{
   string fn = "Bitey_TradeAssembly.csv";
   // Estimates are per 1.00 lot (account currency); slippage = the max slippage the EA accepts.
   double spc = estimatedSpreadCost, cmc = estimatedCommission, slc = estimatedSlippage;
   if(spc == 0.0 && cmc == 0.0 && slc == 0.0) EstExecCostPerLot(symbol, spc, cmc, slc);
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;symbol;timeframe;decision;consensus_score;confidence;supporting_models;opposing_models;estimated_spread_cost;estimated_commission;estimated_slippage;approved;reason");
   if(h == INVALID_HANDLE) return;
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, symbol, timeframe,
      direction, DoubleToString(consensusScore, 6), DoubleToString(confidence, 6),
      supportingModels, opposingModels, DoubleToString(spc, 2),
      DoubleToString(cmc, 2), DoubleToString(slc, 2),
      (approved ? "true" : "false"), reason);
   BiteyCsvClose(h);
}
void BiteyCsvLogTradeOpened(
   const string decisionId, const string eaVersion, const int ticket,
   const string symbol, const string direction, const double lots,
   const double openPrice, const double initialSL, const double initialTP,
   const double referenceCapital, const double riskMoney,
   const string riskMode, const string reason)
{
   string fn = "Bitey_TradeAudit_v1_8_1_5.csv";
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;ticket;magic;symbol;direction;lots;open_price;initial_sl;initial_tp;reference_capital_usd;risk_money_estimate;risk_mode;buy_votes;sell_votes;reason");
   if(h == INVALID_HANDLE) return;
   int digits=(int)MarketInfo(symbol,MODE_DIGITS);
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, ticket, InpMagic, symbol,
      direction, DoubleToString(lots, 2), DoubleToString(openPrice, digits),
      DoubleToString(initialSL, digits), DoubleToString(initialTP, digits),
      DoubleToString(referenceCapital, 2), DoubleToString(riskMoney, 2),
      riskMode, (GlobalVariableCheck(GvKey("BUYV",ticket))?IntegerToString((int)GlobalVariableGet(GvKey("BUYV",ticket))):"0"),
      (GlobalVariableCheck(GvKey("SELLV",ticket))?IntegerToString((int)GlobalVariableGet(GvKey("SELLV",ticket))):"0"), reason);
   BiteyCsvClose(h);
}
bool BiteyCsvLogTradeClosed(
   const string decisionId, const string eaVersion, const int ticket,
   const string symbol, const string direction, const double lots,
   const datetime openedAt, const datetime closedAt, const double openPrice,
   const double closePrice, const double grossProfit, const double commission,
   const double swap, const double slippagePoints, const string closeReason)
{
   string fn = "Bitey_ClosedTrades_v1_8_1_5.csv";
   double net = grossProfit + commission + swap;
   int durationSeconds = (int)(closedAt - openedAt);
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;ticket;magic;symbol;direction;lots;opened_at;closed_at;duration_seconds;open_price;close_price;gross_profit;commission_actual;swap_actual;net_after_commission_swap;entry_slippage_points;buy_votes;sell_votes;close_reason;estimated_entry_spread_cost;estimated_entry_commission");
   if(h == INVALID_HANDLE) return(false);
   int digits=(int)MarketInfo(symbol,MODE_DIGITS);
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, ticket, InpMagic, symbol,
      direction, DoubleToString(lots, 2),
      TimeToString(openedAt, TIME_DATE|TIME_SECONDS),
      TimeToString(closedAt, TIME_DATE|TIME_SECONDS), durationSeconds,
      DoubleToString(openPrice, digits), DoubleToString(closePrice, digits),
      DoubleToString(grossProfit, 2), DoubleToString(commission, 2),
      DoubleToString(swap, 2), DoubleToString(net, 2),
      (slippagePoints <= -999998.0 ? "NA" : DoubleToString(slippagePoints, 1)),
      (GlobalVariableCheck(GvKey("BUYV",ticket))?IntegerToString((int)GlobalVariableGet(GvKey("BUYV",ticket))):"0"),
      (GlobalVariableCheck(GvKey("SELLV",ticket))?IntegerToString((int)GlobalVariableGet(GvKey("SELLV",ticket))):"0"), closeReason,
      DoubleToString(GlobalVariableCheck(GvKey("SPREADEST",ticket))?GlobalVariableGet(GvKey("SPREADEST",ticket)):0.0,2),
      DoubleToString(GlobalVariableCheck(GvKey("COMMEST",ticket))?GlobalVariableGet(GvKey("COMMEST",ticket)):0.0,2));
   BiteyCsvClose(h);
   return(true);
}
void BiteyCsvLogAdaptiveExit(
   const string decisionId, const string eaVersion, const int ticket,
   const string symbol, const double oldSL, const double newSL,
   const double oldTP, const double newTP, const double currentNet,
   const string reason)
{
   string fn = "Bitey_AdaptiveExits.csv";
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;ticket;symbol;old_sl;new_sl;old_tp;new_tp;current_net_profit;reason");
   if(h == INVALID_HANDLE) return;
   int digits=(int)MarketInfo(symbol,MODE_DIGITS);
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, ticket, symbol,
      DoubleToString(oldSL, digits), DoubleToString(newSL, digits),
      DoubleToString(oldTP, digits), DoubleToString(newTP, digits),
      DoubleToString(currentNet, 2), reason);
   BiteyCsvClose(h);
}
void BiteyCsvLogPerformance(
   const string eaVersion, const string scope, const string symbol,
   const int trades, const int wins, const int losses,
   const double grossProfit, const double commissions, const double swap,
   const double netClosedProfit, const double profitFactor,
   const double maxDrawdownPct, const double expectancyNet,
   const int abstentions, const string note)
{
   string fn = "Bitey_Performance.csv";
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;ea_version;scope;symbol;trades;wins;losses;gross_profit;commissions;swap;net_closed_profit;profit_factor;max_drawdown_pct;expectancy_net;abstentions;note");
   if(h == INVALID_HANDLE) return;
   FileWrite(h, BiteyCsvStamp(), eaVersion, scope, symbol, trades, wins, losses,
      DoubleToString(grossProfit, 2), DoubleToString(commissions, 2),
      DoubleToString(swap, 2), DoubleToString(netClosedProfit, 2),
      DoubleToString(profitFactor, 4), DoubleToString(maxDrawdownPct, 4),
      DoubleToString(expectancyNet, 4), abstentions, note);
   BiteyCsvClose(h);
}
#define EA_VERSION          "1.8.1.5-EXP-PER-TRADE-SL-FULL-COST-AUDIT"
#define MAX_SYMBOLS         256
#define HARD_MAX_POSITIONS  5
input string           InpSymbolsCSV            = "";      // Blank = symbols in Market Watch (aliases deduplicated)
input bool             InpAutoAddCrypto         = true;    // v1.5.2: add every tradable crypto the broker offers (not only Market Watch)
input bool             InpAutoAddUSDT           = true;    // v1.6.1: add every tradable *USDT symbol the broker offers (weekend-capable)
input bool             InpUSDTIs24x7            = true;    // v1.8.0.8: applies only to *USDT symbols whose ticker is a listed crypto; other *USDT are equity tokens with a stock session
input string           InpExtraCryptoPrefixes   = "LRC,IMX,FET,RENDER,APE,STX,AR,KAVA,QNT,ENA,ONDO,PENDLE,FLOKI,ORDI,BOME,WIF,JTO,TWT,ZIL,ONE,CHZ,ENJ,BAT,ZRX,DYDX,BLUR,MINA,ROSE,CELO,THETA,FLOW,QTUM,CKB,CFX,ASTR,AKT,TAO,STRK,SAFE,ASTER,VVV,TRUMP,LAB"; // Additional USD-quoted crypto tickers; USDT symbols are auto-discovered
input string           InpExtraSymbolsCSV       = "NEARUSDT,ZECUSDT"; // Always included; replaces a same-asset alias already listed (e.g. NEARUSD)
input ENUM_TIMEFRAMES  InpSignalTF              = PERIOD_M15; // M15: wider stops dilute spread+commission (was M5)
input ENUM_TIMEFRAMES  InpHTF                   = PERIOD_H1;   // Higher-timeframe bias (trend regime only)
input bool             InpUseHTFFilter          = true;
input double           InpReferenceCapitalUSD   = 500.0;
input bool             InpUseEquityRisk         = false;   // true = size risk on min(balance,equity) instead of the reference capital
input double           InpRiskPctPerTrade       = 0.5;     // Target loss budget for each position at its initial SL
input int              InpMaxOpenPositions      = 5;       // Clamped to 1..5, one position per asset
input double           InpMaxLotsFX             = 0.30;    // Hard lot cap, forex pairs
input double           InpMaxLotsOther          = 0.10;    // Hard lot cap, metals/crypto/stocks/indices
input double           InpCommissionPerLotFX    = 10.0;    // Tradewill statement: 0.01 lot = 0.10
input double           InpCommissionPerLotOther = 15.0;    // Tradewill statement: 0.01 lot = 0.15
input double           InpMaxCostR              = 0.15;    // v1.8.0.9 (was 0.20): skip if (spread+commission) > this fraction of the stop (R)
input bool             InpAllowBuy              = true;
input bool             InpAllowSell             = true;
input int              InpAssemblyMinFamilies   = 3;       // Trend assembly: minimum agreeing families (out of 4)
input int              InpAssemblyMinModelVotes = 3;       // Minimum directional models inside a family (out of 5)
input double           InpTrendADX              = 20.0;    // ADX >= this: trend regime, otherwise range regime
input bool             InpAllowTrendRegime      = true;    // A/B: disable to test range-only
input bool             InpAllowRangeRegime      = true;    // true = Bollinger/Stochastic families decide when ADX < InpTrendADX; false = trend-only (10 of 30 models inert)
input double           InpMinADX                = 10.0;    // Dead-market filter
input int              InpATRPeriod             = 14;
input double           InpStopATR               = 1.5;
input double           InpRewardRisk            = 2.0;     // v1.8.0.9 (was 1.8): reward/risk in TREND regime; winners must pay for the losers and the cost
input double           InpRewardRiskRange       = 1.5;     // v1.8.0.9: reward/risk in RANGE regime (mean reversion takes profit sooner)
input double           InpMaxSpreadPctOfStop    = 10.0;    // Spread must be <= this % of the stop distance
input int              InpMaxSpreadPoints       = 0;       // Optional absolute cap, 0 = off
input int              InpMaxQuoteAgeSec        = 120;
input int              InpSlippagePoints        = 20;
input int              InpMinBars               = 250;
input bool             InpUseSessionFilter      = true;    // Server hours; crypto is exempt
input int              InpSessionStartHour      = 7;
input int              InpSessionEndHour        = 21;
input int              InpCooldownBars          = 6;       // Bars to wait on a symbol after a LOSING trade
input int              InpReentryBars           = 3;       // Bars to wait on a symbol after a winning/flat trade
input int              InpMaxHoldBars           = 48;      // Time exit (0 = off)
input bool             InpBlockRollover         = true;    // No new entries inside the window
input bool             InpFlatBeforeRollover    = true;
input int              InpFridayFlatHour        = 22;      // Server hour on Friday: no entries and flat (non-crypto). 0 = off    // Close open trades when the window starts (avoids swap)
input int              InpRolloverStartMin      = 1410;    // Server minute of day (1410 = 23:30)
input int              InpRolloverEndMin        = 15;      // Server minute of day (15 = 00:15)
input int              InpExpectancyWindow      = 20;      // Last N closed trades per symbol
input int              InpExpectancyMinTrades   = 12;      // Need at least this many before judging a symbol
input int              InpExpectancyBanHours    = 24;      // Ban a symbol this long after its last close if net expectancy < 0
input bool             InpUseCorrelationGuard   = true;
input int              InpMaxCryptoPositions    = 2;       // Max simultaneous crypto positions (0 = no cap)
input int              InpMaxCcyExposure        = 2;       // Max net same-direction positions on one FX currency (0 = no cap)
input int              InpMaxCcyGross           = 3;       // v1.7.2: max positions touching one FX currency in ANY direction (0 = no cap)
input double           InpDiversifyPenalty      = 4.0;     // v1.7.2: score penalty per unit of same-direction overlap with open positions (0 = rank by raw score)
input bool             InpCryptoPriorityEnabled = true;    // Small tie-break preference for liquid major crypto candidates; never bypasses signal/risk filters
input double           InpCryptoPriorityTopBonus= 2.0;     // Max ranking bonus for BTC/ETH/SOL/XRP/BNB etc; does not bypass any risk/cost/correlation guard
input bool             InpPrefilterSpreadCost   = true;    // v1.8.0.8: drop candidates failing spread-vs-stop or cost-R BEFORE the 30 models and the ranking
input bool             InpTradeEquityTokens     = true;    // v1.8.0.8: trade stock/ETF *USDT symbols, but only inside the window below (false = exclude them)
input int              InpEquitySessionStartMin = 1005;    // Server minute of day (1005 = 16:45); US cash open + 15 min. Check against your broker and US DST
input int              InpEquitySessionEndMin   = 1350;    // Server minute of day (1350 = 22:30); stop new entries before the close
input int              InpMaxEquityPositions    = 2;       // Max simultaneous equity-token positions (0 = no cap); they move together with US indices
input double           InpStopATRMax            = 2.25;    // v1.8.0.9: widest stop (x ATR) the adaptive stop may use to cut cost-R; = InpStopATR disables widening
input double           InpTargetCostR           = 0.10;    // v1.8.0.9: widen the stop in 0.25 ATR steps until cost-R <= this (0 = off)
input double           InpMinScore              = 30.0;    // v1.8.0.9: minimum ensemble score to enter (30 = 3 agreeing families; 0 = off)
input int              InpMaxTradesPerDay       = 12;      // v1.8.0.9: cap on trades opened per server day (0 = off)
input bool             InpUseProfitSelector     = true;    // v1.8.0.9: rank and ban by each symbol's realized net edge (R) and cost-R
input bool             InpUseChatGPTIndicator    = false;   // Optional external ChatGPT bridge; OFF by default
input string           InpChatGPTIndicatorURL    = "";      // User-operated bridge endpoint; plain numeric response only
input double           InpChatGPTBonusMax        = 5.0;     // Clamp ranking bonus to +/- absolute value
input int              InpChatGPTTimeoutMs       = 700;     // Short timeout; failures produce zero bonus
input bool             InpChatGPTLog             = true;    // Log advisory success/failure
input int              InpMemWindow             = 30;      // Last N closed trades per symbol used by the selector
input int              InpMemDays               = 60;      // ...and not older than this many days
input int              InpMemMinTrades          = 6;       // Soft ban only after this many trades on the symbol
input double           InpMemPriorWeight        = 8.0;     // Shrinkage: the prior counts as this many trades (small samples stay near the prior)
input double           InpMemPriorEdgeR         = 0.0;     // Prior net edge per trade in R
input double           InpMemWeight             = 10.0;    // Ranking points per +1R of shrunk net edge
input double           InpMinNetEdgeR           = 0.30;    // Soft ban when shrunk net edge < -this R (with >= InpMemMinTrades trades)
input double           InpCostRankExtra         = 15.0;    // Ranking points subtracted per 1.0 of cost-R (cheap assets first)
input bool             InpUseLimitEntry         = false;   // v1.8.0.9: EXPERIMENTAL resting entry at the touch price instead of market (saves spread; fills skew to losers)
input double           InpLimitMaxSpreadMult    = 1.5;     // Limit distance may be at most this x spread, else market entry
input int              InpLimitExpireBars       = 2;       // Delete an unfilled limit order after this many signal bars
input bool             InpPrefilterMinLot       = true;    // v1.8.0.7: drop candidates whose minimum lot already exceeds the per-trade risk budget (before ranking)
input bool             InpUseMeanExit           = true;
input int              InpExitMAPeriod          = 20;      // SMA used as the mean
input double           InpExitBandATR           = 1.0;     // Opposite band = mean +/- this many ATR
input double           InpMeanExitMinR          = 0.5;     // At the mean, close only if net profit >= this fraction of R
input bool             InpEnableAdaptiveExits   = true;
input double           InpBreakEvenTriggerATR   = 1.0;     // Start protecting sooner; broker stop/freeze levels still apply
input double           InpBreakEvenLockATR      = 0.15;    // Plus commission is added automatically
input double           InpTrailStartATR         = 1.2;
input double           InpTrailDistanceATR      = 0.9;
input double           InpTrailStepATR          = 0.08;    // Minimum SL improvement per modification
input double           InpTrailTightenPerATR     = 0.15;    // Tighten trail as unrealized gain grows
input double           InpTrailMinDistanceATR    = 0.45;    // Minimum ATR distance for adaptive trail
input double           InpTPExpandTriggerATR    = 1.5;
input double           InpTPExpandBufferATR     = 1.0;
input double           InpTPExpandStepATR       = 0.25;    // Minimum TP extension per modification (fewer broker requests)
input bool             InpEnableTPExpand        = true;    // false = fixed TP (A/B tests)
input double           InpTPExpandADXMin        = 22.0;
input double           InpTPMaxDistanceATR      = 5.0;
input double           InpNetTargetR            = 0.0;     // Optional close at +N R net (0 = off; let adaptive TP run)
input bool             InpEnableNetProfitLock    = true;    // Cost-aware USD profit lock after net trigger
input double           InpProfitLockTriggerR    = 0.50;    // Begin cost-aware profit protection earlier
input double           InpProfitLockTargetR     = 0.10;    // Net profit (in R) targeted by the SL after estimated costs
input double           InpProfitLockStepR       = 0.05;    // Smaller steps to ratchet the net lock upward
input bool             InpEnableConfirmedReversalExit = true; // Exit profitable trades on a closed-bar EMA reversal
input int              InpReversalFastMAPeriod   = 9;
input int              InpReversalSlowMAPeriod   = 21;
input double           InpReversalExitMinR       = 0.0;     // 0 = exit once net P/L is non-negative; no fill guarantee
input bool             InpEnableTrading         = true;    // false = log candidates only
input bool             InpLogRejects            = false;
input bool             InpLogTradesCSV          = true;    // Per-trade audit CSV -> terminal MQL4\Files\Bitey_Ens_TradeAudit_<magic>.csv
input bool             InpLogAssetSummaryCSV    = true;    // Net summary CSV in this terminal MQL4\\Files folder
input int              InpRejectLogMinutes      = 60;      // Throttle for reject rows (CSV and Print): same symbol+reason is logged again only after N minutes (0 = log all)
input bool             InpRequireCsvAudit       = true;    // No NEW entries while the audit CSV cannot be written
input int              InpLogVotesMode          = 1;       // 30 vote rows -> 0 = every evaluation, 1 = only when Assembly 2 approves a direction, 2 = never
input bool             InpLogLegacyClosed       = false;   // true = also write closed trades the EA never tracked (older versions, same magic)
input int              InpMaxClosedRowsPerScan  = 25;      // Max closed-trade rows written per 20 s scan (keeps catch-up from freezing the EA)
string   g_symbols[MAX_SYMBOLS];
string   g_keys[MAX_SYMBOLS];
datetime g_lastBar[MAX_SYMBOLS];
int      g_symbolCount = 0;
uint     g_lastCycleTick = 0;
datetime g_lastHeartbeat = 0;
datetime g_lastDailyBlockLog = 0;
datetime g_lastCsvScan = 0;
datetime g_lastNetSummaryScan = 0;
bool     g_haltAll = false;    // Legacy variable retained; no equity-floor trigger in this build
int      g_tmpRegime = 0;      // 1 = trend, 2 = range (set by Analyze)
int      g_tmpValidModels = 0;
int      g_tmpBuyVotes = 0;
int      g_tmpSellVotes = 0;
int      g_candReg[MAX_SYMBOLS];
datetime g_lastRejectLog[MAX_SYMBOLS];
string   g_candSym[MAX_SYMBOLS];
int      g_candCmd[MAX_SYMBOLS];
double   g_candScore[MAX_SYMBOLS];
bool     g_candUsed[MAX_SYMBOLS];
int      g_candBuyVotes[MAX_SYMBOLS];
double   g_candEdge[MAX_SYMBOLS];      // v1.8.0.9: shrunk realized net edge (R)
int      g_candMemN[MAX_SYMBOLS];      // trades behind that edge
double   g_candCostR[MAX_SYMBOLS];     // cost-R at the adaptive stop
double   g_candChatGPTBonus[MAX_SYMBOLS]; // External advisory ranking bonus; never a trade command
int      g_candSellVotes[MAX_SYMBOLS];
int      g_abstentions = 0;        // evaluations that ended without a trade direction
int      g_lastPerfClosed = -1;    // closed-trade count at the last Bitey_Performance snapshot
int      g_closeTicket[64];        // ring buffer ticket -> reason the EA closed it
string   g_closeReason[64];
int      g_closeN = 0;
string   g_lastRejectCsvWhy[MAX_SYMBOLS];
datetime g_lastRejectCsvTime[MAX_SYMBOLS];
void BiteyCsvInitializeFiles()
{
   int h;
   h=BiteyCsvOpenAppend("Bitey_ActionLog.csv","timestamp;decision_id;ea_version;symbol;stage;action;ticket;direction;score;reason");
   if(h!=INVALID_HANDLE) BiteyCsvClose(h);
   h=BiteyCsvOpenAppend("Bitey_EvaluatorVotes.csv","timestamp;decision_id;ea_version;symbol;timeframe;model_id;model_family;direction;raw_score;model_weight;confidence;signal_valid;reason");
   if(h!=INVALID_HANDLE) BiteyCsvClose(h);
   h=BiteyCsvOpenAppend("Bitey_AssetAssembly.csv","timestamp;decision_id;ea_version;symbol;timeframe;opportunity_score;expected_net_estimate;estimated_cost;valid_models;buy_votes;sell_votes;selected;reason");
   if(h!=INVALID_HANDLE) BiteyCsvClose(h);
   h=BiteyCsvOpenAppend("Bitey_TradeAssembly.csv","timestamp;decision_id;ea_version;symbol;timeframe;decision;consensus_score;confidence;supporting_models;opposing_models;estimated_spread_cost;estimated_commission;estimated_slippage;approved;reason");
   if(h!=INVALID_HANDLE) BiteyCsvClose(h);
   h=BiteyCsvOpenAppend("Bitey_TradeAudit_v1_8_0_2.csv","timestamp;decision_id;ea_version;ticket;magic;symbol;direction;lots;open_price;initial_sl;initial_tp;reference_capital_usd;risk_money_estimate;risk_mode;buy_votes;sell_votes;reason");
   if(h!=INVALID_HANDLE) BiteyCsvClose(h);
   h=BiteyCsvOpenAppend("Bitey_ClosedTrades_v1_8_0_2.csv","timestamp;decision_id;ea_version;ticket;magic;symbol;direction;lots;opened_at;closed_at;duration_seconds;open_price;close_price;gross_profit;commission;swap;net_profit;slippage_points;buy_votes;sell_votes;close_reason");
   if(h!=INVALID_HANDLE) BiteyCsvClose(h);
   h=BiteyCsvOpenAppend("Bitey_AdaptiveExits.csv","timestamp;decision_id;ea_version;ticket;symbol;old_sl;new_sl;old_tp;new_tp;current_net_profit;reason");
   if(h!=INVALID_HANDLE) BiteyCsvClose(h);
   h=BiteyCsvOpenAppend("Bitey_Performance.csv","timestamp;ea_version;scope;symbol;trades;wins;losses;gross_profit;commissions;swap;net_closed_profit;profit_factor;max_drawdown_pct;expectancy_net;abstentions;note");
   if(h!=INVALID_HANDLE) BiteyCsvClose(h);
   BiteyCsvLogAction("startup_"+IntegerToString((int)TimeCurrent()),EA_VERSION,Symbol(),
      "LIFECYCLE","EA_INITIALIZED",0,"NONE",0.0,"CSV_FILES_INITIALIZED");
   Print("BITEY_CSV_INIT | files=8 | folder=MQL4\\Files | action=Bitey_ActionLog.csv");
}
int OnInit()
{
   ParseSymbols();
   AddExtraSymbols();
   AddAllCrypto();
   BiteyCsvInitializeFiles();
   if(g_csvFailed)
      Print("CSV_AUDIT_WARNING | audit CSV cannot be written; new entries stay blocked while InpRequireCsvAudit=true");
   if(g_symbolCount<=0) { Print("INIT_ERROR | no symbols found"); return(INIT_FAILED); }
   for(int i=0;i<g_symbolCount;i++)
   {
      g_lastBar[i]=0;
      SymbolSelect(g_symbols[i],true);
   }
   EventSetTimer(1);
   if(InpUseChatGPTIndicator) Print("CHATGPT_INDICATOR_INIT | enabled=ON | endpointConfigured=",(StringLen(InpChatGPTIndicatorURL)>7?"YES":"NO")," | mode=RANKING_ONLY");
   Print("BITEY_ENSEMBLE_INIT | version=",EA_VERSION," | symbols=",g_symbolCount,
         " | maxPositions=",MaxPositions()," | tf=",(int)InpSignalTF,
         " | accountMode=NOT_A_GATE | trading=",(InpEnableTrading?"ON":"OFF"));
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick()  { RunCycle(); }
void OnTimer() { RunCycle(); }
int MaxPositions()
{
   return(MathMin(HARD_MAX_POSITIONS,MathMax(1,InpMaxOpenPositions)));
}
string AssetKey(string s)
{
   StringToUpper(s);
   if(StringLen(s)>0 && StringGetChar(s,0)=='#') s=StringSubstr(s,1);
   string k="";
   for(int i=0;i<StringLen(s) && StringLen(k)<6;i++)
   {
      int ch=StringGetChar(s,i);
      bool alnum=((ch>='0' && ch<='9') || (ch>='A' && ch<='Z'));
      if(!alnum) break;
      k+=CharToString((uchar)ch);
   }
   return(k);
}
bool IsUSDTSymbol(string sym)
{
   string nm=sym;
   StringToUpper(nm);
   return(StringFind(nm,"USDT")>=1);
}
string CryptoBaseList()
{
   return("BTC,XBT,ETH,SOL,XRP,LTC,BCH,DOG,ADA,DOT,LINK,AVAX,BNB,NEAR,ZEC,TRX,ATOM,FIL,ALGO,DASH,IOTA,ETC,UNI,AXS,HYPE,SHIB,MATIC,POL,XLM,XMR,EOS,NEO,AAVE,APT,ARB,SUI,INJ,TON,ICP,HBAR,VET,SAND,MANA,CRV,GRT,XTZ,COMP,MKR,SNX,RUNE,FTM,EGLD,KAS,OP,PEPE,BONK,WLD,SEI,TIA,JUP,LRC,IMX,FET,RENDER,APE,STX,KAVA,QNT,ENA,ONDO,PENDLE,FLOKI,ORDI,BOME,WIF,JTO,TWT,ZIL,ONE,CHZ,ENJ,BAT,ZRX,DYDX,BLUR,MINA,ROSE,CELO,THETA,FLOW,QTUM,CKB,CFX,ASTR,AKT,TAO,STRK,SAFE,ENS,1INCH,ANKR,API3,ARPA,AST,AUCTION,BAND,BICO,BLZ,C98,CAKE,CEEK,CELR,CHR,CTSI,CVC,DENT,DEXE,DGB,DODO,EDU,ELF,FLUX,FORTH,FXS,GAS,GLM,GMX,GRASS,HFT,HIGH,HOOK,ID,ILV,IO,IOST,IOTX,JASMY,KNC,LEVER,LINA,LOOKS,LPT,LQTY,LTO,MAGIC,MASK,MAV,MBOX,METIS,MOVR,MTL,NKN,NMR,NTRN,OCEAN,OGN,OM,OMG,ONT,ORBS,OSMO,PERP,PHB,PIXEL,POWR,PRIME,PROM,PYTH,QI,RAY,REEF,REN,REQ,RLC,RSR,RVN,SAGA,SCRT,SKL,SLP,SPELL,SSV,STG,STORJ,STRAX,SUN,SUPER,SUSHI,SXP,TRB,TRU,UMA,UNFI,USUAL,VANRY,VIC,WAXP,WIN,WOO,XAI,XEC,XEM,XVG,YFI,YGG,ZETA,ZEN,ZRO");
}
// Exact ticker match (no prefix logic): DOGE matches DOGE, LRCX (a stock) does not match LRC.
bool CryptoTickerExact(string tk)
{
   StringToUpper(tk);
   StringTrimLeft(tk); StringTrimRight(tk);
   if(StringLen(tk)>0 && StringGetChar(tk,0)=='#') tk=StringSubstr(tk,1);
   if(StringLen(tk)<2) return(false);
   string all=","+CryptoBaseList()+",DOGE,"+InpExtraCryptoPrefixes+",";
   StringToUpper(all);
   StringReplace(all," ","");
   return(StringFind(all,","+tk+",")>=0);
}
bool IsCrypto(string sym)
{
   string k=AssetKey(sym);
   string nm=sym;
   StringToUpper(nm);
   int uq=StringFind(nm,"USDT");
   if(InpUSDTIs24x7 && uq>=1) return(CryptoTickerExact(StringSubstr(nm,0,uq)));   // v1.8.0.8: unlisted *USDT are equity tokens, not crypto
   if(StringFind(nm,"USD")<2) return(false);   // crypto CFDs here are quoted vs USD/USDT; avoids stock tickers like LIN, UNI, COMP
   // USD-quoted crypto prefixes commonly offered as broker CFDs. USDT pairs are discovered separately.
   // Keep this list broad but explicit: arbitrary *USD symbols may be stocks or FX, not crypto.
   string p=CryptoBaseList();
   while(StringLen(p)>0)
   {
      int q=StringFind(p,",");
      string t;
      if(q<0) { t=p; p=""; } else { t=StringSubstr(p,0,q); p=StringSubstr(p,q+1); }
      if(StringLen(t)>0 && StringFind(k,t)==0) return(true);
   }
   string ex=InpExtraCryptoPrefixes;
   StringToUpper(ex);
   while(StringLen(ex)>0)
   {
      int q=StringFind(ex,",");
      string t;
      if(q<0) { t=ex; ex=""; } else { t=StringSubstr(ex,0,q); ex=StringSubstr(ex,q+1); }
      StringTrimLeft(t); StringTrimRight(t);
      if(StringLen(t)>0 && StringFind(k,t)==0) return(true);
   }
   return(false);
}
// *USDT symbol whose ticker is not a listed crypto (TSLAUSDT, AMDUSDT, LRCXUSDT...): stock/ETF token with market hours.
bool IsEquityToken(string sym)
{
   return(IsUSDTSymbol(sym) && !IsCrypto(sym));
}
bool IsCcy(string c)
{
   string l[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   for(int i=0;i<8;i++)
      if(c==l[i]) return(true);
   return(false);
}
bool IsForex(string sym)
{
   string k=AssetKey(sym);
   if(StringLen(k)!=6) return(false);
   return(IsCcy(StringSubstr(k,0,3)) && IsCcy(StringSubstr(k,3,3)));
}
double CommissionPerLot(string sym)
{
   return(IsForex(sym)?InpCommissionPerLotFX:InpCommissionPerLotOther);
}
double LotCap(string sym)
{
   return(IsForex(sym)?InpMaxLotsFX:InpMaxLotsOther);
}
void ParseSymbols()
{
   g_symbolCount=0;
   if(IsTesting()) { AddSymbol(Symbol()); return; }   // Strategy Tester models the chart symbol only
   string csv=InpSymbolsCSV;
   StringTrimLeft(csv); StringTrimRight(csv);
   if(StringLen(csv)==0)
   {
      int total=SymbolsTotal(true);
      for(int i=0;i<total && g_symbolCount<MAX_SYMBOLS;i++)
         AddSymbol(SymbolName(i,true));
      return;
   }
   while(StringLen(csv)>0 && g_symbolCount<MAX_SYMBOLS)
   {
      int p=StringFind(csv,",");
      string s;
      if(p<0) { s=csv; csv=""; }
      else { s=StringSubstr(csv,0,p); csv=StringSubstr(csv,p+1); }
      StringTrimLeft(s); StringTrimRight(s);
      AddSymbol(s);
   }
}
void AddSymbol(string s)
{
   if(StringLen(s)<=0) return;
   string k=AssetKey(s);
   if(StringLen(k)<3) return;
   for(int i=0;i<g_symbolCount;i++)
      if(g_keys[i]==k) return;            // alias of an asset already listed
   g_symbols[g_symbolCount]=s;
   g_keys[g_symbolCount]=k;
   g_symbolCount++;
}
// Small ranking tie-break only: never creates a signal and never bypasses cost/risk filters.
double CryptoPriorityBonus(string sym)
{
   if(!InpCryptoPriorityEnabled || !IsCrypto(sym)) return(0.0);
   string nm=sym;
   StringToUpper(nm);
   if(StringLen(nm)>0 && StringGetChar(nm,0)=='#') nm=StringSubstr(nm,1);
   int q=StringFind(nm,"USDT");
   if(q<=0) q=StringFind(nm,"USD");
   string k=(q>0 ? StringSubstr(nm,0,q) : AssetKey(sym));   // full ticker: DOGE, AVAX, NEAR... (AssetKey stops at 6 chars)
   string tier1=",BTC,XBT,ETH,SOL,XRP,BNB,ADA,DOGE,LTC,BCH,LINK,AVAX,DOT,TRX,TON,";
   if(StringFind(tier1,","+k+",")>=0) return(MathMax(0.0,InpCryptoPriorityTopBonus));
   // Tier 2: established liquid alternatives; lower preference than tier 1.
   string tier2=",NEAR,ZEC,UNI,AAVE,ETC,ATOM,SUI,APT,ARB,OP,INJ,FIL,XLM,HBAR,ICP,RENDER,TAO,SHIB,";
   if(StringFind(tier2,","+k+",")>=0) return(MathMax(0.0,InpCryptoPriorityTopBonus)*0.5);
   return(0.0);
}

void RunCycle()
{
   if(!IsTesting())
   {
      uint nowTick=GetTickCount();
      if(g_lastCycleTick!=0 && (nowTick-g_lastCycleTick)<900) return;
      g_lastCycleTick=nowTick;
   }
   ManageExits();
   ManagePendingLimits();
   LogClosedTrades();
   WriteAssetNetSummary(); // Read-only audit; does not alter orders or signals
   // No daily/monthly/equity-floor loss brake in this research build; per-trade SL remains active.
   int maxPos=MaxPositions();   int limit=g_symbolCount;
   int nc=0;
   for(int i=0;i<limit;i++)
   {
      string sym=g_symbols[i];
      datetime bt=iTime(sym,InpSignalTF,0);
      if(bt<=0 || bt==g_lastBar[i]) continue;
      bool firstSight=(g_lastBar[i]==0);
      g_lastBar[i]=bt;                      // one evaluation per closed bar per symbol
      if(firstSight) continue;              // never trade on the bar where the EA started
      if(CountOpenPositions()>=maxPos) { Reject(sym,"MAX_POSITIONS"); continue; }
      int cmd; double score; string why;
      if(!Prefilter(sym,why))
      {
         string rejectId=sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1));
         if(RejectCsvDue(sym,"PREFILTER_"+why))
         {
            BiteyCsvLogAssetAssembly(rejectId,EA_VERSION,sym,InpSignalTF,0.0,0.0,0.0,0,0,0,false,"PREFILTER_REJECT_"+why);
            BiteyCsvLogAction(rejectId,EA_VERSION,sym,"ASSEMBLY1","REJECT",0,"ABSTAIN",0.0,"PREFILTER_"+why);
         }
         RejectQuiet(sym,why); continue;
      }
      if(!Analyze(sym,cmd,score,why))
      {
         string rejectId=sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1));
         BiteyCsvLogAssetAssembly(rejectId,EA_VERSION,sym,InpSignalTF,score,0.0,0.0,g_tmpValidModels,g_tmpBuyVotes,g_tmpSellVotes,false,"SIGNAL_REJECT_"+why);
         g_abstentions++;
         BiteyCsvLogAction(rejectId,EA_VERSION,sym,"ASSEMBLY2","ABSTAIN",0,"ABSTAIN",score,why);
         RejectQuiet(sym,why); continue;
      }
      if(cmd==OP_BUY && !InpAllowBuy)  { Reject(sym,"BUY_DISABLED");  continue; }
      if(cmd==OP_SELL && !InpAllowSell) { Reject(sym,"SELL_DISABLED"); continue; }
      if(InpMinScore>0.0 && score<InpMinScore)
      {
         if(RejectCsvDue(sym,"SELECTOR_SCORE_BELOW_MIN"))
            BiteyCsvLogAction(sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1)),EA_VERSION,sym,"SELECTOR","REJECT",0,
               (cmd==OP_BUY?"BUY":"SELL"),score,"SCORE_BELOW_MIN");
         RejectQuiet(sym,"SCORE_BELOW_MIN"); continue;
      }
      int memN=0; double memEdge=0.0;
      double candCost=CandCostR(sym);
      if(InpUseProfitSelector)
      {
         memEdge=NetEdgeR(sym,memN);
         if(InpMemMinTrades>0 && memN>=InpMemMinTrades && memEdge<-InpMinNetEdgeR)
         {
            if(RejectCsvDue(sym,"SELECTOR_NEGATIVE_NET_EDGE"))
               BiteyCsvLogAction(sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1)),EA_VERSION,sym,"SELECTOR","REJECT",0,
                  (cmd==OP_BUY?"BUY":"SELL"),score,"NEGATIVE_NET_EDGE edgeR="+DoubleToString(memEdge,3)+" n="+IntegerToString(memN));
            RejectQuiet(sym,"NEGATIVE_NET_EDGE"); continue;
         }
      }
      BiteyCsvLogAssetAssembly(sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1)),EA_VERSION,sym,InpSignalTF,
         score,0.0,0.0,g_tmpValidModels,g_tmpBuyVotes,g_tmpSellVotes,false,"ELIGIBLE_CANDIDATE_POOL");
      g_candSym[nc]=sym; g_candCmd[nc]=cmd; g_candScore[nc]=score; g_candReg[nc]=g_tmpRegime;
      g_candBuyVotes[nc]=g_tmpBuyVotes; g_candSellVotes[nc]=g_tmpSellVotes;
      g_candEdge[nc]=memEdge; g_candMemN[nc]=memN; g_candCostR[nc]=candCost;
      g_candChatGPTBonus[nc]=ChatGPTIndicatorBonus(sym,cmd,score); nc++;
   }
   if(nc>0)
   {
      for(int a=0;a<nc-1;a++)
         for(int b=a+1;b<nc;b++)
            if(g_candScore[b]>g_candScore[a])
            {
               string ts=g_candSym[a]; g_candSym[a]=g_candSym[b]; g_candSym[b]=ts;
               int tc=g_candCmd[a];    g_candCmd[a]=g_candCmd[b];  g_candCmd[b]=tc;
               double td=g_candScore[a]; g_candScore[a]=g_candScore[b]; g_candScore[b]=td;
               int tg=g_candReg[a];     g_candReg[a]=g_candReg[b];     g_candReg[b]=tg;
               int tb=g_candBuyVotes[a]; g_candBuyVotes[a]=g_candBuyVotes[b]; g_candBuyVotes[b]=tb;
               int tsell=g_candSellVotes[a]; g_candSellVotes[a]=g_candSellVotes[b]; g_candSellVotes[b]=tsell;
               double te9=g_candEdge[a]; g_candEdge[a]=g_candEdge[b]; g_candEdge[b]=te9;
               int tn9=g_candMemN[a]; g_candMemN[a]=g_candMemN[b]; g_candMemN[b]=tn9;
               double tk9=g_candCostR[a]; g_candCostR[a]=g_candCostR[b]; g_candCostR[b]=tk9;
               double tcb=g_candChatGPTBonus[a]; g_candChatGPTBonus[a]=g_candChatGPTBonus[b]; g_candChatGPTBonus[b]=tcb;
            }
      string blockWhy=EntryBlockReason();   // CSV integrity and non-loss entry constraints only
      if(blockWhy!="")
      {
         for(int blocked=0;blocked<nc;blocked++)
            BiteyCsvLogAction(g_candSym[blocked]+"_"+IntegerToString((int)iTime(g_candSym[blocked],InpSignalTF,1)),EA_VERSION,g_candSym[blocked],"ENTRY_GUARD","REJECT",0,(g_candCmd[blocked]==OP_BUY?"BUY":"SELL"),g_candScore[blocked],blockWhy);
         if(g_lastDailyBlockLog==0 || TimeCurrent()-g_lastDailyBlockLog>=300)
         {
            g_lastDailyBlockLog=TimeCurrent();
            Print("ENTRY_BLOCK | reason=",blockWhy," dayNet=",DoubleToString(TodayNet(),2),
                  " monthNet=",DoubleToString(MonthNet(),2)," | no new entries; open trades stay managed");
         }
      }
      else
      {
         for(int c0=0;c0<nc;c0++) g_candUsed[c0]=false;
         for(int pick=0;pick<nc;pick++)
         {
            if(CountOpenPositions()>=maxPos) break;
            if(InpMaxTradesPerDay>0 && TradesOpenedToday()>=InpMaxTradesPerDay) break;
            int best=-1; double bestAdj=-1.0e100, bestOv=0.0;
            for(int c=0;c<nc;c++)
            {
               if(g_candUsed[c]) continue;
               double ov=DiversifyOverlap(g_candSym[c],g_candCmd[c]);
               double cryptoBonus=CryptoPriorityBonus(g_candSym[c]);
               double adj=g_candScore[c]-InpDiversifyPenalty*ov+cryptoBonus
                          +(InpUseProfitSelector ? InpMemWeight*g_candEdge[c]-InpCostRankExtra*g_candCostR[c] : 0.0)
                          +g_candChatGPTBonus[c];
               if(adj>bestAdj) { bestAdj=adj; best=c; bestOv=ov; }
            }
            if(best<0) break;
            g_candUsed[best]=true;
            string corrWhy="";
            if(!CorrelationOK(g_candSym[best],g_candCmd[best],corrWhy))
            {
               LogCandidateNotSelected(best,"CORRELATION_"+corrWhy);
               RejectQuiet(g_candSym[best],corrWhy);
               if(RejectLogDue(g_candSym[best])) Print("CORRELATION_BLOCK | symbol=",g_candSym[best]," reason=",corrWhy);
               continue;
            }
            if(bestOv>0.0)
               Print("DIVERSIFY_RANK | symbol=",g_candSym[best]," rawScore=",DoubleToString(g_candScore[best],1),
                     " overlap=",DoubleToString(bestOv,1)," adjScore=",DoubleToString(bestAdj,1));
            double pickedCryptoBonus=CryptoPriorityBonus(g_candSym[best]);
            if(pickedCryptoBonus>0.0)
               Print("CRYPTO_PRIORITY_RANK | symbol=",g_candSym[best]," rawScore=",DoubleToString(g_candScore[best],1),
                     " priorityBonus=",DoubleToString(pickedCryptoBonus,2)," adjustedScore=",DoubleToString(bestAdj,1));
            BiteyCsvLogAssetAssembly(g_candSym[best]+"_"+IntegerToString((int)iTime(g_candSym[best],InpSignalTF,1)),EA_VERSION,
               g_candSym[best],InpSignalTF,g_candScore[best],0.0,0.0,30,g_candBuyVotes[best],g_candSellVotes[best],true,"ASSEMBLY1_SELECTED_FOR_EXECUTION");
            string selectedId=g_candSym[best]+"_"+IntegerToString((int)iTime(g_candSym[best],InpSignalTF,1));
            BiteyCsvLogAction(selectedId,EA_VERSION,g_candSym[best],"ASSEMBLY1","SELECT",0,
               (g_candCmd[best]==OP_BUY?"BUY":"SELL"),g_candScore[best],"TOP_RANKED_CANDIDATE");
            BiteyCsvLogAction(selectedId,EA_VERSION,g_candSym[best],"SELECTOR","RANKED",0,
               (g_candCmd[best]==OP_BUY?"BUY":"SELL"),bestAdj,
               "edgeR="+DoubleToString(g_candEdge[best],3)+" memN="+IntegerToString(g_candMemN[best])+
               " costR="+DoubleToString(g_candCostR[best],3)+" rawScore="+DoubleToString(g_candScore[best],1));
            OpenTrade(g_candSym[best],g_candCmd[best],g_candScore[best],g_candReg[best],g_candBuyVotes[best],g_candSellVotes[best]);
         }
         for(int cv=0;cv<nc;cv++)
            if(!g_candUsed[cv]) LogCandidateNotSelected(cv,"NOT_SELECTED_NO_FREE_SLOT");
      }
   }
   datetime now=TimeCurrent();
   if(g_lastHeartbeat==0 || now-g_lastHeartbeat>=300)
   {
      g_lastHeartbeat=now;
      Print("HEARTBEAT | v",EA_VERSION," open=",CountOpenPositions(),"/",maxPos,
            " dayNet=",DoubleToString(TodayNet(),2)," monthNet=",DoubleToString(MonthNet(),2)," symbols=",g_symbolCount,
            " lossStreakPause=",(lossBlock?"ON":"off")," equityHalt=",(g_haltAll?"ON":"off"));
   }
}
// Optional external ChatGPT indicator bridge. It must return ONLY a plain number.
// No API key is embedded and this EA does not call OpenAI directly.
double ChatGPTIndicatorBonus(string sym,int cmd,double rawScore)
{
   if(!InpUseChatGPTIndicator || StringLen(InpChatGPTIndicatorURL)<8) return(0.0);
   string url=InpChatGPTIndicatorURL;
   string sep=(StringFind(url,"?")>=0 ? "&" : "?");
   url+=sep+"symbol="+sym+"&direction="+(cmd==OP_BUY?"BUY":"SELL")+
        "&timeframe="+IntegerToString((int)InpSignalTF)+
        "&score="+DoubleToString(rawScore,2);
   char post[], result[];
   string responseHeaders="";
   ResetLastError();
   int status=WebRequest("GET",url,"","",InpChatGPTTimeoutMs,post,0,result,responseHeaders);
   if(status!=200)
   {
      int err=GetLastError();
      if(InpChatGPTLog) Print("CHATGPT_INDICATOR | status=",status," err=",err," symbol=",sym," bonus=0");
      BiteyCsvLogAction(sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1)),EA_VERSION,sym,
         "CHATGPT_INDICATOR","FALLBACK",0,(cmd==OP_BUY?"BUY":"SELL"),rawScore,
         "HTTP_STATUS="+IntegerToString(status)+";ERR="+IntegerToString(err)+";BONUS=0");
      return(0.0);
   }
   string body=CharArrayToString(result,0,WHOLE_ARRAY,CP_UTF8);
   StringTrimLeft(body); StringTrimRight(body);
   int bodyLen=StringLen(body);
   if(bodyLen<1 || bodyLen>24) return(0.0);
   // Strict decimal syntax only: reject JSON, prose, exponent notation and trailing junk.
   int digits=0, dots=0;
   for(int bi=0;bi<bodyLen;bi++)
   {
      int ch=StringGetCharacter(body,bi);
      if(ch>='0' && ch<='9') { digits++; continue; }
      if(ch=='.' && dots==0) { dots++; continue; }
      if((ch=='-' || ch=='+') && bi==0) continue;
      if(InpChatGPTLog) Print("CHATGPT_INDICATOR | invalid numeric body; bonus=0 symbol=",sym);
      return(0.0);
   }
   if(digits==0) return(0.0);
   double bonus=StringToDouble(body);
   double cap=MathAbs(InpChatGPTBonusMax);
   if(bonus>cap) bonus=cap;
   if(bonus< -cap) bonus= -cap;
   if(InpChatGPTLog) Print("CHATGPT_INDICATOR | symbol=",sym," direction=",
      (cmd==OP_BUY?"BUY":"SELL")," rawScore=",DoubleToString(rawScore,2),
      " bonus=",DoubleToString(bonus,2)," mode=RANKING_ONLY");
   BiteyCsvLogAction(sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1)),EA_VERSION,sym,
      "CHATGPT_INDICATOR","ADVISORY",0,(cmd==OP_BUY?"BUY":"SELL"),bonus,
      "RAW_SCORE="+DoubleToString(rawScore,2)+";RANKING_ONLY");
   return(bonus);
}
void Reject(string sym,string reason)
{
   if(RejectCsvDue(sym,reason))
   {
      string decisionId=sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1));
      BiteyCsvLogAction(decisionId,EA_VERSION,sym,"FILTER","REJECT",0,"ABSTAIN",0.0,reason);
   }
   if(InpLogRejects) Print("SYMBOL_REJECT | symbol=",sym," | reason=",reason);
}

// For callers that already wrote their own audit rows
void RejectQuiet(string sym,string reason)
{
   if(InpLogRejects) Print("SYMBOL_REJECT | symbol=",sym," | reason=",reason);
}
bool QuoteFresh(string sym)
{
   datetime qt=(datetime)MarketInfo(sym,MODE_TIME);
   if(qt<=0) return(false);
   int age=(int)(TimeCurrent()-qt);
   return(age>=-5 && age<=InpMaxQuoteAgeSec);
}
bool SessionOK(string sym)
{
   if(IsEquityToken(sym))
   {
      if(!InpTradeEquityTokens) return(false);
      datetime te=TimeCurrent();
      int dw=TimeDayOfWeek(te);
      if(dw==0 || dw==6) return(false);
      int me=TimeHour(te)*60+TimeMinute(te);
      return(me>=InpEquitySessionStartMin && me<InpEquitySessionEndMin);
   }
   if(!InpUseSessionFilter || IsCrypto(sym)) return(true);
   int h=TimeHour(TimeCurrent());
   if(InpSessionStartHour<InpSessionEndHour) return(h>=InpSessionStartHour && h<InpSessionEndHour);
   return(h>=InpSessionStartHour || h<InpSessionEndHour);
}
bool InRolloverWindow()
{
   datetime t=TimeCurrent();
   int m=TimeHour(t)*60+TimeMinute(t);
   if(InpRolloverStartMin>InpRolloverEndMin) return(m>=InpRolloverStartMin || m<InpRolloverEndMin);
   return(m>=InpRolloverStartMin && m<InpRolloverEndMin);
}
bool Prefilter(string sym,string &why)
{
   why="";
   if(!IsTradeAllowed()) { why="TERMINAL_TRADING_NOT_ALLOWED"; return(false); }
   if(InpBlockRollover && InRolloverWindow()) { why="ROLLOVER_WINDOW"; return(false); }
   if(FridayCutoff(sym)) { why="FRIDAY_CUTOFF"; return(false); }
   if(MarketInfo(sym,MODE_TRADEALLOWED)==0) { why="SYMBOL_TRADING_DISABLED"; return(false); }
   if(iBars(sym,InpSignalTF)<InpMinBars) { why="INSUFFICIENT_HISTORY"; return(false); }
   if(!QuoteFresh(sym)) { why="STALE_QUOTE"; return(false); }
   if(!SessionOK(sym)) { why="OUTSIDE_SESSION"; return(false); }
   if(HasPositionForKey(AssetKey(sym))) { why="POSITION_ALREADY_OPEN"; return(false); }
   if(InCooldown(sym)) { why="COOLDOWN"; return(false); }
   if(SymbolExpectancyBad(sym)) { why="NEGATIVE_EXPECTANCY_BAN"; return(false); }
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   if(bid<=0 || ask<bid || point<=0) { why="INVALID_QUOTE"; return(false); }
   if(InpMaxSpreadPoints>0 && (ask-bid)/point>InpMaxSpreadPoints) { why="SPREAD_POINTS_CAP"; return(false); }
   if(!EntryViable(sym,why)) return(false);
   return(true);
}
bool Analyze(string sym,int &cmd,double &score,string &why)
{
   cmd=-1; score=0.0; why="";
   g_tmpValidModels=0; g_tmpBuyVotes=0; g_tmpSellVotes=0;
   int tf=InpSignalTF;
   double c1=iClose(sym,tf,1), c2=iClose(sym,tf,2);
   double atr=iATR(sym,tf,InpATRPeriod,1);
   double adx=iADX(sym,tf,14,PRICE_CLOSE,MODE_MAIN,1);
   double rsi14=iRSI(sym,tf,14,PRICE_CLOSE,1);
   if(c1<=0 || c2<=0 || atr<=0 || adx<0 || rsi14<0) { why="INDICATOR_DATA_INVALID"; return(false); }
   if(adx<InpMinADX) { why="DEAD_MARKET_ADX"; return(false); }
   int modelDir[30]; double modelScore[30];
   string modelName[30]; string modelFamily[30];
   ArrayInitialize(modelDir,0); ArrayInitialize(modelScore,0.0);
   int fastEMA[5]={5,8,13,21,34}, slowEMA[5]={21,34,50,89,144};
   int macdFast[5]={5,8,10,12,15}, macdSlow[5]={13,17,21,26,30}, macdSig[5]={3,5,7,9,10};
   int donLen[5]={5,8,12,18,24}, rsiLen[5]={7,9,14,21,28};
   int bbLen[5]={10,14,20,24,30}, stochLen[5]={5,7,9,14,21};
   for(int k=0;k<5;k++)
   {
      int ix=k;
      double f=iMA(sym,tf,fastEMA[k],0,MODE_EMA,PRICE_CLOSE,1);
      double sl=iMA(sym,tf,slowEMA[k],0,MODE_EMA,PRICE_CLOSE,1);
      double fp=iMA(sym,tf,fastEMA[k],0,MODE_EMA,PRICE_CLOSE,2);
      if(f>0 && sl>0 && fp>0)
      { if(f>sl && c1>f && f>=fp) modelDir[ix]=1; else if(f<sl && c1<f && f<=fp) modelDir[ix]=-1; }
      modelScore[ix]=modelDir[ix]; modelName[ix]="EMA_"+IntegerToString(k+1); modelFamily[ix]="EMA_TREND";
      ix=5+k;
      double mm=iMACD(sym,tf,macdFast[k],macdSlow[k],macdSig[k],PRICE_CLOSE,MODE_MAIN,1);
      double ms=iMACD(sym,tf,macdFast[k],macdSlow[k],macdSig[k],PRICE_CLOSE,MODE_SIGNAL,1);
      double mprev=iMACD(sym,tf,macdFast[k],macdSlow[k],macdSig[k],PRICE_CLOSE,MODE_MAIN,2);
      if(mm>ms && mm>mprev) modelDir[ix]=1; else if(mm<ms && mm<mprev) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="MACD_"+IntegerToString(k+1); modelFamily[ix]="MACD_TREND";
      ix=10+k;
      int hi=iHighest(sym,tf,MODE_HIGH,donLen[k],2), lo=iLowest(sym,tf,MODE_LOW,donLen[k],2);
      double hh=(hi>=0?iHigh(sym,tf,hi):0.0), ll=(lo>=0?iLow(sym,tf,lo):0.0);
      if(hh>0 && c1>hh && c1>c2) modelDir[ix]=1; else if(ll>0 && c1<ll && c1<c2) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="DONCHIAN_"+IntegerToString(k+1); modelFamily[ix]="BREAKOUT";
      ix=15+k;
      double rv=iRSI(sym,tf,rsiLen[k],PRICE_CLOSE,1), rp=iRSI(sym,tf,rsiLen[k],PRICE_CLOSE,2);
      if(rv>52 && rv>rp && rv<75) modelDir[ix]=1; else if(rv<48 && rv<rp && rv>25) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="RSI_MOMENTUM_"+IntegerToString(k+1); modelFamily[ix]="RSI_MOMENTUM";
      ix=20+k;
      double up=iBands(sym,tf,bbLen[k],2.0,0,PRICE_CLOSE,MODE_UPPER,1);
      double lw=iBands(sym,tf,bbLen[k],2.0,0,PRICE_CLOSE,MODE_LOWER,1);
      double up2=iBands(sym,tf,bbLen[k],2.0,0,PRICE_CLOSE,MODE_UPPER,2);
      double lw2=iBands(sym,tf,bbLen[k],2.0,0,PRICE_CLOSE,MODE_LOWER,2);
      if(c2<lw2 && c1>lw && c1>c2) modelDir[ix]=1; else if(c2>up2 && c1<up && c1<c2) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="BOLLINGER_REENTRY_"+IntegerToString(k+1); modelFamily[ix]="MEAN_REVERSION";
      ix=25+k;
      double sm1=iStochastic(sym,tf,stochLen[k],3,3,MODE_SMA,0,MODE_MAIN,1);
      double ss1=iStochastic(sym,tf,stochLen[k],3,3,MODE_SMA,0,MODE_SIGNAL,1);
      double sm2=iStochastic(sym,tf,stochLen[k],3,3,MODE_SMA,0,MODE_MAIN,2);
      double ss2=iStochastic(sym,tf,stochLen[k],3,3,MODE_SMA,0,MODE_SIGNAL,2);
      if(sm2<=ss2 && sm1>ss1 && sm1<35) modelDir[ix]=1; else if(sm2>=ss2 && sm1<ss1 && sm1>65) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="STOCHASTIC_"+IntegerToString(k+1); modelFamily[ix]="MEAN_REVERSION";
   }
   string decisionId=sym+"_"+IntegerToString((int)iTime(sym,tf,1));
   g_tmpValidModels=30; g_tmpBuyVotes=0; g_tmpSellVotes=0;
   for(int countModel=0;countModel<30;countModel++)
   {
      if(modelDir[countModel]>0) g_tmpBuyVotes++;
      else if(modelDir[countModel]<0) g_tmpSellVotes++;
   }
   if(InpLogVotesMode==0) LogAllVotes(decisionId,sym,tf,modelName,modelFamily,modelDir,modelScore);
   int famBuy[6],famSell[6],famDir[6];
   ArrayInitialize(famBuy,0); ArrayInitialize(famSell,0); ArrayInitialize(famDir,0);
   for(int m=0;m<30;m++) { int fam=m/5; if(modelDir[m]>0) famBuy[fam]++; else if(modelDir[m]<0) famSell[fam]++; }
   for(int fidx=0;fidx<6;fidx++)
   {
      if(famBuy[fidx]>=InpAssemblyMinModelVotes && famBuy[fidx]>famSell[fidx]) famDir[fidx]=1;
      else if(famSell[fidx]>=InpAssemblyMinModelVotes && famSell[fidx]>famBuy[fidx]) famDir[fidx]=-1;
   }
   int dir=0, agree=0, opposing=0, modelVotes=0;
   int upTrend=0, downTrend=0;
   for(int t=0;t<4;t++) { if(famDir[t]>0) upTrend++; else if(famDir[t]<0) downTrend++; }
   if(adx>=InpTrendADX)
   {
      if(!InpAllowTrendRegime) { why="TREND_REGIME_DISABLED"; return(false); }
      g_tmpRegime=1;
      if(upTrend>=InpAssemblyMinFamilies && downTrend<=1) dir=1;
      else if(downTrend>=InpAssemblyMinFamilies && upTrend<=1) dir=-1;
      else
      {
         why="ASSEMBLY2_ABSTAIN_TREND_NO_CONSENSUS";
         BiteyCsvLogTradeAssembly(decisionId,EA_VERSION,sym,tf,"ABSTAIN",0,0,upTrend+downTrend,0,0,0,0,false,why);
         return(false);
      }
      agree=(dir>0?upTrend:downTrend); opposing=(dir>0?downTrend:upTrend);
   }
   else
   {
      if(!InpAllowRangeRegime) { why="RANGE_REGIME_DISABLED"; return(false); }
      g_tmpRegime=2;
      if(famDir[4]!=0 && famDir[4]==famDir[5] &&
         ((famDir[4]>0 && rsi14<=45.0) || (famDir[4]<0 && rsi14>=55.0))) dir=famDir[4];
      if(dir==0)
      {
         why="ASSEMBLY2_ABSTAIN_RANGE_NO_CONSENSUS";
         BiteyCsvLogTradeAssembly(decisionId,EA_VERSION,sym,tf,"ABSTAIN",0,0,
            (famDir[4]!=0 ? 1 : 0)+(famDir[5]!=0 ? 1 : 0),0,0,0,0,false,why);
         return(false);
      }
      agree=2; opposing=0;
   }
   if(InpUseHTFFilter)
   {
      double hc=iClose(sym,InpHTF,1), he=iMA(sym,InpHTF,50,0,MODE_EMA,PRICE_CLOSE,1);
      if(hc<=0 || he<=0) { why="HTF_DATA_UNAVAILABLE"; return(false); }
      if((dir>0 && hc<=he) || (dir<0 && hc>=he))
      {
         why="HTF_BIAS_AGAINST";
         BiteyCsvLogTradeAssembly(decisionId,EA_VERSION,sym,tf,"ABSTAIN",0,0,agree,opposing,0,0,0,false,why);
         return(false);
      }
   }
   double sb9=MarketInfo(sym,MODE_BID), sa9=MarketInfo(sym,MODE_ASK), sp9=MarketInfo(sym,MODE_POINT);
   double spr9=(sa9>sb9 ? sa9-sb9 : 0.0);
   double sbk9=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*sp9;
   double stopRef=EntryStopDist(sym,atr,spr9,sbk9), costR=EntryCostR(sym,stopRef);
   score=10.0*agree+MathMin(adx,40.0)/4.0-30.0*MathMin(costR,2.0)-2.0*opposing;
   cmd=(dir>0?OP_BUY:OP_SELL);
   modelVotes=(dir>0?famBuy[0]+famBuy[1]+famBuy[2]+famBuy[3]:famSell[0]+famSell[1]+famSell[2]+famSell[3]);
   if(InpLogVotesMode==1) LogAllVotes(decisionId,sym,tf,modelName,modelFamily,modelDir,modelScore);
   BiteyCsvLogTradeAssembly(decisionId,EA_VERSION,sym,tf,(dir>0?"BUY":"SELL"),score,
      MathMin(1.0,(double)agree/4.0),modelVotes,
      (dir>0?famSell[0]+famSell[1]+famSell[2]+famSell[3]:famBuy[0]+famBuy[1]+famBuy[2]+famBuy[3]),
      0,0,0,true,"ASSEMBLY2_CONSENSUS");
   BiteyCsvLogAction(decisionId,EA_VERSION,sym,"ASSEMBLY2","VOTE_APPROVED",0,
      (dir>0?"BUY":"SELL"),score,"ASSEMBLY2_CONSENSUS");
   return(true);
}
double EntryCostR(string sym,double stopDist)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
   if(tv<=0 || ts<=0 || stopDist<=0 || bid<=0 || ask<bid) return(99.0);
   double stopPerLot=(stopDist/ts)*tv;
   double costPerLot=((ask-bid)/ts)*tv+CommissionPerLot(sym);
   if(stopPerLot<=0) return(99.0);
   return(costPerLot/stopPerLot);
}
bool OpenTrade(string sym,int cmd,double score,int regime,int buyVotes,int sellVotes)
{
   datetime decisionBar=iTime(sym,InpSignalTF,1);
   string decisionId=sym+"_"+IntegerToString((int)decisionBar);
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(bid<=0 || ask<bid || point<=0 || atr<=0) { Reject(sym,"ENTRY_DATA_INVALID"); return(false); }
   if(!QuoteFresh(sym)) { Reject(sym,"STALE_QUOTE_AT_ENTRY"); return(false); }
   double spreadPrice=ask-bid;
   double brokerMin=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*point;
   double stopDist=EntryStopDist(sym,atr,spreadPrice,brokerMin);
   double targetDist=MathMax(stopDist*RewardRiskFor(regime),spreadPrice+brokerMin);
   if(spreadPrice>stopDist*InpMaxSpreadPctOfStop/100.0)
   {
      BiteyCsvLogAction(decisionId,EA_VERSION,sym,"EXECUTION","ORDER_REJECTED",0,(cmd==OP_BUY?"BUY":"SELL"),score,"SPREAD_VS_STOP_REJECT");
      if(RejectLogDue(sym)) Print("SPREAD_VS_STOP_REJECT | symbol=",sym," spread=",DoubleToString(spreadPrice,digits),
            " stop=",DoubleToString(stopDist,digits)," maxPct=",DoubleToString(InpMaxSpreadPctOfStop,1));
      return(false);
   }
   double entry=(cmd==OP_BUY?ask:bid);
   int sendType=cmd;
   if(InpUseLimitEntry)
   {
      double lim=LimitEntryPrice(sym,cmd,bid,ask,point,digits);
      if(lim>0.0) { entry=lim; sendType=(cmd==OP_BUY?OP_BUYLIMIT:OP_SELLLIMIT); }
   }
   double sl=NormalizeDouble(cmd==OP_BUY?entry-stopDist:entry+stopDist,digits);
   double tp=NormalizeDouble(cmd==OP_BUY?entry+targetDist:entry-targetDist,digits);
   stopDist=MathAbs(entry-sl);
   bool ok=false;
   if(cmd==OP_BUY) ok=(sl>0 && tp>0 && sl<bid-brokerMin*0.5 && tp>bid+brokerMin*0.5);
   else            ok=(sl>ask+brokerMin*0.5 && tp>0 && tp<ask-brokerMin*0.5);
   if(!ok) { BiteyCsvLogAction(decisionId,EA_VERSION,sym,"EXECUTION","ORDER_REJECTED",0,(cmd==OP_BUY?"BUY":"SELL"),score,"STOP_PREFLIGHT_REJECT"); Print("STOP_PREFLIGHT_REJECT | symbol=",sym," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits)); return(false); }
   double costR=EntryCostR(sym,stopDist);
   if(costR>InpMaxCostR)
   {
      BiteyCsvLogAction(decisionId,EA_VERSION,sym,"EXECUTION","ORDER_REJECTED",0,(cmd==OP_BUY?"BUY":"SELL"),score,"COST_REJECT costR="+DoubleToString(costR,3));
      if(RejectLogDue(sym)) Print("COST_REJECT | symbol=",sym," costR=",DoubleToString(costR,3)," max=",DoubleToString(InpMaxCostR,3));
      return(false);
   }
   double perTrade=RiskCapital()*InpRiskPctPerTrade/100.0;
   double lots=LotsForRisk(sym,stopDist,perTrade);
   if(lots<=0) { BiteyCsvLogAction(decisionId,EA_VERSION,sym,"EXECUTION","ORDER_REJECTED",0,(cmd==OP_BUY?"BUY":"SELL"),score,"MIN_LOT_EXCEEDS_BUDGET_OR_CAP"); Print("RISK_REJECT | symbol=",sym," reason=MIN_LOT_EXCEEDS_BUDGET_OR_CAP budget=",DoubleToString(budget,2)); return(false); }
   double risk=EstimateRisk(sym,lots,stopDist);
   if(!InpEnableTrading)
   {
      BiteyCsvLogAction(decisionId,EA_VERSION,sym,"EXECUTION","DRY_RUN_CANDIDATE",0,
         (cmd==OP_BUY?"BUY":"SELL"),score,
         "TRADING_DISABLED lots="+DoubleToString(lots,2)+" risk="+DoubleToString(risk,2)+
         " costR="+DoubleToString(costR,3)+" sl="+DoubleToString(sl,digits)+" tp="+DoubleToString(tp,digits));
      Print("DRY_RUN_CANDIDATE | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL")," score=",DoubleToString(score,1),
            " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," costR=",DoubleToString(costR,3),
            " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      return(false);
   }
   if(IsTradeContextBusy()) { BiteyCsvLogAction(decisionId,EA_VERSION,sym,"EXECUTION","ORDER_REJECTED",0,(cmd==OP_BUY?"BUY":"SELL"),score,"TRADE_CONTEXT_BUSY"); Reject(sym,"TRADE_CONTEXT_BUSY"); return(false); }
   if(InpRequireCsvAudit)
   {
      // Audit-first: write the intent row; if the CSV cannot be written, do not send the order.
      BiteyCsvLogAction(decisionId,EA_VERSION,sym,"EXECUTION","ORDER_SUBMIT",0,
         (cmd==OP_BUY?"BUY":"SELL"),score,"PRE_ORDER_AUDIT_CHECK");
      if(g_csvFailed) { Print("CSV_AUDIT_BLOCK | symbol=",sym," | audit CSV not writable, order not sent"); return(false); }
   }
   ResetLastError();
   int ticket=OrderSend(sym,sendType,lots,entry,InpSlippagePoints,sl,tp,"BE"+EA_VERSION+(regime==1?" T":" R"),InpMagic,0,clrNONE);
   if(ticket<0)
   {
      int err=GetLastError();
      BiteyCsvLogAction(decisionId,EA_VERSION,sym,"EXECUTION","ORDER_FAILED",0,(cmd==OP_BUY?"BUY":"SELL"),score,
          "OrderSend_error="+IntegerToString(err)+" lots="+DoubleToString(lots,2)+
          " risk="+DoubleToString(risk,2)+" entry="+DoubleToString(entry,digits)+
          " sl="+DoubleToString(sl,digits)+" tp="+DoubleToString(tp,digits));
      Print("ORDER_REJECTED | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL")," error=",err,
            " lots=",DoubleToString(lots,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      return(false);
   }
   Print("ORDER_ACCEPTED | ticket=",ticket," symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
         " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," costR=",DoubleToString(costR,3),
         " score=",DoubleToString(score,1)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
   double filledEntry=entry;
   if(OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)) filledEntry=OrderOpenPrice();
   TrackOpen(ticket,MathAbs(filledEntry-sl));
   double spreadCostPerLot=0.0, commissionCostPerLot=0.0;
   EstCostPerLot(sym,spreadCostPerLot,commissionCostPerLot);
   GlobalVariableSet(GvKey("SPREADEST",ticket),MathMax(0.0,spreadCostPerLot)*lots);
   GlobalVariableSet(GvKey("COMMEST",ticket),MathMax(0.0,commissionCostPerLot)*lots);
   GlobalVariableSet(GvKey("DID",ticket),(double)decisionBar);
   GlobalVariableSet(GvKey("REQPX",ticket),entry);
   GlobalVariableSet(GvKey("BUYV",ticket),(double)buyVotes);
   GlobalVariableSet(GvKey("SELLV",ticket),(double)sellVotes);
   GlobalVariableSet(GvKey("MAGIC",ticket),(double)InpMagic);
   BiteyCsvLogTradeOpened(decisionId,EA_VERSION,ticket,sym,(cmd==OP_BUY?"BUY":"SELL"),
      lots,filledEntry,sl,tp,InpReferenceCapitalUSD,risk,(IsTesting()?"TESTER":"TERMINAL"),"ORDER_ACCEPTED");
   BiteyCsvLogAction(decisionId,EA_VERSION,sym,"EXECUTION","ORDER_OPENED",ticket,
      (cmd==OP_BUY?"BUY":"SELL"),score,(sendType==cmd?"ORDER_ACCEPTED":"LIMIT_ORDER_PLACED"));
   return(true);
}
bool CloseTicket(int ticket,string reason)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES) || OrderCloseTime()>0) return(false);
   string sym=OrderSymbol();
   int type=OrderType();
   double lots=OrderLots();
   double px=(type==OP_BUY?MarketInfo(sym,MODE_BID):MarketInfo(sym,MODE_ASK));
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   if(px<=0) return(false);
   double net=OrderProfit()+OrderSwap()+OrderCommission();
   ResetLastError();
   bool ok=OrderClose(ticket,lots,NormalizeDouble(px,digits),InpSlippagePoints,clrNONE);
   if(ok) RememberCloseReason(ticket,reason);
   Print("CLOSE | reason=",reason," ticket=",ticket," symbol=",sym," net=",DoubleToString(net,2)," ok=",(ok?"true":"false"),
         " error=",(ok?0:GetLastError()));
   return(ok);
}
void ManageExits()
{
   bool rollover=(InpFlatBeforeRollover && InRolloverWindow());
   for(int pos=OrdersTotal()-1;pos>=0;pos--)
   {
      if(!OrderSelect(pos,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      int ticket=OrderTicket();
      string sym=OrderSymbol();
      double point=MarketInfo(sym,MODE_POINT);
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      if(point<=0 || bid<=0 || ask<=0) continue;
      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      double entry=OrderOpenPrice(), oldSL=OrderStopLoss(), oldTP=OrderTakeProfit(), lots=OrderLots();
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
      bool rangeTrade=(StringFind(OrderComment()," R")>=0);   // order comment is tagged " R" (range) or " T" (trend) at entry
      UpdateExcursion(ticket,type,entry,oldSL,bid,ask);
      if(rollover) { CloseTicket(ticket,"ROLLOVER_FLAT"); continue; }   // avoid overnight swap
      if(FridayCutoff(sym)) { CloseTicket(ticket,"FRIDAY_FLAT"); continue; }   // avoid overnight swap
      if(InpMaxHoldBars>0)
      {
         int barsOpen=iBarShift(sym,InpSignalTF,OrderOpenTime(),false);
         if(barsOpen>=InpMaxHoldBars) { CloseTicket(ticket,"TIME_EXIT"); continue; }
      }
      if(atr<=0) continue;
      if(InpEnableConfirmedReversalExit && InpReversalFastMAPeriod>0 &&
         InpReversalSlowMAPeriod>InpReversalFastMAPeriod)
      {
         double fast1=iMA(sym,InpSignalTF,InpReversalFastMAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
         double fast2=iMA(sym,InpSignalTF,InpReversalFastMAPeriod,0,MODE_EMA,PRICE_CLOSE,2);
         double slow1=iMA(sym,InpSignalTF,InpReversalSlowMAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
         double slow2=iMA(sym,InpSignalTF,InpReversalSlowMAPeriod,0,MODE_EMA,PRICE_CLOSE,2);
         double reversalRisk=EstimateRisk(sym,lots,atr*InpStopATR);
         double reversalFloor=(reversalRisk<1.0e11 ? MathMax(0.0,InpReversalExitMinR*reversalRisk) : 0.0);
         bool bearishCross=(fast2>=slow2 && fast1<slow1);
         bool bullishCross=(fast2<=slow2 && fast1>slow1);
         if(((type==OP_BUY && bearishCross) || (type==OP_SELL && bullishCross)) && net>=reversalFloor)
         {
            if(CloseTicket(ticket,"PROFITABLE_CONFIRMED_REVERSAL")) continue;
         }
      }
      if(InpNetTargetR>0.0)
      {
         double refRisk=EstimateRisk(sym,lots,atr*InpStopATR);   // reference R, independent of SL trailing
         if(refRisk<1.0e11 && net>=InpNetTargetR*refRisk) { CloseTicket(ticket,"NET_TARGET_R"); continue; }
      }
      if(InpUseMeanExit && rangeTrade)
      {
         double mid=iMA(sym,InpSignalTF,InpExitMAPeriod,0,MODE_SMA,PRICE_CLOSE,0);
         if(mid>0.0)
         {
            double bandW=InpExitBandATR*atr;
            bool atMean=(type==OP_BUY ? bid>=mid : ask<=mid);
            bool atFar =(type==OP_BUY ? bid>=mid+bandW : ask<=mid-bandW);
            double refR=EstimateRisk(sym,lots,atr*InpStopATR);
            if(atFar && net>0.0) { CloseTicket(ticket,"OPPOSITE_BAND"); continue; }
            if(atMean && refR<1.0e11 && net>=InpMeanExitMinR*refR) { CloseTicket(ticket,"MEAN_TARGET"); continue; }
         }
      }
      if(!InpEnableAdaptiveExits) continue;
      double minDist=(MarketInfo(sym,MODE_STOPLEVEL)+MarketInfo(sym,MODE_FREEZELEVEL)+2.0)*point;
      double price=(type==OP_BUY?bid:ask);
      double favorable=(type==OP_BUY?price-entry:entry-price);
      double newSL=oldSL, newTP=oldTP;
      bool slUp=false, tpUp=false;
      string exitWhy="";
      double tvv=MarketInfo(sym,MODE_TICKVALUE), tss=MarketInfo(sym,MODE_TICKSIZE);
      double commPrice=(tvv>0 && tss>0 ? CommissionPerLot(sym)*tss/tvv : 0.0);
      if(InpBreakEvenTriggerATR>0 && favorable>=atr*InpBreakEvenTriggerATR)
      {
         double lockDist=atr*InpBreakEvenLockATR+commPrice;
         double be=(type==OP_BUY?entry+lockDist:entry-lockDist);
         if(type==OP_BUY  && (newSL<=0 || be>newSL) && be<bid-minDist) { newSL=be; exitWhy+="BREAKEVEN;"; }
         if(type==OP_SELL && (newSL<=0 || be<newSL) && be>ask+minDist) { newSL=be; exitWhy+="BREAKEVEN;"; }
      }
      if(InpTrailStartATR>0 && InpTrailDistanceATR>0 && favorable>=atr*InpTrailStartATR)
      {
         double trailDistanceATR=MathMax(InpTrailMinDistanceATR,
                                         InpTrailDistanceATR-MathMax(0.0,favorable/atr-InpTrailStartATR)*InpTrailTightenPerATR);
          double tr=(type==OP_BUY?bid-atr*trailDistanceATR:ask+atr*trailDistanceATR);
         if(type==OP_BUY  && tr>newSL+atr*InpTrailStepATR && tr<bid-minDist) { newSL=tr; exitWhy+="TRAIL;"; }
         if(type==OP_SELL && (newSL<=0 || tr<newSL-atr*InpTrailStepATR) && tr>ask+minDist) { newSL=tr; exitWhy+="TRAIL;"; }
      }
      double lockR0=(GlobalVariableCheck(GvKey("R0",ticket))?GlobalVariableGet(GvKey("R0",ticket)):0.0);
      double lockRef=EstimateRisk(sym,lots,(lockR0>0.0?lockR0:atr*InpStopATR));   // initial risk in money
      double lockTrigUSD=InpProfitLockTriggerR*lockRef;
      double lockTargetUSD=InpProfitLockTargetR*lockRef;
      double lockStepUSD=InpProfitLockStepR*lockRef;
      if(InpEnableNetProfitLock && lockRef<1.0e11 && InpProfitLockTriggerR>0.0 && InpProfitLockTargetR>0.0 &&
         lockTargetUSD<lockTrigUSD && net>=lockTrigUSD)
      {
         double lockTickValue=MarketInfo(sym,MODE_TICKVALUE);
         double lockTickSize=MarketInfo(sym,MODE_TICKSIZE);
         double lockMoneyPerPrice=(lockTickValue>0.0 && lockTickSize>0.0 ? lots*lockTickValue/lockTickSize : 0.0);
         if(lockMoneyPerPrice>0.0 && lots>0.0)
         {
            double postedCommission=MathAbs(OrderCommission());
            double configuredRoundTurn=CommissionPerLot(sym)*lots;
            double commissionEstimate=MathMax(postedCommission,configuredRoundTurn);
            double requiredPricePnl=lockTargetUSD-OrderSwap()+commissionEstimate;
            double lockMove=MathMax(0.0,requiredPricePnl/lockMoneyPerPrice);
            double lockSL=NormalizeDouble(type==OP_BUY?entry+lockMove:entry-lockMove,digits);
            bool improves=(type==OP_BUY ? (newSL<=0.0 || lockSL>newSL+point*0.5)
                                        : (newSL<=0.0 || lockSL<newSL-point*0.5));
            bool brokerValid=(type==OP_BUY ? lockSL<bid-minDist : lockSL>ask+minDist);
            double currentLockNet=-1.0e100;
            if(oldSL>0.0)
            {
               double oldMove=(type==OP_BUY?oldSL-entry:entry-oldSL);
               currentLockNet=oldMove*lockMoneyPerPrice+OrderSwap()-commissionEstimate;
            }
            double candidateLockNet=lockMove*lockMoneyPerPrice+OrderSwap()-commissionEstimate;
            bool stepReached=(oldSL<=0.0 ||
                              currentLockNet<lockTargetUSD-lockStepUSD ||
                              candidateLockNet>=currentLockNet+lockStepUSD);
            if(improves && brokerValid && stepReached)
            {
               newSL=lockSL;
               exitWhy+="NET_PROFIT_LOCK;";
               Print("NET_PROFIT_LOCK | ticket=",ticket," symbol=",sym,
                     " netUSD=",DoubleToString(net,2),
                     " targetNetUSD=",DoubleToString(lockTargetUSD,2),
                     " commissionEstimate=",DoubleToString(commissionEstimate,2),
                     " swap=",DoubleToString(OrderSwap(),2),
                     " SLcandidate=",DoubleToString(lockSL,digits));
            }
         }
      }
      newSL=(newSL>0?NormalizeDouble(newSL,digits):0);
      if(type==OP_BUY)  slUp=(newSL>0 && (oldSL<=0 || newSL>oldSL+point*0.5));
      else              slUp=(newSL>0 && (oldSL<=0 || newSL<oldSL-point*0.5));
      double adx=iADX(sym,InpSignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
      if(InpEnableTPExpand && oldTP>0 && favorable>=atr*InpTPExpandTriggerATR && adx>=InpTPExpandADXMin)
      {
         double remainingToTP=(type==OP_BUY?oldTP-bid:ask-oldTP);
         if(remainingToTP<=atr*InpTPExpandBufferATR)
         {
            double curDist=MathAbs(oldTP-entry);
            double want=MathMin(atr*InpTPMaxDistanceATR,MathMax(curDist,favorable+atr*InpTPExpandBufferATR));
            double prop=NormalizeDouble(type==OP_BUY?entry+want:entry-want,digits);
            if(type==OP_BUY  && prop>oldTP+atr*InpTPExpandStepATR && prop>ask+minDist) { newTP=prop; tpUp=true; exitWhy+="TP_EXPAND;"; }
            if(type==OP_SELL && prop<oldTP-atr*InpTPExpandStepATR && prop<bid-minDist) { newTP=prop; tpUp=true; exitWhy+="TP_EXPAND;"; }
         }
      }
      if(!slUp && !tpUp) continue;
      double fSL=(slUp?newSL:oldSL), fTP=(tpUp?newTP:oldTP);
      ResetLastError();
      if(OrderModify(ticket,entry,fSL,fTP,0,clrNONE))
      {
         string exitDecisionId="ticket_"+IntegerToString(ticket);
         string exitWhyLog=(exitWhy==""?"SL_TP_UPDATE":exitWhy);
         if(GlobalVariableCheck(GvKey("DID",ticket)))
            exitDecisionId=sym+"_"+IntegerToString((int)GlobalVariableGet(GvKey("DID",ticket)));
         BiteyCsvLogAdaptiveExit(exitDecisionId,EA_VERSION,ticket,sym,oldSL,fSL,oldTP,fTP,
            OrderProfit()+OrderCommission()+OrderSwap(),exitWhyLog);
         BiteyCsvLogAction(exitDecisionId,EA_VERSION,sym,"RISK_MANAGEMENT","SLTP_MODIFIED",ticket,
            (OrderType()==OP_BUY?"BUY":"SELL"),OrderProfit()+OrderCommission()+OrderSwap(),exitWhyLog);
         Print("ADAPTIVE_MODIFY | ticket=",ticket," symbol=",sym,
               " SL ",DoubleToString(oldSL,digits),"->",DoubleToString(fSL,digits),
               " TP ",DoubleToString(oldTP,digits),"->",DoubleToString(fTP,digits));
      }
      else
         Print("ADAPTIVE_MODIFY_FAILED | ticket=",ticket," symbol=",sym," error=",GetLastError());
   }
}
bool HasPositionForKey(string key)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || !IsLiveOrderType(OrderType())) continue;
      if(AssetKey(OrderSymbol())==key) return(true);
   }
   return(false);
}
int CountOpenPositions()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==InpMagic && IsLiveOrderType(OrderType())) n++;
   }
   return(n);
}
double CurrentOpenRisk()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || !IsLiveOrderType(OrderType())) continue;
      if(OrderStopLoss()<=0) return(RiskCapital());      // unknown risk fails closed
      double d=((OrderType()==OP_BUY || OrderType()==OP_BUYLIMIT)?OrderOpenPrice()-OrderStopLoss():OrderStopLoss()-OrderOpenPrice());
      if(d>0) total+=EstimateRisk(OrderSymbol(),OrderLots(),d);
   }
   return(total);
}
double TodayNet()
{
   return(PeriodNet(StrToTime(TimeToString(TimeCurrent(),TIME_DATE))));
}
double MonthNet()
{
   datetime t=TimeCurrent();
   return(PeriodNet(StrToTime(StringFormat("%04d.%02d.01",TimeYear(t),TimeMonth(t)))));
}
double PeriodNet(datetime ds)
{
   double net=0.0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      if(OrderCloseTime()>=ds) net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return(net);
}
bool InCooldown(string sym)
{
   datetime latest=0; double latestNet=0.0;
   int seen=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<120;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber()!=InpMagic || OrderSymbol()!=sym || OrderType()>OP_SELL) continue;
      if(OrderCloseTime()>latest)
      {
         latest=OrderCloseTime();
         latestNet=OrderProfit()+OrderSwap()+OrderCommission();
      }
   }
   if(latest<=0) return(false);
   int bars=(latestNet<0.0?InpCooldownBars:InpReentryBars);
   if(bars<=0) return(false);
   return((TimeCurrent()-latest)<bars*PeriodSeconds(InpSignalTF));
}
bool SymbolExpectancyBad(string sym)
{
   if(InpExpectancyWindow<=0 || InpExpectancyMinTrades<=0) return(false);
   int cnt=0, seen=0;
   double sum=0.0;
   datetime last=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<500 && cnt<InpExpectancyWindow;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber()!=InpMagic || OrderSymbol()!=sym || OrderType()>OP_SELL) continue;
      cnt++;
      sum+=OrderProfit()+OrderSwap()+OrderCommission();
      if(OrderCloseTime()>last) last=OrderCloseTime();
   }
   if(cnt<InpExpectancyMinTrades || sum>=0.0) return(false);
   return((TimeCurrent()-last)<InpExpectancyBanHours*3600);
}
double EstimateRisk(string sym,double lots,double stopDist)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   if(tv<=0 || ts<=0 || lots<=0 || stopDist<=0) return(1.0e12);
   return(((stopDist/ts)*tv+CommissionPerLot(sym))*lots);
}
int LotDigits(double step)
{
   if(step>=1.0) return(0);
   if(step>=0.1) return(1);
   if(step>=0.01) return(2);
   return(3);
}
double LotsForRisk(string sym,double stopDist,double riskMoney)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   double minLot=MarketInfo(sym,MODE_MINLOT), maxLot=MarketInfo(sym,MODE_MAXLOT), step=MarketInfo(sym,MODE_LOTSTEP);
   if(riskMoney<=0 || tv<=0 || ts<=0 || stopDist<=0 || minLot<=0 || maxLot<minLot || step<=0) return(0.0);
   double lossPerLot=(stopDist/ts)*tv+CommissionPerLot(sym);
   if(lossPerLot<=0) return(0.0);
   double lots=MathFloor(riskMoney/lossPerLot/step+1e-9)*step;
   lots=MathMin(lots,maxLot);
   lots=MathMin(lots,LotCap(sym));
   lots=MathFloor(lots/step+1e-9)*step;
   lots=NormalizeDouble(lots,LotDigits(step));
   if(lots<minLot) return(0.0);
   if(EstimateRisk(sym,lots,stopDist)>riskMoney+0.02) return(0.0);
   return(lots);
}
int SymIndex(string sym)
{
   for(int i=0;i<g_symbolCount;i++)
      if(g_symbols[i]==sym) return(i);
   return(-1);
}
bool RejectLogDue(string sym)
{
   if(InpRejectLogMinutes<=0) return(true);
   int i=SymIndex(sym);
   if(i<0) return(true);
   datetime now=TimeCurrent();
   if(g_lastRejectLog[i]!=0 && now-g_lastRejectLog[i]<InpRejectLogMinutes*60) return(false);
   g_lastRejectLog[i]=now;
   return(true);
}
string GvKey(string tag,int ticket)
{
   return("BE"+IntegerToString(InpMagic)+"_"+tag+"_"+IntegerToString(ticket));
}
void TrackOpen(int ticket,double r0)
{
   GlobalVariableSet(GvKey("R0",ticket),r0);
   GlobalVariableSet(GvKey("MFE",ticket),0.0);
   GlobalVariableSet(GvKey("MAE",ticket),0.0);
}
void UpdateExcursion(int ticket,int type,double entry,double sl,double bid,double ask)
{
   string kr=GvKey("R0",ticket);
   if(!GlobalVariableCheck(kr))
   {
      double r0=(sl>0?MathAbs(entry-sl):0.0);
      GlobalVariableSet(kr,r0);
      GlobalVariableSet(GvKey("MFE",ticket),0.0);
      GlobalVariableSet(GvKey("MAE",ticket),0.0);
   }
   double px=(type==OP_BUY?bid:ask);
   double move=(type==OP_BUY?px-entry:entry-px);
   string kf=GvKey("MFE",ticket), ka=GvKey("MAE",ticket);
   double mfe=GlobalVariableGet(kf), mae=GlobalVariableGet(ka);
   if(move>mfe)  GlobalVariableSet(kf,move);
   if(-move>mae) GlobalVariableSet(ka,-move);
}
bool BiteyClosedTicketAlreadyLogged(int ticket,string sym,datetime openedAt)
{
   // Strategy Tester: ticket numbers restart on every run while the CSV persists, so a ticket-based
   // duplicate check would silently drop rows of later runs. The per-run global-variable claim is enough there.
   if(IsTesting()) return(false);
   string fn="Bitey_ClosedTrades_v1_8_0_2.csv";
   int h=FileOpen(fn,FILE_READ|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) return(false);
   string wantedTicket=IntegerToString(ticket);
   string wantedOpen=TimeToString(openedAt,TIME_DATE|TIME_SECONDS);
   bool found=false;
   while(!FileIsEnding(h))
   {
      string fields[23];
      for(int k=0;k<23;k++)
      {
         fields[k]="";
         if(FileIsEnding(h)) break;
         fields[k]=FileReadString(h);
      }
      // same ticket AND symbol AND open time (tickets can repeat across accounts sharing this folder)
      if(fields[3]==wantedTicket && fields[5]==sym && fields[8]==wantedOpen) { found=true; break; }
   }
   FileClose(h);
   return(found);
}

bool WriteTradeRow(int ticket)
{
   if(BiteyClosedTicketAlreadyLogged(ticket,OrderSymbol(),OrderOpenTime())) return(true);
   string sym=OrderSymbol();
   int type=OrderType();
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   bool hasTracking=GlobalVariableCheck(GvKey("R0",ticket));
   string closedVersion=(hasTracking?EA_VERSION:"LEGACY_UNTRACKED");
   double r0=(hasTracking?GlobalVariableGet(GvKey("R0",ticket)):0.0);
   double mfe=GlobalVariableGet(GvKey("MFE",ticket));
   double mae=GlobalVariableGet(GvKey("MAE",ticket));
   double mfeR=(r0>0?mfe/r0:0.0), maeR=(r0>0?mae/r0:0.0);
   double gross=OrderProfit(), comm=OrderCommission(), swp=OrderSwap();
   // Entry slippage in points, positive = adverse (filled worse than requested); -999999 = unknown (written as NA)
   double entrySlippagePoints=-999999.0;
   string requestedPriceKey=GvKey("REQPX",ticket);
   double symbolPoint=MarketInfo(sym,MODE_POINT);
   if(symbolPoint>0.0 && GlobalVariableCheck(requestedPriceKey))
   {
      double reqPx=GlobalVariableGet(requestedPriceKey);
      entrySlippagePoints=(type==OP_BUY?OrderOpenPrice()-reqPx:reqPx-OrderOpenPrice())/symbolPoint;
   }
   string closeWhy=LookupCloseReason(ticket,OrderComment());
   int durMin=(int)((OrderCloseTime()-OrderOpenTime())/60);
   string mfeLogKey=GvKey("MFELOG",ticket);
   if(!GlobalVariableCheck(mfeLogKey))
   {
   string fn="Bitey_Ens_TradeAudit_"+IntegerToString(InpMagic)+".csv";
   int h=FileOpen(fn,FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) { Print("CSV_OPEN_FAILED | file=",fn," error=",GetLastError()); return(false); }
   if(FileSize(h)==0)
      FileWrite(h,"ticket","symbol","side","open_time","close_time","duration_min","lots","open_price","close_price",
                "initial_risk_price","mfe_price","mae_price","mfe_R","mae_R","gross","commission_actual","swap_actual","net_after_commission_swap","comment","estimated_entry_spread_cost","estimated_entry_commission");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,ticket,sym,(type==OP_BUY?"BUY":"SELL"),
             TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),
             durMin,DoubleToString(OrderLots(),2),DoubleToString(OrderOpenPrice(),digits),DoubleToString(OrderClosePrice(),digits),
             DoubleToString(r0,digits),DoubleToString(mfe,digits),DoubleToString(mae,digits),
             DoubleToString(mfeR,2),DoubleToString(maeR,2),
             DoubleToString(gross,2),DoubleToString(comm,2),DoubleToString(swp,2),DoubleToString(gross+comm+swp,2),
             OrderComment());
   FileClose(h);
   GlobalVariableSet(mfeLogKey,1.0);
   }
   string closedDecisionId="ticket_"+IntegerToString(ticket);
   if(GlobalVariableCheck(GvKey("DID",ticket)))
      closedDecisionId=sym+"_"+IntegerToString((int)GlobalVariableGet(GvKey("DID",ticket)));
   if(!BiteyCsvLogTradeClosed(closedDecisionId,closedVersion,ticket,sym,
      (type==OP_BUY?"BUY":"SELL"),OrderLots(),OrderOpenTime(),OrderCloseTime(),
      OrderOpenPrice(),OrderClosePrice(),gross,comm,swp,entrySlippagePoints,closeWhy)) return(false);
   BiteyCsvLogAction(closedDecisionId,EA_VERSION,sym,"EXECUTION","ORDER_CLOSED",ticket,
      (type==OP_BUY?"BUY":"SELL"),gross+comm+swp,closeWhy);
   return(true);
}
void LogClosedTrades()
{
   if(!InpLogTradesCSV) return;
   datetime now=TimeCurrent();
   if(g_lastCsvScan!=0 && now-g_lastCsvScan<20) return;
   g_lastCsvScan=now;
   int historyTotal=OrdersHistoryTotal();
   int attempts=0;
   for(int i=historyTotal-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      int ticket=OrderTicket();
      string kd=GvKey("LOG",ticket);
      if(GlobalVariableCheck(kd)) continue;
      if(!InpLogLegacyClosed && !GlobalVariableCheck(GvKey("R0",ticket))) continue;   // closed by a version that never tracked it
      if(attempts>=InpMaxClosedRowsPerScan) break;                                     // the rest is caught up on the next scan
      attempts++;
      // Persist the claim only after the audit row is confirmed. If the terminal stops
      // during a write, the next scan retries; CSV ticket dedupe prevents duplicates.
      if(WriteTradeRow(ticket)) GlobalVariableSet(kd,1.0);
   }
}
void WriteAssetNetSummary()
{
   if(!InpLogAssetSummaryCSV) return;
   datetime now=TimeCurrent();
   if(g_lastNetSummaryScan!=0 && now-g_lastNetSummaryScan<60) return;
   g_lastNetSummaryScan=now;
   string symbols[512];
   int counts[512], wins[512], losses[512];
   double gross[512], commissions[512], swaps[512], nets[512], winSum[512], lossSum[512];
   ArrayInitialize(counts,0); ArrayInitialize(wins,0); ArrayInitialize(losses,0);
   ArrayInitialize(gross,0.0); ArrayInitialize(commissions,0.0);
   ArrayInitialize(swaps,0.0); ArrayInitialize(nets,0.0);
   ArrayInitialize(winSum,0.0); ArrayInitialize(lossSum,0.0);
   int symbolCount=0, included=0, skipped=0;
   double totalGross=0.0, totalCommission=0.0, totalSwap=0.0, totalNet=0.0;
   double totalWinSum=0.0, totalLossSum=0.0;
   int totalWins=0, totalLosses=0;
   int historyTotal=OrdersHistoryTotal();
   for(int p=historyTotal-1; p>=0; p--)
   {
      if(!OrderSelect(p,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if((type!=OP_BUY && type!=OP_SELL) || OrderCloseTime()<=0) continue;
      string sym=OrderSymbol();
      int idx=-1;
      for(int k=0;k<symbolCount;k++)
      {
         if(symbols[k]==sym) { idx=k; break; }
      }
      if(idx<0)
      {
         if(symbolCount>=512) { skipped++; continue; }
         idx=symbolCount++;
         symbols[idx]=sym;
      }
      double g=OrderProfit();
      double c=OrderCommission();
      double s=OrderSwap();
      double n=g+c+s;
      counts[idx]++;
      gross[idx]+=g;
      commissions[idx]+=c;
      swaps[idx]+=s;
      nets[idx]+=n;
      if(n>0.0) { winSum[idx]+=n; totalWinSum+=n; }
      else if(n<0.0) { lossSum[idx]+=-n; totalLossSum+=-n; }
      if(n>0.000001) wins[idx]++;
      else if(n< -0.000001) losses[idx]++;
      included++;
      totalGross+=g;
      totalCommission+=c;
      totalSwap+=s;
      totalNet+=n;
      if(n>0.000001) totalWins++;
      else if(n< -0.000001) totalLosses++;
   }
   string fn="Bitey_Ens_NetByAsset_"+IntegerToString(InpMagic)+".csv";
   ResetLastError();
   int h=FileOpen(fn,FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE)
   {
      int err=GetLastError();
      Print("NET_SUMMARY_OPEN_FAILED | file=",fn," error=",err,
            " | expected_folder=MQL4\\Files");
      return;
   }
   FileWrite(h,"updated_server_time",TimeToString(now,TIME_DATE|TIME_SECONDS));
   FileWrite(h,"magic",InpMagic,"history_orders_visible_to_MT4",historyTotal,
             "matched_closed_trades",included,"skipped_symbol_limit",skipped);
   FileWrite(h,"symbol","closed_trades","wins_net","losses_net","gross_profit","commission","swap","net_profit");
   for(int j=0;j<symbolCount;j++)
   {
      FileWrite(h,symbols[j],counts[j],wins[j],losses[j],
                DoubleToString(gross[j],2),DoubleToString(commissions[j],2),
                DoubleToString(swaps[j],2),DoubleToString(nets[j],2));
   }
   FileWrite(h,"TOTAL",included,totalWins,totalLosses,DoubleToString(totalGross,2),
             DoubleToString(totalCommission,2),DoubleToString(totalSwap,2),DoubleToString(totalNet,2));
   FileClose(h);
   if(included>0 && included!=g_lastPerfClosed)
   {
      g_lastPerfClosed=included;   // one snapshot per change in closed-trade count
      double pfT=(totalLossSum>0.0?totalWinSum/totalLossSum:(totalWinSum>0.0?999.0:0.0));
      BiteyCsvLogPerformance(EA_VERSION,"TOTAL","ALL",included,totalWins,totalLosses,totalGross,totalCommission,
         totalSwap,totalNet,pfT,ClosedCurveMaxDDPct(),totalNet/included,g_abstentions,
         "CLOSED_TRADES_ONLY; DD on closed-trade curve (history assumed ordered by close time)");
      for(int ps=0;ps<symbolCount;ps++)
      {
         double pfS=(lossSum[ps]>0.0?winSum[ps]/lossSum[ps]:(winSum[ps]>0.0?999.0:0.0));
         BiteyCsvLogPerformance(EA_VERSION,"SYMBOL",symbols[ps],counts[ps],wins[ps],losses[ps],gross[ps],commissions[ps],
            swaps[ps],nets[ps],pfS,0.0,(counts[ps]>0?nets[ps]/counts[ps]:0.0),0,"DD_NOT_COMPUTED_PER_SYMBOL");
      }
   }
   Print("NET_SUMMARY_UPDATED | file=",fn," folder=MQL4\\Files",
         " | history=",historyTotal," matched=",included," assets=",symbolCount,
         " | gross=",DoubleToString(totalGross,2),
         " commission=",DoubleToString(totalCommission,2),
         " swap=",DoubleToString(totalSwap,2),
         " net=",DoubleToString(totalNet,2),
         " | set Account History to All History for full available totals");
}
double RiskCapital()
{
   if(!InpUseEquityRisk) return(InpReferenceCapitalUSD);
   double c=MathMin(AccountBalance(),AccountEquity());
   return(c>1.0?c:InpReferenceCapitalUSD);
}
bool FridayCutoff(string sym)
{
   if(InpFridayFlatHour<=0 || IsCrypto(sym)) return(false);
   datetime t=TimeCurrent();
   return(TimeDayOfWeek(t)==5 && TimeHour(t)>=InpFridayFlatHour);
}
string ResolveSymbol(string want)
{
   string w=want;
   StringToUpper(w);
   int total=SymbolsTotal(false);               // every symbol the broker offers
   for(int i=0;i<total;i++)
   {
      string n=SymbolName(i,false);
      string u=n;
      StringToUpper(u);
      if(u==w) return(n);
   }
   return("");
}
void AddExtraSymbols()
{
   if(IsTesting()) return;                      // Tester models the chart symbol only
   string csv=InpExtraSymbolsCSV;
   StringTrimLeft(csv); StringTrimRight(csv);
   while(StringLen(csv)>0 && g_symbolCount<MAX_SYMBOLS)
   {
      int p=StringFind(csv,",");
      string s;
      if(p<0) { s=csv; csv=""; }
      else { s=StringSubstr(csv,0,p); csv=StringSubstr(csv,p+1); }
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s)<=0) continue;
      string real=ResolveSymbol(s);
      if(real=="") { Print("EXTRA_SYMBOL_NOT_FOUND | requested=",s," | not offered by this broker"); continue; }
      if(!SymbolSelect(real,true)) { Print("EXTRA_SYMBOL_SELECT_FAILED | symbol=",real," error=",GetLastError()); continue; }
      string k=AssetKey(real);
      bool replaced=false;
      for(int i=0;i<g_symbolCount;i++)
         if(g_keys[i]==k)
         {
            Print("EXTRA_SYMBOL | requested=",s," | replaces alias ",g_symbols[i]," with ",real);
            g_symbols[i]=real;
            replaced=true;
            break;
         }
      if(!replaced)
      {
         AddSymbol(real);
         Print("EXTRA_SYMBOL | requested=",s," | added as ",real);
      }
   }
}
void AddAllCrypto()
{
   if(!InpAutoAddCrypto || IsTesting()) return;
   int total=SymbolsTotal(false);
   int added=0, skipped=0;
   string list="";
   for(int i=0;i<total && g_symbolCount<MAX_SYMBOLS;i++)
   {
      string n=SymbolName(i,false);
      if(!(IsCrypto(n) || (InpAutoAddUSDT && IsUSDTSymbol(n) && InpTradeEquityTokens))) continue;
      string k=AssetKey(n);
      bool dup=false;
      for(int j=0;j<g_symbolCount;j++)
         if(g_keys[j]==k) { dup=true; break; }
      if(dup) continue;
      if(MarketInfo(n,MODE_TRADEALLOWED)<=0) { skipped++; continue; }
      if(!SymbolSelect(n,true)) { skipped++; continue; }
      AddSymbol(n);
      added++;
      list+=n+" ";
   }
   Print("AUTO_CRYPTO | added=",added," skippedNotTradable=",skipped," | ",list);
}
int CloseAllPositions(string reason)
{
   int left=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      if(!CloseTicket(OrderTicket(),reason)) left++;
   }
   return(left);
}
string EntryBlockReason()
{   if(InpRequireCsvAudit && g_csvFailed) return("CSV_AUDIT_UNAVAILABLE");
   double cap=RiskCapital();   if(InpMaxTradesPerDay>0 && TradesOpenedToday()>=InpMaxTradesPerDay) return("DAILY_TRADE_CAP");
   return("");
}
void AddCcyExposure(string sym,int type,int &net[])
{
   string cc[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   string k=AssetKey(sym);
   string base=StringSubstr(k,0,3), quote=StringSubstr(k,3,3);
   int sgn=(type==OP_BUY?1:-1);
   for(int ci=0;ci<8;ci++)
   {
      if(cc[ci]==base)  net[ci]+=sgn;
      if(cc[ci]==quote) net[ci]-=sgn;
   }
}
bool CorrelationOK(string sym,int cmd,string &why)
{
   why="";
   if(!InpUseCorrelationGuard) return(true);
   if(IsCrypto(sym))
   {
      if(InpMaxCryptoPositions<=0) return(true);
      int cryptoOpen=0;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
         if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
         if(IsCrypto(OrderSymbol())) cryptoOpen++;
      }
      if(cryptoOpen>=InpMaxCryptoPositions) { why="CRYPTO_CLUSTER_CAP open="+IntegerToString(cryptoOpen); return(false); }
      return(true);
   }
   if(IsEquityToken(sym))
   {
      if(InpMaxEquityPositions<=0) return(true);
      int eqOpen=0;
      for(int e=OrdersTotal()-1;e>=0;e--)
      {
         if(!OrderSelect(e,SELECT_BY_POS,MODE_TRADES)) continue;
         if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
         if(IsEquityToken(OrderSymbol())) eqOpen++;
      }
      if(eqOpen>=InpMaxEquityPositions) { why="EQUITY_CLUSTER_CAP open="+IntegerToString(eqOpen); return(false); }
      return(true);
   }
   if(!IsForex(sym)) return(true);
   if(InpMaxCcyExposure<=0 && InpMaxCcyGross<=0) return(true);
   string cc[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   int expo[8], gross[8];
   ArrayInitialize(expo,0);
   ArrayInitialize(gross,0);
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(!IsForex(OrderSymbol())) continue;
      AddCcyExposure(OrderSymbol(),OrderType(),expo);
      AddCcyGross(OrderSymbol(),gross);
   }
   AddCcyExposure(sym,cmd,expo);
   AddCcyGross(sym,gross);
   for(int k2=0;k2<8;k2++)
   {
      if(InpMaxCcyExposure>0 && MathAbs(expo[k2])>InpMaxCcyExposure)
      {
         why="FX_CURRENCY_EXPOSURE_CAP "+cc[k2]+" net="+IntegerToString(expo[k2]);
         return(false);
      }
      if(InpMaxCcyGross>0 && gross[k2]>InpMaxCcyGross)
      {
         why="FX_CURRENCY_GROSS_CAP "+cc[k2]+" gross="+IntegerToString(gross[k2]);
         return(false);
      }
   }
   return(true);
}
void AddCcyGross(string sym,int &gross[])
{
   string cc[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   string k=AssetKey(sym);
   string base=StringSubstr(k,0,3), quote=StringSubstr(k,3,3);
   for(int ci=0;ci<8;ci++)
   {
      if(cc[ci]==base)  gross[ci]++;
      if(cc[ci]==quote) gross[ci]++;
   }
}
double DiversifyOverlap(string sym,int cmd)
{
   if(InpDiversifyPenalty<=0.0) return(0.0);
   if(IsCrypto(sym))
   {
      int same=0;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
         if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
         if(IsCrypto(OrderSymbol()) && OrderType()==cmd) same++;
      }
      return((double)same);
   }
   if(!IsForex(sym)) return(0.0);
   string cc[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   int expo[8];
   ArrayInitialize(expo,0);
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(!IsForex(OrderSymbol())) continue;
      AddCcyExposure(OrderSymbol(),OrderType(),expo);
   }
   string k=AssetKey(sym);
   string base=StringSubstr(k,0,3), quote=StringSubstr(k,3,3);
   int sgn=(cmd==OP_BUY?1:-1);
   double ov=0.0;
   for(int ci=0;ci<8;ci++)
   {
      if(cc[ci]==base  && expo[ci]*sgn>0)    ov+=expo[ci]*sgn;
      if(cc[ci]==quote && expo[ci]*(-sgn)>0) ov+=expo[ci]*(-sgn);
   }
   return(ov);
}

//+------------------------------------------------------------------+
//| v1.8.0.3 helpers                                                  |
//+------------------------------------------------------------------+

// Per 1.00 lot, account currency: current spread cost and round-turn commission
void EstCostPerLot(string sym,double &spreadCost,double &commission)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
   spreadCost=0.0;
   commission=CommissionPerLot(sym);
   if(tv>0.0 && ts>0.0 && bid>0.0 && ask>=bid) spreadCost=((ask-bid)/ts)*tv;
}

// Per 1.00 lot: spread cost, commission and the max slippage this EA accepts (InpSlippagePoints)
void EstExecCostPerLot(string sym,double &spreadCost,double &commission,double &slippage)
{
   EstCostPerLot(sym,spreadCost,commission);
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE), pt=MarketInfo(sym,MODE_POINT);
   slippage=((tv>0.0 && ts>0.0 && pt>0.0)?(InpSlippagePoints*pt/ts)*tv:0.0);
}

// Per 1.00 lot: net result if the initial TP is reached (target distance minus spread and commission)
double ExpectedNetPerLot(string sym)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(tv<=0.0 || ts<=0.0 || atr<=0.0) return(0.0);
   double sc,cm;
   EstCostPerLot(sym,sc,cm);
   return(((atr*InpStopATR*InpRewardRisk)/ts)*tv-sc-cm);
}

void LogAllVotes(const string decisionId,const string sym,const int tf,
                 const string &names[],const string &fams[],const int &dirs[],const double &scores[])
{
   for(int v=0;v<30;v++)
      BiteyCsvLogEvaluatorVote(decisionId,EA_VERSION,sym,tf,names[v],fams[v],
         (dirs[v]>0?"BUY":(dirs[v]<0?"SELL":"ABSTAIN")),scores[v],1.0,
         MathAbs(scores[v]),(dirs[v]!=0),(dirs[v]==0?"NO_SIGNAL":"CLOSED_BAR_SIGNAL"));
}

void LogCandidateNotSelected(int idx,string reason)
{
   string id=g_candSym[idx]+"_"+IntegerToString((int)iTime(g_candSym[idx],InpSignalTF,1));
   BiteyCsvLogAssetAssembly(id,EA_VERSION,g_candSym[idx],InpSignalTF,g_candScore[idx],0.0,0.0,30,
      g_candBuyVotes[idx],g_candSellVotes[idx],false,reason);
   BiteyCsvLogAction(id,EA_VERSION,g_candSym[idx],"ASSEMBLY1","NOT_SELECTED",0,
      (g_candCmd[idx]==OP_BUY?"BUY":"SELL"),g_candScore[idx],reason);
}

// Reject rows: the same symbol+reason is written again only after InpRejectLogMinutes (0 = always)
bool RejectCsvDue(string sym,string reason)
{
   int i=SymIndex(sym);
   if(i<0) return(true);
   datetime now=TimeCurrent();
   if(InpRejectLogMinutes>0 && g_lastRejectCsvWhy[i]==reason &&
      now-g_lastRejectCsvTime[i]<InpRejectLogMinutes*60) return(false);
   g_lastRejectCsvWhy[i]=reason;
   g_lastRejectCsvTime[i]=now;
   return(true);
}

void RememberCloseReason(int ticket,string reason)
{
   int slot=g_closeN%64;
   g_closeTicket[slot]=ticket;
   g_closeReason[slot]=reason;
   g_closeN++;
}

// Reason the EA itself closed the ticket; otherwise infer from the broker comment suffix
string LookupCloseReason(int ticket,string comment)
{
   for(int i=0;i<64;i++)
      if(g_closeTicket[i]==ticket && g_closeReason[i]!="") return(g_closeReason[i]);
   if(StringFind(comment,"[sl]")>=0) return("BROKER_SL");
   if(StringFind(comment,"[tp]")>=0) return("BROKER_TP");
   return("UNKNOWN_OR_MANUAL");
}

// Max drawdown (%) of the cumulative closed-trade net curve of this EA.
// Assumes MT4 history is listed in close-time order; base = risk capital + running peak.
double ClosedCurveMaxDDPct()
{
   double cum=0.0, peak=0.0, maxDD=0.0;
   int total=OrdersHistoryTotal();
   for(int i=0;i<total;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL || OrderCloseTime()<=0) continue;
      cum+=OrderProfit()+OrderSwap()+OrderCommission();
      if(cum>peak) peak=cum;
      double base=RiskCapital()+peak;
      if(base>0.0)
      {
         double dd=(peak-cum)/base*100.0;
         if(dd>maxDD) maxDD=dd;
      }
   }
   return(maxDD);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| v1.8.0.8: entry viability BEFORE the 30 models and the ranking.     |
//| Same stop distance, spread rule, cost-R rule and lot sizing as      |
//| OpenTrade, which keeps its own checks as a backstop. A candidate    |
//| that cannot pass them would only be selected and then rejected.     |
//+------------------------------------------------------------------+
bool EntryViable(string sym,string &why)
{
   why="";
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(bid<=0.0 || ask<bid || point<=0.0 || atr<=0.0) return(true);   // bad data: let the existing checks report it
   double spreadPrice=ask-bid;
   double brokerMin=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*point;
   double stopDist=EntryStopDist(sym,atr,spreadPrice,brokerMin);
   if(InpPrefilterSpreadCost)
   {
      if(spreadPrice>stopDist*InpMaxSpreadPctOfStop/100.0) { why="SPREAD_VS_STOP"; return(false); }
      if(EntryCostR(sym,stopDist)>InpMaxCostR) { why="COST_R_ABOVE_MAX"; return(false); }
   }
   if(InpPrefilterMinLot)
   {
      double perTrade=RiskCapital()*InpRiskPctPerTrade/100.0;
      if(LotsForRisk(sym,stopDist,perTrade)<=0.0) { why="MIN_LOT_EXCEEDS_BUDGET_OR_CAP"; return(false); }
   }
   return(true);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| v1.8.0.9 helpers                                                  |
//+------------------------------------------------------------------+
bool IsLiveOrderType(int type)
{
   if(type==OP_BUY || type==OP_SELL) return(true);
   return(InpUseLimitEntry && (type==OP_BUYLIMIT || type==OP_SELLLIMIT));
}
double RewardRiskFor(int regime)
{
   return(regime==1 ? InpRewardRisk : InpRewardRiskRange);
}
// Stop distance: InpStopATR x ATR, widened in 0.25 ATR steps (up to InpStopATRMax) while cost-R exceeds InpTargetCostR.
// Wider stop -> smaller lot for the same money risk -> less commission and spread per R.
double EntryStopDist(string sym,double atr,double spreadPrice,double brokerMin)
{
   double floorD=spreadPrice+brokerMin;
   double k=InpStopATR;
   double d=MathMax(atr*k,floorD);
   if(InpTargetCostR>0.0 && InpStopATRMax>InpStopATR+1e-9)
   {
      while(k<InpStopATRMax-1e-9 && EntryCostR(sym,d)>InpTargetCostR)
      {
         k=MathMin(k+0.25,InpStopATRMax);
         d=MathMax(atr*k,floorD);
      }
   }
   return(d);
}
double CandCostR(string sym)
{
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(bid<=0.0 || ask<bid || point<=0.0 || atr<=0.0) return(0.0);
   double brokerMin=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*point;
   double sd=EntryStopDist(sym,atr,ask-bid,brokerMin);
   double c=EntryCostR(sym,sd);
   return(c>=99.0 ? 0.0 : c);
}
// Realized net result (profit+commission+swap) of this symbol's recent closed trades, in R (nominal per-trade risk).
void SymbolMemory(string sym,int &n,double &sumR)
{
   n=0; sumR=0.0;
   double r1=RiskCapital()*InpRiskPctPerTrade/100.0;
   if(r1<=0.0 || InpMemWindow<=0) return;
   datetime from=TimeCurrent()-(datetime)InpMemDays*86400;
   int seen=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<800 && n<InpMemWindow;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber()!=InpMagic || OrderSymbol()!=sym || OrderType()>OP_SELL) continue;
      if(InpMemDays>0 && OrderCloseTime()<from) continue;
      n++;
      sumR+=(OrderProfit()+OrderSwap()+OrderCommission())/r1;
   }
}
// Shrunk mean net edge in R: (sum + w*prior)/(n + w). With few trades it stays near the prior.
double NetEdgeR(string sym,int &n)
{
   double sumR=0.0;
   SymbolMemory(sym,n,sumR);
   double w=MathMax(0.0,InpMemPriorWeight);
   if(n+w<=0.0) return(InpMemPriorEdgeR);
   return((sumR+w*InpMemPriorEdgeR)/(n+w));
}
int TradesOpenedToday()
{
   datetime ds=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   int n=0, seen=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<800;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      if(OrderOpenTime()>=ds) n++;
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      if(OrderOpenTime()>=ds) n++;
   }
   return(n);
}
// Resting entry at the touch price. Returns 0 to fall back to a market order.
double LimitEntryPrice(string sym,int cmd,double bid,double ask,double point,int digits)
{
   double spr=ask-bid;
   if(spr<=0.0 || point<=0.0) return(0.0);
   double minDist=(MarketInfo(sym,MODE_STOPLEVEL)+1.0)*point;
   double dist=MathMax(spr,minDist);
   if(dist>spr*InpLimitMaxSpreadMult) return(0.0);
   double px=(cmd==OP_BUY ? ask-dist : bid+dist);
   return(NormalizeDouble(px,digits));
}
void ManagePendingLimits()
{
   if(!InpUseLimitEntry) return;
   int maxAge=InpLimitExpireBars*PeriodSeconds(InpSignalTF);
   if(maxAge<=0) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int ty=OrderType();
      if(ty!=OP_BUYLIMIT && ty!=OP_SELLLIMIT) continue;
      if((int)(TimeCurrent()-OrderOpenTime())<maxAge) continue;
      int tk=OrderTicket();
      string s=OrderSymbol();
      bool done=OrderDelete(tk);
      BiteyCsvLogAction(s+"_"+IntegerToString(tk),EA_VERSION,s,"EXECUTION",(done?"LIMIT_EXPIRED":"LIMIT_DELETE_FAILED"),tk,
         (ty==OP_BUYLIMIT?"BUY":"SELL"),0.0,"UNFILLED_AFTER_"+IntegerToString(InpLimitExpireBars)+"_BARS");
   }
}
//+------------------------------------------------------------------+
