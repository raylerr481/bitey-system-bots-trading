//+------------------------------------------------------------------+
//| Bitey_Ensemble_Experimental_CSV_Audit.mqh                         |
//| CSV audit helpers for the experimental 30-evaluator architecture. |
//| Install in MQL4\\Include and include from the experimental EA.   |
//| Writes to this terminal's MQL4\\Files directory.                |
//+------------------------------------------------------------------+
#ifndef BITEY_ENSEMBLE_EXPERIMENTAL_CSV_AUDIT_MQH
#define BITEY_ENSEMBLE_EXPERIMENTAL_CSV_AUDIT_MQH

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
      return INVALID_HANDLE;
   }
   if(FileSize(h) == 0)
   {
      // Write the header as a raw delimited line so each header is a separate column.
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

// One row per evaluator per candidate/decision. Use the same decisionId across
// all 30 rows, both assemblies, and the eventual trade (if any).
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

// One row per asset considered by Assembly 1, including rejected candidates.
void BiteyCsvLogAssetAssembly(
   const string decisionId, const string eaVersion, const string symbol,
   const int timeframe, const double opportunityScore, const double expectedNet,
   const double estimatedCost, const int validModels, const int buyVotes,
   const int sellVotes, const bool selected, const string reason)
{
   string fn = "Bitey_AssetAssembly.csv";
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;symbol;timeframe;opportunity_score;expected_net_estimate;estimated_cost;valid_models;buy_votes;sell_votes;selected;reason");
   if(h == INVALID_HANDLE) return;
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, symbol, timeframe,
      DoubleToString(opportunityScore, 6), DoubleToString(expectedNet, 2),
      DoubleToString(estimatedCost, 2), validModels, buyVotes, sellVotes,
      (selected ? "true" : "false"), reason);
   BiteyCsvClose(h);
}

// One row per Assembly 2 decision. direction should be BUY, SELL or ABSTAIN.
void BiteyCsvLogTradeAssembly(
   const string decisionId, const string eaVersion, const string symbol,
   const int timeframe, const string direction, const double consensusScore,
   const double confidence, const int supportingModels, const int opposingModels,
   const double estimatedSpreadCost, const double estimatedCommission,
   const double estimatedSlippage, const bool approved, const string reason)
{
   string fn = "Bitey_TradeAssembly.csv";
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;symbol;timeframe;decision;consensus_score;confidence;supporting_models;opposing_models;estimated_spread_cost;estimated_commission;estimated_slippage;approved;reason");
   if(h == INVALID_HANDLE) return;
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, symbol, timeframe,
      direction, DoubleToString(consensusScore, 6), DoubleToString(confidence, 6),
      supportingModels, opposingModels, DoubleToString(estimatedSpreadCost, 2),
      DoubleToString(estimatedCommission, 2), DoubleToString(estimatedSlippage, 2),
      (approved ? "true" : "false"), reason);
   BiteyCsvClose(h);
}

// Log after an order has actually been accepted by the broker/server.
void BiteyCsvLogTradeOpened(
   const string decisionId, const string eaVersion, const int ticket,
   const string symbol, const string direction, const double lots,
   const double openPrice, const double initialSL, const double initialTP,
   const double referenceCapital, const double riskMoney,
   const string riskMode, const string reason)
{
   string fn = "Bitey_TradeAudit.csv";
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;ticket;symbol;direction;lots;open_price;initial_sl;initial_tp;reference_capital_usd;risk_money_estimate;risk_mode;reason");
   if(h == INVALID_HANDLE) return;
   int digits=(int)MarketInfo(symbol,MODE_DIGITS);
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, ticket, symbol,
      direction, DoubleToString(lots, 2), DoubleToString(openPrice, digits),
      DoubleToString(initialSL, digits), DoubleToString(initialTP, digits),
      DoubleToString(referenceCapital, 2), DoubleToString(riskMoney, 2),
      riskMode, reason);
   BiteyCsvClose(h);
}

// Call once per fully closed order. net = profit + commission + swap.
// Pass actual OrderCommission() and OrderSwap() from the selected history order.
void BiteyCsvLogTradeClosed(
   const string decisionId, const string eaVersion, const int ticket,
   const string symbol, const string direction, const double lots,
   const datetime openedAt, const datetime closedAt, const double openPrice,
   const double closePrice, const double grossProfit, const double commission,
   const double swap, const double slippagePoints, const string closeReason)
{
   string fn = "Bitey_ClosedTrades.csv";
   double net = grossProfit + commission + swap;
   int durationSeconds = (int)(closedAt - openedAt);
   int h = BiteyCsvOpenAppend(fn,
      "timestamp;decision_id;ea_version;ticket;symbol;direction;lots;opened_at;closed_at;duration_seconds;open_price;close_price;gross_profit;commission;swap;net_profit;slippage_points;close_reason");
   if(h == INVALID_HANDLE) return;
   int digits=(int)MarketInfo(symbol,MODE_DIGITS);
   FileWrite(h, BiteyCsvStamp(), decisionId, eaVersion, ticket, symbol,
      direction, DoubleToString(lots, 2),
      TimeToString(openedAt, TIME_DATE|TIME_SECONDS),
      TimeToString(closedAt, TIME_DATE|TIME_SECONDS), durationSeconds,
      DoubleToString(openPrice, digits), DoubleToString(closePrice, digits),
      DoubleToString(grossProfit, 2), DoubleToString(commission, 2),
      DoubleToString(swap, 2), DoubleToString(net, 2),
      DoubleToString(slippagePoints, 1), closeReason);
   BiteyCsvClose(h);
}

// Call whenever SL/TP changes. Log the full transition, not only final values.
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

// Snapshot metrics; aggregate by date/version outside the EA to avoid
// mixing open floating P/L with realized closed-trade performance.
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

#endif // BITEY_ENSEMBLE_EXPERIMENTAL_CSV_AUDIT_MQH
