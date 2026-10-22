//+------------------------------------------------------------------+
//| Bitey_Ensemble_Scalper_MultiAsset_v1_2_2_Adaptive_SLTP_RiskBudget8 |
//| Original 32-variant committee with adaptive SL/TP management      |
//| Trading disabled by default. Not performance-validated.           |
//+------------------------------------------------------------------+
#property strict
#property version "1.28"
#property description "RiskBudget8: 32-variant ensemble, adaptive SL/TP, net-profit-after-costs close"

input string InpSymbolsCSV = ""; // Blank scans symbols in Market Watch
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_M5;
input int InpMagic = 21102026;
input double InpReferenceCapitalUSD = 500.0;
input double InpRiskPctPerTrade = 1.0;
input double InpMaxAggregateRiskPct = 2.0;
input int InpMaxOpenPositions = 3;
input int InpMinActiveVotes = 8;       // At least 8 of 32 variants must emit a directional vote
input double InpMinDirectionalPct = 70.0; // Winning side as % of active votes
input int InpMinVoteMargin = 4;          // Minimum absolute BUY/SELL vote difference
input int InpATRPeriod = 14;
input double InpStopATR = 2.0;
input double InpRewardRisk = 1.5;
input bool InpEnableAdaptiveExits = true;
input bool InpEnableNetProfitClose = true; // Close when net profit after costs reaches target
input double InpNetProfitTargetAfterCosts = 1.00; // Required net profit after costs, in account currency
input double InpEstimatedCloseCostsReserve = 0.00; // Extra reserve for closing commission/fees not yet reflected by MT4
input double InpBreakEvenTriggerATR = 1.0; // Protect entry after favorable movement
input double InpTrailStartATR = 1.5; // Start trailing only after this favorable move
input double InpTrailDistanceATR = 1.5; // ATR distance for protective trailing stop
input double InpTPExpandTriggerATR = 1.0; // Do not adapt TP before this favorable move
input double InpTPExpandBufferATR = 1.5; // Keep TP ahead of price during a strong trend
input double InpTPExpandADXMin = 22.0; // Extend TP only when directional strength is adequate
input double InpTPMaxDistanceATR = 6.0; // Hard cap on TP distance from entry
input int InpMaxSpreadPoints = 80;
input int InpSlippagePoints = 20;
input int InpMinBars = 250;
input bool InpAllowBuy = true;
input bool InpAllowSell = true;
input bool InpOnePositionPerSymbol = true;
input bool InpEnableTrading = true; // User requested execution for qualifying signals; validate on demo first
input bool InpLogVotes = true;

#define MODEL_COUNT 32
#define MAX_SYMBOLS 128
string g_symbols[MAX_SYMBOLS];
int g_symbolCount=0;
datetime g_lastBar[MAX_SYMBOLS];

int OnInit()
{
   ParseSymbols();
   if(g_symbolCount<=0) { Print("INIT_ERROR | no symbols found"); return(INIT_FAILED); }
   Print("BITEY_ENSEMBLE_INIT | version=1.26 | symbols=",g_symbolCount," | models=",MODEL_COUNT,
         " | referenceCapital=",DoubleToString(InpReferenceCapitalUSD,2),
         " | riskPct=",DoubleToString(InpRiskPctPerTrade,2),
         " | tradingEnabled=",InpEnableTrading);
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(InpEnableAdaptiveExits || InpEnableNetProfitClose) ManageAdaptiveExits();
   for(int i=0;i<g_symbolCount;i++)
   {
      string sym=g_symbols[i];
      if(!SymbolSelect(sym,true)) { LogReject(sym,"SYMBOL_SELECT_FAILED"); continue; }
      if(iBars(sym,InpSignalTF)<InpMinBars) { LogReject(sym,"INSUFFICIENT_HISTORY"); continue; }
      datetime bt=iTime(sym,InpSignalTF,0);
      if(bt<=0 || bt==g_lastBar[i]) continue;
      g_lastBar[i]=bt;
      EvaluateSymbol(sym);
   }
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

void EvaluateSymbol(string sym)
{
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
   double point=MarketInfo(sym,MODE_POINT);
   if(bid<=0 || ask<=0 || point<=0) { LogReject(sym,"INVALID_QUOTES_OR_POINT"); return; }
   double spread=(ask-bid)/point;
   if(spread>InpMaxSpreadPoints) { LogReject(sym,"SPREAD_LIMIT"); return; }
   if(InpOnePositionPerSymbol && HasPositionForSymbol(sym)) { LogReject(sym,"POSITION_ALREADY_OPEN"); return; }
   if(CountOpenPositions()>=InpMaxOpenPositions) { LogReject(sym,"MAX_OPEN_POSITIONS"); return; }

   int buys=0,sells=0; ScoreEnsemble(sym,buys,sells);
   int activeVotes=buys+sells;
   int winningVotes=MathMax(buys,sells);
   double directionalPct=(activeVotes>0?100.0*winningVotes/activeVotes:0.0);
   int margin=MathAbs(buys-sells);
   if(InpLogVotes) Print("ENSEMBLE_AUDIT | symbol=",sym," | buyVotes=",buys,
                         " | sellVotes=",sells," | activeVotes=",activeVotes,
                         " | directionalPct=",DoubleToString(directionalPct,1), " | margin=",margin,
                         " | spreadPoints=",DoubleToString(spread,1));
   int cmd=-1;
   if(activeVotes<InpMinActiveVotes)
   { LogReject(sym,"INSUFFICIENT_ACTIVE_VOTES"); return; }
   if(directionalPct<InpMinDirectionalPct)
   { LogReject(sym,"DIRECTIONAL_PERCENT_BELOW_MIN"); return; }
   if(margin<InpMinVoteMargin)
   { LogReject(sym,"VOTE_MARGIN_BELOW_MIN"); return; }
   if(InpAllowBuy && buys>sells) cmd=OP_BUY;
   else if(InpAllowSell && sells>buys) cmd=OP_SELL;
   if(cmd<0) { LogReject(sym,"ENSEMBLE_NO_CLEAR_CONSENSUS"); return; }

   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(atr<=0) { LogReject(sym,"ATR_UNAVAILABLE"); return; }
   // Build stops against the executable side of the quote, not entry alone.
   // For market orders BUY stops are validated against Bid; SELL stops against Ask.
   // Broker stop-level data can be dynamic (MODE_STOPLEVEL may report zero), so use
   // a small point buffer and fail closed if the final normalized prices are invalid.
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double stopLevelPoints=MarketInfo(sym,MODE_STOPLEVEL);
   double freezeLevelPoints=MarketInfo(sym,MODE_FREEZELEVEL);
   double brokerMinDistance=(MathMax(stopLevelPoints,freezeLevelPoints)+2.0)*point;
   double spreadPrice=ask-bid;
   double stopDist=MathMax(atr*InpStopATR,spreadPrice+brokerMinDistance);
   double targetDist=MathMax(stopDist*InpRewardRisk,spreadPrice+brokerMinDistance);
   double entry=(cmd==OP_BUY?ask:bid);
   double sl=NormalizeDouble(cmd==OP_BUY?entry-stopDist:entry+stopDist,digits);
   double tp=NormalizeDouble(cmd==OP_BUY?entry+targetDist:entry-targetDist,digits);
   // Recalculate actual stop distance after normalization; use it for position sizing.
   stopDist=MathAbs(entry-sl);
   bool stopsValid=false;
   if(cmd==OP_BUY)
      stopsValid=(sl>0 && tp>0 && sl<bid-brokerMinDistance*0.5 && tp>bid+brokerMinDistance*0.5);
   else
      stopsValid=(sl>ask+brokerMinDistance*0.5 && tp<ask-brokerMinDistance*0.5);
   if(!stopsValid)
   {
      Print("STOP_LEVEL_PREFLIGHT_REJECT | symbol=",sym,
         " | side=",(cmd==OP_BUY?"BUY":"SELL"),
         " | bid=",DoubleToString(bid,digits)," | ask=",DoubleToString(ask,digits),
         " | SL=",DoubleToString(sl,digits)," | TP=",DoubleToString(tp,digits),
         " | stopLevelPoints=",DoubleToString(stopLevelPoints,1),
         " | freezeLevelPoints=",DoubleToString(freezeLevelPoints,1),
         " | spreadPoints=",DoubleToString(spread,1),
         " | brokerMinDistance=",DoubleToString(brokerMinDistance,digits),
         " | reason=SL_TP_TOO_CLOSE_OR_WRONG_SIDE");
      LogReject(sym,"INVALID_STOPS_PREFLIGHT");
      return;
   }
   double maxRisk=InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0;
   double currentRisk=CurrentPlannedRiskUSD();
   double remainingRisk=maxRisk-currentRisk;
   double perTradeBudget=InpReferenceCapitalUSD*InpRiskPctPerTrade/100.0;
   if(remainingRisk<=0.01)
   {
      Print("RISK_BUDGET_REJECT_DETAIL | symbol=",sym,
         " | reason=NO_AGGREGATE_RISK_REMAINING",
         " | currentRisk=",DoubleToString(currentRisk,2),
         " | cap=",DoubleToString(maxRisk,2),
         " | remaining=",DoubleToString(remainingRisk,2),
         " | accountCurrency=",AccountCurrency());
      LogReject(sym,"AGGREGATE_RISK_CAP"); return;
   }
   double effectiveRiskBudget=MathMin(perTradeBudget,remainingRisk);
   double lots=LotsForRisk(sym,stopDist,effectiveRiskBudget);
   if(lots<=0)
   {
      Print("RISK_BUDGET_NO_VALID_LOT | symbol=",sym,
         " | reason=MIN_LOT_OR_CONTRACT_EXCEEDS_REMAINING_BUDGET",
         " | effectiveRiskBudget=",DoubleToString(effectiveRiskBudget,2),
         " | remainingAggregateRisk=",DoubleToString(remainingRisk,2),
         " | accountCurrency=",AccountCurrency());
      LogReject(sym,"RISK_OR_LOT_CALCULATION_FAILED"); return;
   }
   double risk=EstimateRiskUSD(sym,lots,stopDist);
   Print("RISK_BUDGET_AUDIT | symbol=",sym,
         " | accountCurrency=",AccountCurrency(),
         " | referenceCapitalUSD=",DoubleToString(InpReferenceCapitalUSD,2),
         " | riskPerTradeBudget=",DoubleToString(perTradeBudget,2),
         " | effectiveRiskBudget=",DoubleToString(effectiveRiskBudget,2),
         " | candidateRiskTickValueCurrency=",DoubleToString(risk,2),
         " | currentOpenRiskTickValueCurrency=",DoubleToString(currentRisk,2),
         " | aggregateCap=",DoubleToString(maxRisk,2),
         " | remainingBeforeCandidate=",DoubleToString(remainingRisk,2),
         " | projectedTotal=",DoubleToString(currentRisk+risk,2));
   if(currentRisk+risk>maxRisk+0.01)
   {
      Print("RISK_BUDGET_REJECT_DETAIL | symbol=",sym,
         " | reason=AGGREGATE_RISK_CAP",
         " | currentRisk=",DoubleToString(currentRisk,2),
         " | candidateRisk=",DoubleToString(risk,2),
         " | cap=",DoubleToString(maxRisk,2),
         " | excess=",DoubleToString(currentRisk+risk-maxRisk,2),
         " | accountCurrency=",AccountCurrency());
      LogReject(sym,"AGGREGATE_RISK_CAP"); return;
   }

   if(!InpEnableTrading)
   {
      Print("DRY_RUN_CANDIDATE | symbol=",sym," | side=",(cmd==OP_BUY?"BUY":"SELL"),
            " | activeVotes=",activeVotes," | directionPct=",DoubleToString(directionalPct,1),"% | votes=",MathMax(buys,sells),"/",MODEL_COUNT," | lots=",DoubleToString(lots,2),
            " | riskUSD=",DoubleToString(risk,2)," | entry=",DoubleToString(entry,digits),
            " | SL=",DoubleToString(sl,digits)," | TP=",DoubleToString(tp,digits),
            " | reason=TRADING_DISABLED");
      return;
   }
   if(!IsTradeAllowed() || !MarketInfo(sym,MODE_TRADEALLOWED))
   { LogReject(sym,"TRADING_NOT_ALLOWED"); return; }

   ResetLastError();
   int ticket=OrderSend(sym,cmd,lots,entry,InpSlippagePoints,sl,tp,"Bitey Ensemble v1.2.2",InpMagic,0,clrNONE);
   if(ticket<0)
   {
      int orderError=GetLastError();
      Print("ORDER_REJECTED | symbol=",sym," | side=",(cmd==OP_BUY?"BUY":"SELL"),
            " | error=",orderError," | lots=",DoubleToString(lots,2),
            " | entry=",DoubleToString(entry,digits),
            " | bid=",DoubleToString(MarketInfo(sym,MODE_BID),digits),
            " | ask=",DoubleToString(MarketInfo(sym,MODE_ASK),digits),
            " | SL=",DoubleToString(sl,digits)," | TP=",DoubleToString(tp,digits),
            " | stopLevelPoints=",DoubleToString(MarketInfo(sym,MODE_STOPLEVEL),1),
            " | freezeLevelPoints=",DoubleToString(MarketInfo(sym,MODE_FREEZELEVEL),1));
      if(orderError==130)
         Print("ORDER_ERROR_130_DIAGNOSTIC | symbol=",sym,
            " | reason=INVALID_STOPS_RECHECK_QUOTE_STOPLEVEL_TICKSIZE_OR_BROKER_DYNAMIC_RULE",
            " | action=NO_AUTOMATIC_WIDER_STOP_RETRY");
      return;
   }
   Print("ORDER_ACCEPTED | ticket=",ticket," | symbol=",sym," | side=",
         (cmd==OP_BUY?"BUY":"SELL")," | lots=",DoubleToString(lots,2),
         " | plannedRiskUSD=",DoubleToString(risk,2)," | SL=",DoubleToString(sl,digits),
         " | TP=",DoubleToString(tp,digits));
}

// Adaptive exit management only. The original 32-model committee, entry filters,
// position sizing, candidate evaluation and order entry remain unchanged.
void ManageAdaptiveExits()
{
   for(int pos=OrdersTotal()-1;pos>=0;pos--)
   {
      if(!OrderSelect(pos,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;

      // Close this EA's market order when reported commission/swap are covered,
      // the optional closing-cost reserve is covered, and net profit reaches target.
      double netProfitAfterReportedCosts=OrderProfit()+OrderSwap()+OrderCommission();
      double netProfitAfterCostsReserve=netProfitAfterReportedCosts-InpEstimatedCloseCostsReserve;
      if(InpEnableNetProfitClose && netProfitAfterCostsReserve>=InpNetProfitTargetAfterCosts)
      {
         string closeSymbol=OrderSymbol();
         int closeTicket=OrderTicket();
         double closeLots=OrderLots();
         double closePrice=(type==OP_BUY?MarketInfo(closeSymbol,MODE_BID):MarketInfo(closeSymbol,MODE_ASK));
         int closeDigits=(int)MarketInfo(closeSymbol,MODE_DIGITS);
         if(closePrice>0)
         {
            closePrice=NormalizeDouble(closePrice,closeDigits);
            ResetLastError();
            if(OrderClose(closeTicket,closeLots,closePrice,InpSlippagePoints,clrNONE))
            {
               Print("NET_PROFIT_TARGET_CLOSE | ticket=",closeTicket,
                     " | symbol=",closeSymbol,
                     " | side=",(type==OP_BUY?"BUY":"SELL"),
                     " | lots=",DoubleToString(closeLots,2),
                     " | netProfitAfterReportedCosts=",DoubleToString(netProfitAfterReportedCosts,2),
                     " | closeCostsReserve=",DoubleToString(InpEstimatedCloseCostsReserve,2),
                     " | netAfterReserve=",DoubleToString(netProfitAfterCostsReserve,2),
                     " | target=",DoubleToString(InpNetProfitTargetAfterCosts,2),
                     " | closePrice=",DoubleToString(closePrice,closeDigits));
            }
            else
            {
               int closeError=GetLastError();
               Print("NET_PROFIT_TARGET_CLOSE_FAILED | ticket=",closeTicket,
                     " | symbol=",closeSymbol,
                     " | netProfitAfterReportedCosts=",DoubleToString(netProfitAfterReportedCosts,2),
                     " | closeCostsReserve=",DoubleToString(InpEstimatedCloseCostsReserve,2),
                     " | netAfterReserve=",DoubleToString(netProfitAfterCostsReserve,2),
                     " | target=",DoubleToString(InpNetProfitTargetAfterCosts,2),
                     " | error=",closeError);
            }
         }
         else
         {
            Print("NET_PROFIT_TARGET_CLOSE_FAILED | ticket=",closeTicket,
                  " | symbol=",closeSymbol,
                  " | reason=INVALID_CLOSE_PRICE");
         }
         continue;
      }

      if(!InpEnableAdaptiveExits) continue;

      string sym=OrderSymbol();
      double point=MarketInfo(sym,MODE_POINT);
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      if(point<=0 || bid<=0 || ask<=0) continue;
      double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
      if(atr<=0) continue;

      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      double entry=OrderOpenPrice();
      double marketPrice=(type==OP_BUY?bid:ask);
      double favorable=(type==OP_BUY?marketPrice-entry:entry-marketPrice);
      double oldSL=OrderStopLoss(), oldTP=OrderTakeProfit();
      double newSL=oldSL, newTP=oldTP;
      double minDistance=(MarketInfo(sym,MODE_STOPLEVEL)+MarketInfo(sym,MODE_FREEZELEVEL))*point+2.0*point;

      // Break-even protection: only tighten the stop; never move it farther from price risk.
      if(InpBreakEvenTriggerATR>0 && favorable>=atr*InpBreakEvenTriggerATR)
      {
         double be=(type==OP_BUY?entry+point:entry-point);
         if(type==OP_BUY)
         {
            if((newSL<=0 || be>newSL) && be<bid-minDistance) newSL=be;
         }
         else
         {
            if((newSL<=0 || be<newSL) && be>ask+minDistance) newSL=be;
         }
      }

      // ATR trailing: the stop may only move in the profit-protecting direction.
      if(InpTrailStartATR>0 && InpTrailDistanceATR>0 && favorable>=atr*InpTrailStartATR)
      {
         double trail=(type==OP_BUY?bid-atr*InpTrailDistanceATR:ask+atr*InpTrailDistanceATR);
         if(type==OP_BUY)
         {
            if(trail>newSL && trail<bid-minDistance) newSL=trail;
         }
         else
         {
            if((newSL<=0 || trail<newSL) && trail>ask+minDistance) newSL=trail;
         }
      }
      newSL=(newSL>0?NormalizeDouble(newSL,digits):0);
      bool slImproves=false;
      if(type==OP_BUY) slImproves=(newSL>0 && (oldSL<=0 || newSL>oldSL+point*0.5));
      else slImproves=(newSL>0 && (oldSL<=0 || newSL<oldSL-point*0.5));

      // Adaptive TP: when price approaches the current target in a strong trend,
      // extend it to maintain an ATR buffer. It only moves outward and is capped.
      bool tpImproves=false;
      double adx=iADX(sym,InpSignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
      if(oldTP>0 && InpTPExpandTriggerATR>0 && InpTPExpandBufferATR>0 &&
         InpTPMaxDistanceATR>0 && adx>=InpTPExpandADXMin &&
         favorable>=atr*InpTPExpandTriggerATR)
      {
         double currentTargetDistance=MathAbs(oldTP-entry);
         double remainingToTarget=(type==OP_BUY?oldTP-bid:ask-oldTP);
         if(remainingToTarget<=atr*InpTPExpandBufferATR)
         {
            double desiredDistance=MathMin(atr*InpTPMaxDistanceATR,
               MathMax(currentTargetDistance,favorable+atr*InpTPExpandBufferATR));
            double proposed=(type==OP_BUY?entry+desiredDistance:entry-desiredDistance);
            proposed=NormalizeDouble(proposed,digits);
            if(type==OP_BUY)
            {
               if(proposed>oldTP+point && proposed>ask+minDistance) { newTP=proposed; tpImproves=true; }
            }
            else
            {
               if(proposed<oldTP-point && proposed<bid-minDistance) { newTP=proposed; tpImproves=true; }
            }
         }
      }

      if(!slImproves && !tpImproves) continue;
      // Preserve existing SL/TP values whenever that side did not improve.
      double finalSL=(slImproves?newSL:oldSL);
      double finalTP=(tpImproves?newTP:oldTP);
      ResetLastError();
      bool modified=OrderModify(OrderTicket(),entry,finalSL,finalTP,0,clrNONE);
      if(modified)
      {
         if(slImproves)
            Print("ADAPTIVE_SL_TIGHTENED | ticket=",OrderTicket()," | symbol=",sym,
               " | oldSL=",DoubleToString(oldSL,digits)," | newSL=",DoubleToString(finalSL,digits),
               " | favorableMove=",DoubleToString(favorable,digits)," | ATR=",DoubleToString(atr,digits),
               " | neverWidened=true");
         if(tpImproves)
            Print("ADAPTIVE_TP_EXTENDED | ticket=",OrderTicket()," | symbol=",sym,
               " | oldTP=",DoubleToString(oldTP,digits)," | newTP=",DoubleToString(finalTP,digits),
               " | ADX=",DoubleToString(adx,2)," | favorableMove=",DoubleToString(favorable,digits),
               " | maxDistanceATR=",DoubleToString(InpTPMaxDistanceATR,2));
      }
      else
         Print("ADAPTIVE_EXIT_MODIFY_FAILED | ticket=",OrderTicket()," | symbol=",sym,
            " | error=",GetLastError()," | SLchange=",slImproves," | TPchange=",tpImproves);
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
      if(OrderStopLoss()<=0)
      {
         Print("OPEN_RISK_AUDIT | ticket=",OrderTicket()," | symbol=",OrderSymbol(),
            " | lots=",DoubleToString(OrderLots(),4)," | reason=OPEN_POSITION_WITHOUT_SL",
            " | failClosedRisk=",DoubleToString(InpReferenceCapitalUSD,2));
         return(InpReferenceCapitalUSD); // fail closed if risk unknown
      }
      double openPrice=OrderOpenPrice();
      double stopLoss=OrderStopLoss();
      double stopDistance=0.0;
      // Count only adverse distance from entry. A stop beyond breakeven protects profit,
      // so it must not be miscounted as additional open loss risk.
      if(OrderType()==OP_BUY) stopDistance=MathMax(0.0,openPrice-stopLoss);
      else stopDistance=MathMax(0.0,stopLoss-openPrice);
      // A stop at or beyond breakeven leaves no adverse entry-to-stop distance.
      // Do not pass zero distance into EstimateRiskUSD(): its invalid-input sentinel
      // (1e12) is reserved for unknown/invalid risk calculations, not protected trades.
      double positionRisk=0.0;
      if(stopDistance>0.0)
         positionRisk=EstimateRiskUSD(OrderSymbol(),OrderLots(),stopDistance);
      Print("OPEN_RISK_AUDIT | ticket=",OrderTicket()," | symbol=",OrderSymbol(),
         " | type=",(OrderType()==OP_BUY?"BUY":"SELL"),
         " | lots=",DoubleToString(OrderLots(),4)," | openPrice=",DoubleToString(openPrice,8),
         " | stopLoss=",DoubleToString(stopLoss,8)," | adverseStopDistance=",DoubleToString(stopDistance,8),
         " | tickValue=",DoubleToString(MarketInfo(OrderSymbol(),MODE_TICKVALUE),8),
         " | tickSize=",DoubleToString(MarketInfo(OrderSymbol(),MODE_TICKSIZE),8),
         " | estimatedRiskTickValueCurrency=",DoubleToString(positionRisk,2),
         " | riskClassification=",(stopDistance>0.0?"ADVERSE_STOP_RISK":"STOP_AT_OR_BEYOND_BREAKEVEN"),
         " | accountCurrency=",AccountCurrency());
      total+=positionRisk;
   }
   return(total);
}

double LotsForRisk(string sym,double stopDist,double riskMoney)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE),ts=MarketInfo(sym,MODE_TICKSIZE);
   double minLot=MarketInfo(sym,MODE_MINLOT),maxLot=MarketInfo(sym,MODE_MAXLOT),step=MarketInfo(sym,MODE_LOTSTEP);
   if(riskMoney<=0 || tv<=0 || ts<=0 || stopDist<=0 || minLot<=0 || maxLot<minLot || step<=0)
   {
      Print("LOT_CALC_AUDIT | symbol=",sym," | reason=INVALID_BROKER_SPEC",
         " | riskBudget=",DoubleToString(riskMoney,2)," | tickValue=",DoubleToString(tv,8),
         " | tickSize=",DoubleToString(ts,8)," | stopDistance=",DoubleToString(stopDist,8),
         " | minLot=",DoubleToString(minLot,4)," | maxLot=",DoubleToString(maxLot,4),
         " | lotStep=",DoubleToString(step,4)," | accountCurrency=",AccountCurrency());
      return(0);
   }
   double lossPerLot=(stopDist/ts)*tv;
   if(lossPerLot<=0)
   {
      Print("LOT_CALC_AUDIT | symbol=",sym," | reason=NONPOSITIVE_LOSS_PER_LOT",
         " | lossPerLot=",DoubleToString(lossPerLot,8)," | stopDistance=",DoubleToString(stopDist,8),
         " | tickValue=",DoubleToString(tv,8)," | tickSize=",DoubleToString(ts,8));
      return(0);
   }
   double rawLots=(riskMoney/lossPerLot);
   double lots=MathFloor(rawLots/step+1e-9)*step;
   lots=NormalizeDouble(lots,LotDigits(step));
   double estimatedRisk=(lots>0?EstimateRiskUSD(sym,lots,stopDist):0);
   if(lots<minLot || lots>maxLot || estimatedRisk>riskMoney+0.02)
   {
      Print("LOT_CALC_AUDIT | symbol=",sym," | reason=LOT_OUTSIDE_RISK_BUDGET",
         " | accountCurrency=",AccountCurrency()," | riskBudget=",DoubleToString(riskMoney,2),
         " | stopDistance=",DoubleToString(stopDist,8)," | tickValue=",DoubleToString(tv,8),
         " | tickSize=",DoubleToString(ts,8)," | lossPerLot=",DoubleToString(lossPerLot,8),
         " | rawLots=",DoubleToString(rawLots,6)," | calculatedLots=",DoubleToString(lots,4),
         " | minLot=",DoubleToString(minLot,4)," | maxLot=",DoubleToString(maxLot,4),
         " | lotStep=",DoubleToString(step,4)," | estimatedRisk=",DoubleToString(estimatedRisk,2));
      return(0);
   }
   return(lots);
}

double EstimateRiskUSD(string sym,double lots,double stopDist)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE),ts=MarketInfo(sym,MODE_TICKSIZE);
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