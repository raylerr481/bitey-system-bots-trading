//+------------------------------------------------------------------+
//| Multi-asset 32-variant 1.5 Committee Selection                   |
//| Votes rank signals; hard execution/risk gates remain mandatory.  |
//| Trading enabled by default; validate in demo before live use.     |
//+------------------------------------------------------------------+
#property strict
#property version "1.50"
#property description "Ranks ensemble candidates, applies hard safety gates, and opens at most one best candidate per scan cycle"

input string InpSymbolsCSV = ""; // Blank scans symbols in Market Watch
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_M5;
input int InpMagic = 21102026;
input double InpReferenceCapitalUSD = 500.0;
input double InpRiskPctPerTrade = 1.0;
input double InpMaxAggregateRiskPct = 2.0;
input int InpMaxOpenPositions = 3;
input double InpMaxRiskPerTradeUSD = 5.0;
input double InpMaxSpreadToATRPercent = 10.0; // Soft scoring threshold, not an automatic rejection
input double InpHardMaxSpreadToATRPercent = 35.0; // Hard cost-safety ceiling; never bypassed
input int InpMinActiveVotes = 5;       // Minimum directional quorum; ranking rewards broader agreement
input double InpMinDirectionalPct = 65.0; // Minimum winning-side share of active votes
input int InpMinVoteMargin = 3;          // Minimum BUY/SELL vote margin
input int InpATRPeriod = 14;
input double InpStopATR = 2.0;
input double InpRewardRisk = 1.5;
input bool InpEnableBreakEven = true;
input double InpBreakEvenTriggerATR = 1.0; // Arm break-even after favorable move of this many ATR
input int InpBreakEvenOffsetPoints = 2; // SL offset beyond entry; does not guarantee net profit after all costs
input bool InpEnableATRTrailing = true;
input double InpTrailingStartATR = 1.5; // Start trailing after favorable move of this many ATR
input double InpTrailingDistanceATR = 1.0; // Keep SL this many ATR behind price
input int InpTrailingStepPoints = 5; // Minimum SL improvement before sending OrderModify
input int InpMaxSpreadPoints = 80;
input int InpSlippagePoints = 20;
input int InpMinBars = 250;
input bool InpAllowBuy = true;
input bool InpAllowSell = true;
input bool InpOnePositionPerSymbol = true;
input bool InpEnableTrading = true; // Auto-trading enabled; retain all signal, broker and risk gates
input bool InpLogVotes = true;

#define MODEL_COUNT 32

struct Candidate
{
   string symbol; int cmd; int buyVotes; int sellVotes; int activeVotes; int margin;
   double directionalPct; double spreadPoints; double entry; double sl; double tp;
   double lots; double riskUSD; double atr; double stopDist; double score;
};
#define MAX_SYMBOLS 128
string g_symbols[MAX_SYMBOLS];
int g_symbolCount=0;
datetime g_lastBar[MAX_SYMBOLS];
int g_scanSymbols=0, g_scanVoteRejected=0, g_scanSpreadRejected=0, g_scanRiskRejected=0, g_scanOtherRejected=0;

int OnInit()
{
   ParseSymbols();
   if(g_symbolCount<=0) { Print("INIT_ERROR | no symbols found"); return(INIT_FAILED); }
   Print("BITEY_ENSEMBLE_INIT | symbols=",g_symbolCount," | models=",MODEL_COUNT,
         " | referenceCapital=",DoubleToString(InpReferenceCapitalUSD,2),
         " | riskPct=",DoubleToString(InpRiskPctPerTrade,2),
         " | tradingEnabled=",InpEnableTrading);
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   ManageOpenPositions();
   Candidate best; bool found=false; int eligibleScanned=0; bool scanAttempted=false;
   g_scanSymbols=0; g_scanVoteRejected=0; g_scanSpreadRejected=0; g_scanRiskRejected=0; g_scanOtherRejected=0;
   for(int i=0;i<g_symbolCount;i++)
   {
      string sym=g_symbols[i];
      if(!SymbolSelect(sym,true)) { g_scanOtherRejected++; LogReject(sym,"SYMBOL_SELECT_FAILED"); continue; }
      if(iBars(sym,InpSignalTF)<InpMinBars) { g_scanOtherRejected++; LogReject(sym,"INSUFFICIENT_HISTORY"); continue; }
      datetime bt=iTime(sym,InpSignalTF,0);
      if(bt<=0 || bt==g_lastBar[i]) continue;
      g_lastBar[i]=bt; scanAttempted=true;
      Candidate candidate;
      if(!EvaluateSymbol(sym,candidate)) continue;
      eligibleScanned++;
      if(!found || candidate.score>best.score ||
         (MathAbs(candidate.score-best.score)<0.0001 && candidate.riskUSD<best.riskUSD))
      { best=candidate; found=true; }
   }
   if(!scanAttempted) return;
   if(!found)
   {
      Print("BEST_CANDIDATE_NONE | reason=NO_SAFE_CANDIDATE | symbolsEvaluated=",g_scanSymbols,
         " | voteRejected=",g_scanVoteRejected," | spreadRejected=",g_scanSpreadRejected,
         " | riskRejected=",g_scanRiskRejected," | otherRejected=",g_scanOtherRejected,
         " | action=NO_ORDER_UNLESS_HARD_GATES_PASS");
      return;
   }
   Print("BEST_CANDIDATE_SELECTED | symbol=",best.symbol," | side=",(best.cmd==OP_BUY?"BUY":"SELL"),
      " | score=",DoubleToString(best.score,2)," | activeVotes=",best.activeVotes,
      " | directionalPct=",DoubleToString(best.directionalPct,1)," | margin=",best.margin,
      " | riskUSD=",DoubleToString(best.riskUSD,2)," | spreadPoints=",DoubleToString(best.spreadPoints,1),
      " | eligibleCandidates=",eligibleScanned," | action=ONLY_ONE_CANDIDATE");
   ExecuteCandidate(best);
}

void ParseSymbols()
{
   g_symbolCount=0;
   string csv=InpSymbolsCSV;
   StringTrimLeft(csv); StringTrimRight(csv);
   if(StringLen(csv)==0)
   {
      int total=SymbolsTotal(true);
      for(int i=0;i<total && g_symbolCount<MAX_SYMBOLS;i++)
      {
         string s=SymbolName(i,true);
         if(StringLen(s)>0) g_symbols[g_symbolCount++]=s;
      }
      return;
   }
   while(StringLen(csv)>0 && g_symbolCount<MAX_SYMBOLS)
   {
      int p=StringFind(csv,","); string s;
      if(p<0) { s=csv; csv=""; }
      else { s=StringSubstr(csv,0,p); csv=StringSubstr(csv,p+1); }
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s)>0) g_symbols[g_symbolCount++]=s;
   }
}

bool EvaluateSymbol(string sym,Candidate &c)
{
   g_scanSymbols++;
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   if(bid<=0 || ask<=0 || point<=0) { g_scanOtherRejected++; LogReject(sym,"INVALID_QUOTES_OR_POINT"); return(false); }

   // The committee votes first. The old implementation vetoed symbols before the vote
   // audit and required 8 votes even when a smaller committee had a clear majority.
   int buys=0,sells=0; ScoreEnsemble(sym,buys,sells);
   int activeVotes=buys+sells, winningVotes=MathMax(buys,sells), margin=MathAbs(buys-sells);
   double directionalPct=(activeVotes>0?100.0*winningVotes/activeVotes:0.0);
   double spread=(ask-bid)/point;
   if(InpLogVotes) Print("ENSEMBLE_AUDIT | symbol=",sym," | buyVotes=",buys," | sellVotes=",sells,
      " | activeVotes=",activeVotes," | directionalPct=",DoubleToString(directionalPct,1),
      " | margin=",margin," | spreadPoints=",DoubleToString(spread,1));

   if(activeVotes<InpMinActiveVotes) { g_scanVoteRejected++; LogReject(sym,"INSUFFICIENT_ACTIVE_VOTES"); return(false); }
   if(directionalPct<InpMinDirectionalPct) { g_scanVoteRejected++; LogReject(sym,"DIRECTIONAL_PERCENT_BELOW_MIN"); return(false); }
   if(margin<InpMinVoteMargin) { g_scanVoteRejected++; LogReject(sym,"VOTE_MARGIN_BELOW_MIN"); return(false); }
   int cmd=-1;
   if(InpAllowBuy && buys>sells) cmd=OP_BUY; else if(InpAllowSell && sells>buys) cmd=OP_SELL;
   if(cmd<0) { g_scanVoteRejected++; LogReject(sym,"ENSEMBLE_NO_CLEAR_CONSENSUS"); return(false); }

   // These are execution eligibility gates, not votes in the committee.
   if(spread>InpMaxSpreadPoints) { g_scanSpreadRejected++; LogReject(sym,"SPREAD_LIMIT"); return(false); }
   if(InpOnePositionPerSymbol && HasPositionForSymbol(sym)) { g_scanOtherRejected++; LogReject(sym,"POSITION_ALREADY_OPEN"); return(false); }
   if(CountOpenPositions()>=InpMaxOpenPositions) { g_scanOtherRejected++; LogReject(sym,"MAX_OPEN_POSITIONS"); return(false); }

   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(atr<=0) { g_scanOtherRejected++; LogReject(sym,"ATR_UNAVAILABLE"); return(false); }
   double spreadToATRPercent=(spread*point/atr)*100.0;
   if(InpHardMaxSpreadToATRPercent>0 && spreadToATRPercent>InpHardMaxSpreadToATRPercent)
   {
      g_scanSpreadRejected++;
      Print("SPREAD_COST_AUDIT | symbol=",sym," | spreadPoints=",DoubleToString(spread,1),
         " | spreadToATRPercent=",DoubleToString(spreadToATRPercent,2),
         " | hardLimitPercent=",DoubleToString(InpHardMaxSpreadToATRPercent,2));
      LogReject(sym,"SPREAD_COST_HARD_LIMIT"); return(false);
   }

   double stopDist=atr*InpStopATR;
   double stopMin=(MarketInfo(sym,MODE_STOPLEVEL)+MarketInfo(sym,MODE_FREEZELEVEL))*point+2*point;
   if(stopDist<stopMin) stopDist=stopMin;
   double entry=(cmd==OP_BUY?ask:bid); int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double sl=NormalizeDouble(cmd==OP_BUY?entry-stopDist:entry+stopDist,digits);
   double tp=NormalizeDouble(cmd==OP_BUY?entry+stopDist*InpRewardRisk:entry-stopDist*InpRewardRisk,digits);

   double perTradeCap=MathMin(InpMaxRiskPerTradeUSD,InpReferenceCapitalUSD*InpRiskPctPerTrade/100.0);
   double maxRisk=InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0;
   double currentRisk=CurrentPlannedRiskUSD();
   double remainingRisk=maxRisk-currentRisk;
   if(currentRisk>=InpReferenceCapitalUSD || remainingRisk<=0.01)
   {
      g_scanRiskRejected++;
      Print("AGGREGATE_RISK_AUDIT | symbol=",sym," | openRiskUSD=",DoubleToString(currentRisk,2),
         " | remainingRiskUSD=",DoubleToString(remainingRisk,2)," | capUSD=",DoubleToString(maxRisk,2),
         " | warning=VERIFY_OPEN_ORDER_TICKVALUE_AND_CONTRACT_UNITS");
      LogReject(sym,"AGGREGATE_RISK_CAP"); return(false);
   }
   double riskBudget=MathMin(perTradeCap,remainingRisk);
   double lots=LotsForRiskBudget(sym,stopDist,riskBudget);
   if(lots<=0)
   {
      g_scanRiskRejected++;
      Print("RISK_BUDGET_AUDIT | symbol=",sym," | perTradeCapUSD=",DoubleToString(perTradeCap,2),
         " | remainingAggregateUSD=",DoubleToString(remainingRisk,2)," | minimumLotMayExceedBudget=true");
      LogReject(sym,"RISK_OR_MINIMUM_LOT_EXCEEDS_AVAILABLE_BUDGET"); return(false);
   }
   double risk=EstimateRiskUSD(sym,lots,stopDist);
   if(risk>perTradeCap+0.02 || risk>remainingRisk+0.02)
   {
      g_scanRiskRejected++;
      Print("AGGREGATE_RISK_AUDIT | symbol=",sym," | openRiskUSD=",DoubleToString(currentRisk,2),
         " | candidateRiskUSD=",DoubleToString(risk,2)," | perTradeCapUSD=",DoubleToString(perTradeCap,2),
         " | remainingRiskUSD=",DoubleToString(remainingRisk,2));
      LogReject(sym,"RISK_BUDGET_RECHECK_FAILED"); return(false);
   }

   // Spread/ATR up to the hard ceiling is a graded cost penalty, not a second veto.
   // The score ranks candidates; it is not a calibrated probability of profit.
   double voteCoverage=100.0*activeVotes/MODEL_COUNT;
   double spreadQuality=100.0-MathMin(100.0,spread/MathMax(1,InpMaxSpreadPoints)*100.0);
   double spreadATRQuality=100.0;
   if(InpMaxSpreadToATRPercent>0 && spreadToATRPercent>InpMaxSpreadToATRPercent)
      spreadATRQuality=100.0*MathMax(0.0,1.0-(spreadToATRPercent-InpMaxSpreadToATRPercent)/
         MathMax(0.01,InpHardMaxSpreadToATRPercent-InpMaxSpreadToATRPercent));
   double riskQuality=100.0-MathMin(100.0,risk/MathMax(0.01,perTradeCap)*100.0);
   double marginStrength=100.0*margin/MODEL_COUNT;
   double score=directionalPct*0.40+voteCoverage*0.25+marginStrength*0.15+
      spreadQuality*0.05+spreadATRQuality*0.10+riskQuality*0.05;
   c.symbol=sym; c.cmd=cmd; c.buyVotes=buys; c.sellVotes=sells; c.activeVotes=activeVotes;
   c.margin=margin; c.directionalPct=directionalPct; c.spreadPoints=spread;
   c.entry=entry; c.sl=sl; c.tp=tp; c.lots=lots; c.riskUSD=risk; c.atr=atr; c.stopDist=stopDist; c.score=score;
   Print("CANDIDATE_QUALIFIED | symbol=",sym," | side=",(cmd==OP_BUY?"BUY":"SELL"),
      " | score=",DoubleToString(score,2)," | activeVotes=",activeVotes,
      " | directionalPct=",DoubleToString(directionalPct,1)," | margin=",margin,
      " | spreadToATRPercent=",DoubleToString(spreadToATRPercent,2),
      " | riskUSD=",DoubleToString(risk,2)," | riskCapUSD=",DoubleToString(perTradeCap,2));
   return(true);
}
void ExecuteCandidate(Candidate &c)
{
   int digits=(int)MarketInfo(c.symbol,MODE_DIGITS);
   if(!InpEnableTrading)
   { Print("DRY_RUN_BEST_CANDIDATE | symbol=",c.symbol," | side=",(c.cmd==OP_BUY?"BUY":"SELL"),
      " | score=",DoubleToString(c.score,2)," | activeVotes=",c.activeVotes,
      " | directionPct=",DoubleToString(c.directionalPct,1),"% | lots=",DoubleToString(c.lots,2),
      " | riskUSD=",DoubleToString(c.riskUSD,2)," | entry=",DoubleToString(c.entry,digits),
      " | SL=",DoubleToString(c.sl,digits)," | TP=",DoubleToString(c.tp,digits)," | reason=TRADING_DISABLED"); return; }
   if(!IsTradeAllowed() || !MarketInfo(c.symbol,MODE_TRADEALLOWED))
   { LogReject(c.symbol,"TRADING_NOT_ALLOWED"); return; }
   if(CountOpenPositions()>=InpMaxOpenPositions ||
      CurrentPlannedRiskUSD()+c.riskUSD>InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0+0.01)
   { LogReject(c.symbol,"RISK_OR_POSITION_CAP_CHANGED_BEFORE_SEND"); return; }
   ResetLastError();
   int ticket=OrderSend(c.symbol,c.cmd,c.lots,c.entry,InpSlippagePoints,c.sl,c.tp,
      "Bitey Committee Selection v1.5",InpMagic,0,clrNONE);
   if(ticket<0) { Print("ORDER_REJECTED | symbol=",c.symbol," | side=",(c.cmd==OP_BUY?"BUY":"SELL"),
      " | error=",GetLastError()," | lots=",DoubleToString(c.lots,2)); return; }
   Print("ORDER_ACCEPTED | ticket=",ticket," | symbol=",c.symbol," | side=",
      (c.cmd==OP_BUY?"BUY":"SELL")," | score=",DoubleToString(c.score,2),
      " | activeVotes=",c.activeVotes," | lots=",DoubleToString(c.lots,2),
      " | plannedRiskUSD=",DoubleToString(c.riskUSD,2)," | SL=",DoubleToString(c.sl,digits),
      " | TP=",DoubleToString(c.tp,digits));
}

// Manage only this EA's market orders. SL can only tighten, never widen.
void ManageOpenPositions()
{
   if(!InpEnableBreakEven && !InpEnableATRTrailing) return;
   for(int pos=OrdersTotal()-1;pos>=0;pos--)
   {
      if(!OrderSelect(pos,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;

      string sym=OrderSymbol();
      double point=MarketInfo(sym,MODE_POINT);
      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      if(point<=0) continue;
      double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
      if(atr<=0) continue;
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      if(bid<=0 || ask<=0) continue;

      double openPrice=OrderOpenPrice();
      double oldSL=OrderStopLoss();
      double candidate=oldSL;
      bool hasCandidate=(oldSL>0);
      double favorable=(type==OP_BUY ? bid-openPrice : openPrice-ask);
      if(favorable<=0) continue;

      if(InpEnableBreakEven && InpBreakEvenTriggerATR>0 && favorable>=atr*InpBreakEvenTriggerATR)
      {
         double be=(type==OP_BUY ? openPrice+InpBreakEvenOffsetPoints*point : openPrice-InpBreakEvenOffsetPoints*point);
         if(!hasCandidate) { candidate=be; hasCandidate=true; }
         else if(type==OP_BUY && be>candidate) candidate=be;
         else if(type==OP_SELL && be<candidate) candidate=be;
      }

      if(InpEnableATRTrailing && InpTrailingStartATR>0 && InpTrailingDistanceATR>0 && favorable>=atr*InpTrailingStartATR)
      {
         double trail=(type==OP_BUY ? bid-atr*InpTrailingDistanceATR : ask+atr*InpTrailingDistanceATR);
         if(!hasCandidate) { candidate=trail; hasCandidate=true; }
         else if(type==OP_BUY && trail>candidate) candidate=trail;
         else if(type==OP_SELL && trail<candidate) candidate=trail;
      }
      if(!hasCandidate) continue;

      double minDistance=(MarketInfo(sym,MODE_STOPLEVEL)+MarketInfo(sym,MODE_FREEZELEVEL))*point+2*point;
      if(type==OP_BUY)
      {
         double maxAllowed=bid-minDistance;
         if(candidate>maxAllowed) candidate=maxAllowed;
         candidate=NormalizeDouble(candidate,digits);
         if(candidate<=0 || (oldSL>0 && candidate<=oldSL+InpTrailingStepPoints*point)) continue;
      }
      else
      {
         double minAllowed=ask+minDistance;
         if(candidate<minAllowed) candidate=minAllowed;
         candidate=NormalizeDouble(candidate,digits);
         if(candidate<=0 || (oldSL>0 && candidate>=oldSL-InpTrailingStepPoints*point)) continue;
      }

      // Final guard: never widen the original/current stop.
      if(oldSL>0 && type==OP_BUY && candidate<oldSL) continue;
      if(oldSL>0 && type==OP_SELL && candidate>oldSL) continue;
      ResetLastError();
      bool modified=OrderModify(OrderTicket(),openPrice,candidate,OrderTakeProfit(),0,clrNONE);
      if(modified)
         Print("PROFIT_PROTECTION_MODIFIED | ticket=",OrderTicket()," | symbol=",sym,
               " | side=",(type==OP_BUY?"BUY":"SELL")," | oldSL=",DoubleToString(oldSL,digits),
               " | newSL=",DoubleToString(candidate,digits)," | entry=",DoubleToString(openPrice,digits),
               " | favorableMove=",DoubleToString(favorable,digits)," | ATR=",DoubleToString(atr,digits),
               " | TP_unchanged=",DoubleToString(OrderTakeProfit(),digits));
      else
         Print("PROFIT_PROTECTION_DEFERRED | ticket=",OrderTicket()," | symbol=",sym,
               " | candidateSL=",DoubleToString(candidate,digits)," | error=",GetLastError());
   }
}

void ScoreEnsemble(string sym,int &buyVotes,int &sellVotes)
{
   buyVotes=0; sellVotes=0;
   double c1=iClose(sym,InpSignalTF,1),c2=iClose(sym,InpSignalTF,2);
   if(c1<=0 || c2<=0) return;
   int periods[9]={5,8,10,13,21,34,50,89,144};
   for(int i=0;i<8;i++)
   {
      double fast=iMA(sym,InpSignalTF,periods[i],0,MODE_EMA,PRICE_CLOSE,1);
      double slow=iMA(sym,InpSignalTF,periods[i+1],0,MODE_EMA,PRICE_CLOSE,1);
      Vote(fast>slow && c1>fast,fast<slow && c1<fast,buyVotes,sellVotes);
   }
   int rp[8]={5,7,9,11,14,18,21,28};
   for(int j=0;j<8;j++)
   {
      double r=iRSI(sym,InpSignalTF,rp[j],PRICE_CLOSE,1);
      double prev=iRSI(sym,InpSignalTF,rp[j],PRICE_CLOSE,2);
      Vote(r>52 && r>prev && r<75,r<48 && r<prev && r>25,buyVotes,sellVotes);
   }
   int lb[8]={5,7,9,12,15,18,22,30};
   for(int k=0;k<8;k++)
   {
      int hi=iHighest(sym,InpSignalTF,MODE_HIGH,lb[k],2);
      int lo=iLowest(sym,InpSignalTF,MODE_LOW,lb[k],2);
      double hh=(hi>=0?iHigh(sym,InpSignalTF,hi):0);
      double ll=(lo>=0?iLow(sym,InpSignalTF,lo):0);
      Vote(hh>0 && c1>hh && c1>c2,ll>0 && c1<ll && c1<c2,buyVotes,sellVotes);
   }
   int bp[8]={8,10,12,14,18,20,24,30};
   for(int m=0;m<8;m++)
   {
      double upper=iBands(sym,InpSignalTF,bp[m],2.0,0,PRICE_CLOSE,MODE_UPPER,1);
      double lower=iBands(sym,InpSignalTF,bp[m],2.0,0,PRICE_CLOSE,MODE_LOWER,1);
      double c2b=iClose(sym,InpSignalTF,2);
      Vote(c2b<lower && c1>lower && c1>c2b,
           c2b>upper && c1<upper && c1<c2b,buyVotes,sellVotes);
   }
}

void Vote(bool buy,bool sell,int &buyVotes,int &sellVotes)
{
   if(buy && !sell) buyVotes++;
   else if(sell && !buy) sellVotes++;
}

bool HasPositionForSymbol(string sym)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         if(OrderMagicNumber()==InpMagic && OrderSymbol()==sym &&
            (OrderType()==OP_BUY || OrderType()==OP_SELL)) return(true);
   return(false);
}

int CountOpenPositions()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         if(OrderMagicNumber()==InpMagic && (OrderType()==OP_BUY || OrderType()==OP_SELL)) n++;
   return(n);
}

double CurrentPlannedRiskUSD()
{
   double total=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(OrderStopLoss()<=0) return(InpReferenceCapitalUSD); // fail closed if risk unknown
      total+=EstimateRiskUSD(OrderSymbol(),OrderLots(),MathAbs(OrderOpenPrice()-OrderStopLoss()));
   }
   return(total);
}

double LotsForRiskBudget(string sym,double stopDist,double riskMoney)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE),ts=MarketInfo(sym,MODE_TICKSIZE)*MarketInfo(sym,MODE_POINT);
   double minLot=MarketInfo(sym,MODE_MINLOT),maxLot=MarketInfo(sym,MODE_MAXLOT),step=MarketInfo(sym,MODE_LOTSTEP);
   if(riskMoney<=0 || tv<=0 || ts<=0 || stopDist<=0 || minLot<=0 || maxLot<minLot || step<=0) return(0);
   double lossPerLot=(stopDist/ts)*tv;
   if(lossPerLot<=0) return(0);
   double lots=MathFloor((riskMoney/lossPerLot)/step+1e-9)*step;
   lots=NormalizeDouble(lots,LotDigits(step));
   if(lots<minLot || lots>maxLot || EstimateRiskUSD(sym,lots,stopDist)>riskMoney+0.02) return(0);
   return(lots);
}

double EstimateRiskUSD(string sym,double lots,double stopDist)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE),ts=MarketInfo(sym,MODE_TICKSIZE)*MarketInfo(sym,MODE_POINT);
   if(tv<=0 || ts<=0 || lots<=0 || stopDist<=0) return(1.0e12);
   return((stopDist/ts)*tv*lots);
}

int LotDigits(double step)
{
   if(step>=1.0) return(0);
   if(step>=0.1) return(1);
   if(step>=0.01) return(2);
   return(3);
}

void LogReject(string sym,string reason)
{
   Print("SYMBOL_REJECT | symbol=",sym," | reason=",reason);
}
//+------------------------------------------------------------------+