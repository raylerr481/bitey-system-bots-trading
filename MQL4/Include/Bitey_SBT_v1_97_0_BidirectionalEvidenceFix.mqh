//+------------------------------------------------------------------+
//| Bitey_SBT_v1_97_0_BidirectionalEvidenceFix.mqh                   |
//| v1.97.0 evidence-evaluation patch for MT4 / MQL4                 |
//|                                                                  |
//| IMPORTANT: This is an integration module, not a complete EA.     |
//| It does not place, modify, or close orders.                      |
//| Call the evaluator for BOTH BUY and SELL on every asset scan.    |
//| Preserve the EA's existing risk, manual-control, and order gates. |
//+------------------------------------------------------------------+
#ifndef BITEY_SBT_V1_97_0_BIDIRECTIONAL_EVIDENCE_FIX_MQH
#define BITEY_SBT_V1_97_0_BIDIRECTIONAL_EVIDENCE_FIX_MQH

#define BITEY_EVIDENCE_MIN_TRAIN_N       12
#define BITEY_EVIDENCE_MIN_TRAIN_WR      0.420
#define BITEY_EVIDENCE_MIN_TRAIN_AVGR    0.020
#define BITEY_EVIDENCE_MIN_HOLDOUT_N     6
#define BITEY_EVIDENCE_MIN_HOLDOUT_WR    0.400
#define BITEY_EVIDENCE_MIN_HOLDOUT_AVGR  0.000

#define BITEY_DIRECTION_NONE  0
#define BITEY_DIRECTION_BUY   1
#define BITEY_DIRECTION_SELL -1

struct BiteyEvidenceStats
{
   bool   calculated;
   int    trainN;
   double trainWinRate;
   double trainAvgR;
   int    holdoutN;
   double holdoutWinRate;
   double holdoutAvgR;
};

struct BiteyEvidenceResult
{
   bool   evaluated;
   bool   qualified;
   string reason;
};

void BiteyInitEvidenceResult(BiteyEvidenceResult &result)
{
   result.evaluated = false;
   result.qualified = false;
   result.reason = "NOT_EVALUATED";
}

BiteyEvidenceResult BiteyEvaluateDirectionEvidence(
   string symbol,
   int direction,
   BiteyEvidenceStats &stats)
{
   BiteyEvidenceResult result;
   BiteyInitEvidenceResult(result);

   string side = "UNKNOWN";
   if(direction == BITEY_DIRECTION_BUY)  side = "BUY";
   if(direction == BITEY_DIRECTION_SELL) side = "SELL";

   if(!stats.calculated)
   {
      result.reason = "EVIDENCE_CALCULATION_UNAVAILABLE";
      Print("SBT EVIDENCE | symbol=", symbol,
            " direction=", side,
            " evaluated=false qualified=false reason=", result.reason);
      return(result);
   }

   result.evaluated = true;

   if(stats.trainN < BITEY_EVIDENCE_MIN_TRAIN_N)
      result.reason = "INSUFFICIENT_TRAIN_SAMPLES";
   else if(stats.trainWinRate < BITEY_EVIDENCE_MIN_TRAIN_WR)
      result.reason = "TRAIN_WIN_RATE_FAILED";
   else if(stats.trainAvgR <= BITEY_EVIDENCE_MIN_TRAIN_AVGR)
      result.reason = "TRAIN_AVG_R_FAILED";
   else if(stats.holdoutN < BITEY_EVIDENCE_MIN_HOLDOUT_N)
      result.reason = "INSUFFICIENT_HOLDOUT_SAMPLES";
   else if(stats.holdoutWinRate < BITEY_EVIDENCE_MIN_HOLDOUT_WR)
      result.reason = "HOLDOUT_WIN_RATE_FAILED";
   else if(stats.holdoutAvgR <= BITEY_EVIDENCE_MIN_HOLDOUT_AVGR)
      result.reason = "HOLDOUT_AVG_R_FAILED";
   else
   {
      result.qualified = true;
      result.reason = "TRAIN_AND_HOLDOUT_PASS";
   }

   Print("SBT EVIDENCE | symbol=", symbol,
         " direction=", side,
         " evaluated=", result.evaluated,
         " trainN=", stats.trainN,
         " trainWR=", DoubleToString(stats.trainWinRate, 3),
         " trainAvgR=", DoubleToString(stats.trainAvgR, 3),
         " holdoutN=", stats.holdoutN,
         " holdoutWR=", DoubleToString(stats.holdoutWinRate, 3),
         " holdoutAvgR=", DoubleToString(stats.holdoutAvgR, 3),
         " qualified=", result.qualified,
         " reason=", result.reason);

   return(result);
}

// This is a final signal/evidence gate only. The caller must still run
// all existing spread, quote freshness, duplicate-asset, max-position,
// stop-loss sizing, USD500 budget, and manual trading-authority checks.
bool BiteyBidirectionalEvidenceAllowsEntry(
   string symbol,
   int currentSignal,
   BiteyEvidenceResult &buyEvidence,
   BiteyEvidenceResult &sellEvidence)
{
   if(currentSignal == BITEY_DIRECTION_NONE)
   {
      Print("SBT ENTRY REJECTED | symbol=", symbol,
            " reason=NO_LIVE_SIGNAL",
            " | historical approval alone cannot open an order");
      return(false);
   }

   if(currentSignal == BITEY_DIRECTION_BUY)
   {
      if(!buyEvidence.evaluated || !buyEvidence.qualified)
      {
         Print("SBT ENTRY REJECTED | symbol=", symbol,
               " direction=BUY reason=", buyEvidence.reason);
         return(false);
      }
      Print("SBT EVIDENCE GATE PASS | symbol=", symbol,
            " direction=BUY | continue to existing risk/order gates");
      return(true);
   }

   if(currentSignal == BITEY_DIRECTION_SELL)
   {
      if(!sellEvidence.evaluated || !sellEvidence.qualified)
      {
         Print("SBT ENTRY REJECTED | symbol=", symbol,
               " direction=SELL reason=", sellEvidence.reason);
         return(false);
      }
      Print("SBT EVIDENCE GATE PASS | symbol=", symbol,
            " direction=SELL | continue to existing risk/order gates");
      return(true);
   }

   Print("SBT ENTRY REJECTED | symbol=", symbol,
         " reason=INVALID_SIGNAL_VALUE signal=", currentSignal);
   return(false);
}

#endif // BITEY_SBT_V1_97_0_BIDIRECTIONAL_EVIDENCE_FIX_MQH
