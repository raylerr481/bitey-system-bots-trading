//+------------------------------------------------------------------+
//| Bitey_Ensemble_Scalper_MultiAsset_v1_8_2_0_Scratch_chagpt.mq4    |
//| SCRATCH / DESIGN SCAFFOLD - Bitey Time-to-Profit Ensemble         |
//| Based on the approved TPI specification dated 2026-10-30.        |
//+------------------------------------------------------------------+
//| STRATEGY SPECIFICATION (kept inside the EA source as requested)   |
//|                                                                  |
//| PRIMARY OBJECTIVE                                                |
//| Seek short-duration intraday trades with a small POSITIVE NET     |
//| result, while limiting exposure time and enforcing hard risk     |
//| controls. No strategy can guarantee a profit on every trade.     |
//|                                                                  |
//| TRADE LIFECYCLE                                                   |
//| 1. Scan permitted symbols and evaluate market regime/opportunity. |
//| 2. Seven independent evaluators vote BUY / SELL / NEUTRAL /      |
//|    ABSTAIN: trend, range, momentum, volatility, cost, session,   |
//|    and historical edge. At least five aligned votes are needed.  |
//| 3. Cost and risk gates have veto power over the ensemble.         |
//| 4. If approved, open with broker-side SL and TP. Start the        |
//|    individual 20-minute timer from the ACTUAL OrderOpenTime.      |
//| 5. Close as soon as estimated NET profit >= TargetNetProfitUSD.  |
//| 6. If the net target is not reached, close at 20 minutes.         |
//| 7. SL or TP may close the trade earlier. Never widen the SL.      |
//| 8. Record outcome, duration, costs, excursions, votes and reason. |
//| 9. Apply symbol/direction cooldown and stricter re-entry after    |
//|    time exits or losses.                                          |
//|                                                                  |
//| NET PROFIT ACCOUNTING                                             |
//| OrderProfit() + OrderCommission() + OrderSwap() are the MT4       |
//| reported components. Spread is already reflected in execution    |
//| prices and must NOT be deducted twice. If close commission is    |
//| not yet booked, estimate it from broker-specific commission      |
//| data. Slippage is reflected by actual execution price. Convert    |
//| account currency to USD using a verified conversion quote; if     |
//| conversion/cost data are unreliable, abstain from new entries.   |
//| Taxes are not assumed to be charged by MT4; any tax estimate is   |
//| an external reporting item, not a fabricated execution cost.     |
//|                                                                  |
//| INITIAL RISK DESIGN                                               |
//| Risk/trade 0.25%; daily loss cap 2%; max 3 trades/day;            |
//| max 3 simultaneous positions; target +0.10 USD net; max life     |
//| 20 minutes. These are TEST STARTING VALUES, not validated edges.  |
//| No martingale, no averaging down, no risk escalation, no SL       |
//| widening, no bypass of broker/account protections.               |
//|                                                                  |
//| RE-ENTRY POLICY                                                   |
//| Target hit: normal fresh analysis. Time exit with loss: 20-minute |
//| cooldown and >=6/7 votes. SL: 30-minute cooldown and >=6/7 votes. |
//| Two consecutive losses: 60-minute cooldown and reinforced review. |
//| Daily loss cap: stop opening trades until next broker server day. |
//| Cooldowns never override the daily risk lock.                     |
//|                                                                  |
//| VALIDATION REQUIREMENTS                                           |
//| Functional tests for net target, 20-minute timeout, SL/TP,        |
//| restart recovery, commissions, currency conversion, reconnection,|
//| cooldown and MagicNumber isolation. Then realistic-cost backtest, |
//| out-of-sample validation and demo forward test. Minimum 200       |
//| representative trades is an initial diagnostic sample, not proof |
//| of statistical significance. Require positive net expectancy,    |
//| net PF > 1, controlled drawdown and robustness across periods.   |
//|                                                                  |
//| INTEGRATION                                                       |
//| MT4 EA remains final execution/risk authority. SBT audits data;   |
//| Bitey IA may analyze and propose parameter changes. AI must not   |
//| directly send MT4 orders, disable SL, bypass limits or deploy     |
//| unvalidated changes.                                              |
//|                                                                  |
//| IMPLEMENTATION STATUS                                             |
//| This file is a SAFE SCRATCH SCAFFOLD containing the specification|
//| and input contract. It does NOT yet implement the entry engine,  |
//| seven evaluators, net-cost estimator, order execution, 20-minute |
//| close manager, cooldown persistence or CSV trade audit. Trading  |
//| is disabled by default and this scaffold deliberately sends no   |
//| orders. Do not treat it as a finished or profitable EA.           |
//+------------------------------------------------------------------+
#property strict
#property version   "1.820"
#property description "Scratch scaffold: TPI ensemble specification; trading disabled; not validated"

//--- General operation
input bool   InpEnableTrading                 = false;
input bool   InpEnableMultiAsset               = true;
input bool   InpEnableBuy                      = true;
input bool   InpEnableSell                     = true;
input int    InpMagic                          = 30102620;
input int    InpSlippagePoints                 = 3;

//--- Time-to-profit contract
input double InpTargetNetProfitUSD             = 0.10;
input int    InpMaxTradeDurationMinutes        = 20;
input bool   InpEnableNetProfitLock            = true;
input bool   InpEnableTimeExit                 = true;

//--- Risk controls (initial test values; not performance validated)
input double InpRiskPercent                    = 0.25;
input double InpDailyLossLimitPct              = 2.0;
input int    InpMaxTradesPerDay                = 3;
input int    InpMaxOpenPositions               = 3;
input bool   InpRequireStopLoss                = true;
input bool   InpRequireTakeProfit              = true;

//--- Ensemble
input bool   InpEnableEnsemble                 = true;
input int    InpEnsembleModelCount             = 7;
input int    InpMinimumVotes                   = 5;
input int    InpStrictReentryVotes             = 6;

//--- Re-entry controls
input int    InpCooldownAfterTimeLossMinutes   = 20;
input int    InpCooldownAfterStopLossMinutes   = 30;
input int    InpCooldownAfterTwoLossesMinutes  = 60;

//--- Audit and recovery
input bool   InpEnableCSVAudit                 = true;
input bool   InpEnablePersistentRecovery       = true;

//--- Explicitly prohibited behaviors
input bool   InpEnableMartingale               = false;
input bool   InpEnableAveraging                = false;
input bool   InpAllowStopLossWidening          = false;

datetime g_lastStatusTime = 0;

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(1);

   Print("BITEY_TPI_SCRATCH_INIT",
         " | version=1.820",
         " | trading=", (InpEnableTrading ? "ON" : "OFF"),
         " | targetNetUSD=", DoubleToString(InpTargetNetProfitUSD, 2),
         " | maxDurationMin=", InpMaxTradeDurationMinutes,
         " | ensemble=", InpEnsembleModelCount,
         " | minVotes=", InpMinimumVotes,
         " | status=SPECIFICATION_SCAFFOLD_NO_ORDER_EXECUTION");

   if(InpTargetNetProfitUSD <= 0.0 ||
      InpMaxTradeDurationMinutes <= 0 ||
      InpEnsembleModelCount != 7 ||
      InpMinimumVotes < 1 ||
      InpMinimumVotes > InpEnsembleModelCount)
   {
      Print("BITEY_TPI_CONFIG_ERROR | invalid TPI configuration");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpEnableMartingale || InpEnableAveraging || InpAllowStopLossWidening)
   {
      Print("BITEY_TPI_SAFETY_ERROR | prohibited risk option enabled");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpEnableTrading)
   {
      Print("BITEY_TPI_BLOCK | trading requested but this scratch scaffold",
            " has no execution engine. No orders will be sent.");
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("BITEY_TPI_SCRATCH_DEINIT | reason=", reason);
}

//+------------------------------------------------------------------+
//| Timer: diagnostics only in this scaffold                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(TimeCurrent() == g_lastStatusTime)
      return;

   g_lastStatusTime = TimeCurrent();

   // Intentionally no order management or execution in this scaffold.
   // The production implementation must reconcile open tickets using
   // MagicNumber + OrderOpenTime and persist state across terminal restarts.
}

//+------------------------------------------------------------------+
//| Tick: no signal generation or order execution in this scaffold    |
//+------------------------------------------------------------------+
void OnTick()
{
   // Reserved for TPI_EntryEngine, TPI_Ensemble and trade management.
   // This file is deliberately non-trading until those modules are
   // implemented, reviewed, compiled and tested in MT4 Strategy Tester.
}
//+------------------------------------------------------------------+
