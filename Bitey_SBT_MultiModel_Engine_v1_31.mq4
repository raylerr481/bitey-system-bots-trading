#property strict
#property version   "1.31"
#property description "Bitey SBT Multi-Model Engine v1.31 - capital-aware risk sizing and evidence diagnostics"

// IMPORTANT
// - Default mode is AUTO_EXECUTION for automatic order execution.
// - No account-type gate is applied; the user is responsible for attaching this EA only to the intended account.
// - OperatingCapitalUSD is a virtual risk-allocation reference; it does not segregate funds at the broker.
// - Historical evidence is an in-sample diagnostic, not proof of future profitability.

enum EngineMode { OBSERVE_ONLY=0, AUTO_EXECUTION=1 };
enum ModelId { MODEL_TREND=0, MODEL_MOMENTUM=1, MODEL_DONCHIAN=2, MODEL_MEANREV=3, MODEL_PULLBACK=4 };

input EngineMode InpMode = AUTO_EXECUTION;
input int      InpMagic = 2036130;
input double   InpOperatingCapitalUSD = 500.0;
input double   InpRiskPerTradeUSD = 1.25;
input double   InpHardRiskCapUSD = 2.00;
input double   InpDailyLossLimitUSD = 10.00;
input int      InpMaxTradesPerDay = 3;
input int      InpMaxOpenTrades = 1;
input int      InpMaxSpreadPoints = 35;
input int      InpSlippagePoints = 10;
input bool     InpWriteCSV = true;
input bool     InpPrintDiagnostics = true;

input int      InpATRPeriod = 14;
input double   InpStopATR = 1.30;
input double   InpTargetATR = 2.60;
input int      InpMaxHoldBars = 6;
input int      InpFastEMA = 8;
input int      InpSlowEMA = 21;
input int      InpTrendEMA = 200;
input int      InpRSIPeriod = 14;
input int      InpADXPeriod = 14;
input double   InpTrendADXMin = 18.0;
input int      InpDonchianPeriod = 20;
input int      InpMomentumLookback = 3;
input double   InpMomentumATRThreshold = 0.65;
input double   InpMeanRevADXMax = 18.0;
input double   InpMeanRevRSIBuy = 30.0;
input double   InpMeanRevRSISell = 70.0;
input double   InpPullbackMaxGapATR = 0.35;
input double   InpBreakoutBufferATR = 0.05;

input int      InpEvidenceLookbackBars = 240;
input int      InpForwardHorizonBars = 6;
input int      InpMinEvidenceSamples = 12;
input double   InpMinEvidenceWinRate = 0.42;
input double   InpMinEvidenceAvgR = 0.02;
input int      InpMinModelVotes = 1;

string   g_modelNames[5] = {"TREND","MOMENTUM","DONCHIAN","MEANREV","PULLBACK"};
datetime g_lastBarTime = 0;

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

int OnInit()
{
   if(InpOperatingCapitalUSD<=0 || InpRiskPerTradeUSD<=0 || InpHardRiskCapUSD<=0 ||
      InpDailyLossLimitUSD<=0 || InpMaxTradesPerDay<1 || InpMaxOpenTrades<1 ||
      InpMaxSpreadPoints<0 || InpSlippagePoints<0 || InpATRPeriod<2 ||
      InpFastEMA<2 || InpSlowEMA<2 || InpTrendEMA<2 || InpRSIPeriod<2 || InpADXPeriod<2 ||
      InpDonchianPeriod<2 || InpMomentumLookback<1 || InpMomentumATRThreshold<0 ||
      InpForwardHorizonBars<1 || InpEvidenceLookbackBars<30 || InpMinEvidenceSamples<1 ||
      InpMinEvidenceWinRate<0 || InpMinEvidenceWinRate>1 || InpMinEvidenceAvgR<0 ||
      InpMeanRevADXMax<0 || InpMeanRevRSIBuy<0 || InpMeanRevRSIBuy>100 ||
      InpMeanRevRSISell<0 || InpMeanRevRSISell>100 || InpPullbackMaxGapATR<0 ||
      InpBreakoutBufferATR<0 || InpStopATR<=0 || InpTargetATR<=0 ||
      InpTrendADXMin<0 || InpMinModelVotes<1 || InpMinModelVotes>5)
   {
      Print("BITEY SBT v1.31 INIT ERROR: invalid risk or lookback inputs.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   g_lastBarTime=0;
   Print("BITEY SBT Multi-Model Engine v1.31 initialized | Symbol=",Symbol(),
         " TF=",Period()," Mode=",(InpMode==OBSERVE_ONLY?"OBSERVE_ONLY":"AUTO_EXECUTION"),
         " OperatingCapitalUSD=",DoubleToString(InpOperatingCapitalUSD,2),
         " RiskRequestUSD=",DoubleToString(InpRiskPerTradeUSD,2),
         " HardRiskCapUSD=",DoubleToString(InpHardRiskCapUSD,2),
         " RiskBasis=operating-capital-reference; AccountTypeFilter=none");
   if(InpWriteCSV) EnsureCSVHeader();
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(Bars < InpTrendEMA+InpDonchianPeriod+InpForwardHorizonBars+20) return;
   datetime barTime=iTime(Symbol(),Period(),0);
   if(barTime==0 || barTime==g_lastBarTime) return;
   g_lastBarTime=barTime;
   EvaluateEngine();
}

void EnsureCSVHeader()
{
   int h=FileOpen("Bitey_SBT_Evidence_v1_31.csv",FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) { Print("CSV warning: cannot open evidence file. Error=",GetLastError()); return; }
   if(FileSize(h)==0)
      FileWrite(h,"time","symbol","timeframe","model","direction","samples","win_rate","avg_R","signal","decision");
   FileClose(h);
}

void WriteEvidenceRow(string model,string direction,DirectionEvidence &e,int signal,string decision)
{
   if(!InpWriteCSV) return;
   int h=FileOpen("Bitey_SBT_Evidence_v1_31.csv",FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),IntegerToString(Period()),model,direction,
             IntegerToString(e.samples),DoubleToString(e.winRate,4),DoubleToString(e.avgR,4),IntegerToString(signal),decision);
   FileClose(h);
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

bool GetModelSignals(int shift,int &trend,int &momentum,int &donchian,int &meanrev,int &pullback)
{
   trend=0; momentum=0; donchian=0; meanrev=0; pullback=0;
   if(Bars < InpTrendEMA+InpDonchianPeriod+shift+InpMomentumLookback+5) return false;
   double close1=iClose(Symbol(),Period(),shift);
   double atr=GetATR(shift);
   double emaFast=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,shift);
   double emaSlow=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,shift);
   double emaTrend=iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,shift);
   double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,shift);
   double plusDI=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_PLUSDI,shift);
   double minusDI=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MINUSDI,shift);
   double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,shift);
   if(close1<=0 || atr<=0 || emaFast<=0 || emaSlow<=0 || emaTrend<=0) return false;

   if(adx>=InpTrendADXMin)
   {
      // Standard directional trend confirmation.
      if(close1>emaTrend && emaFast>emaSlow && plusDI>minusDI) trend=1;
      else if(close1<emaTrend && emaFast<emaSlow && minusDI>plusDI) trend=-1;
      else
      {
         // Pullback continuation: price remains on the correct side of EMA200,
         // ADX is strong, directional DI confirms the trend, and price is near EMA21.
         // This can recognize a retracement without treating every retracement as a reversal.
         double emaGap=MathAbs(close1-emaSlow);
         if(close1<emaTrend && minusDI>plusDI && emaGap<=0.25*atr) trend=-1;
         else if(close1>emaTrend && plusDI>minusDI && emaGap<=0.25*atr) trend=1;
      }
   }

   int momShift=shift+InpMomentumLookback;
   double oldClose=iClose(Symbol(),Period(),momShift);
   if(oldClose>0)
   {
      double normalized=(close1-oldClose)/atr;
      if(normalized>=InpMomentumATRThreshold && close1>emaSlow) momentum=1;
      else if(normalized<=-InpMomentumATRThreshold && close1<emaSlow) momentum=-1;
   }

   double priorHigh=-1.0e100, priorLow=1.0e100;
   for(int k=shift+1;k<=shift+InpDonchianPeriod;k++)
   {
      double hi=iHigh(Symbol(),Period(),k), lo=iLow(Symbol(),Period(),k);
      if(hi>priorHigh) priorHigh=hi;
      if(lo<priorLow) priorLow=lo;
   }
   double breakoutBuffer=MathMax(0.0,InpBreakoutBufferATR)*atr;
   if(close1>priorHigh+breakoutBuffer) donchian=1;
   else if(close1<priorLow-breakoutBuffer) donchian=-1;

   if(adx<=InpMeanRevADXMax)
   {
      if(rsi<=InpMeanRevRSIBuy) meanrev=1;
      else if(rsi>=InpMeanRevRSISell) meanrev=-1;
   }

   // Separate pullback-continuation model. It requires trend structure, DI confirmation,
   // and a closed candle reclaim/rejection around EMA21. It is not a blind EMA touch.
   double gapATR=MathAbs(close1-emaSlow)/atr;
   double close2=iClose(Symbol(),Period(),shift+1);
   double emaSlow2=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,shift+1);
   if(adx>=InpTrendADXMin && gapATR<=InpPullbackMaxGapATR && close2>0 && emaSlow2>0)
   {
      if(close1>emaTrend && emaTrend>iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,shift+5)
         && plusDI>minusDI && close1>emaSlow && close2<=emaSlow2)
         pullback=1;
      else if(close1<emaTrend && emaTrend<iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,shift+5)
              && minusDI>plusDI && close1<emaSlow && close2>=emaSlow2)
         pullback=-1;
   }
   return true;
}

// Returns the realized forward outcome in R for a hypothetical entry at the closed bar close.
// If stop and target are both touched inside one candle, the conservative result is -1R.
bool ForwardOutcomeR(int entryShift,int direction,double &outR)
{
   outR=0.0;
   double entry=iClose(Symbol(),Period(),entryShift);
   double atr=GetATR(entryShift);
   if(entry<=0 || atr<=0 || direction==0) return false;
   double riskDistance=atr*InpStopATR;
   double targetDistance=atr*InpTargetATR;
   if(riskDistance<=0 || targetDistance<=0) return false;
   int endShift=entryShift-InpForwardHorizonBars;
   if(endShift<0) endShift=0;
   for(int s=entryShift-1;s>=endShift;s--)
   {
      if(s<0) break;
      double hi=iHigh(Symbol(),Period(),s), lo=iLow(Symbol(),Period(),s);
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
   double exitClose=iClose(Symbol(),Period(),endShift);
   if(exitClose<=0) return false;
   outR=(direction>0 ? (exitClose-entry) : (entry-exitClose))/riskDistance;
   return true;
}

int ModelSignalAt(int model,int shift)
{
   int t=0,m=0,d=0,r=0,p=0;
   if(!GetModelSignals(shift,t,m,d,r,p)) return 0;
   if(model==MODEL_TREND) return t;
   if(model==MODEL_MOMENTUM) return m;
   if(model==MODEL_DONCHIAN) return d;
   if(model==MODEL_MEANREV) return r;
   if(model==MODEL_PULLBACK) return p;
   return 0;
}

void BuildEvidence(int model,int direction,DirectionEvidence &e)
{
   ResetEvidence(e);
   int maxShift=MathMin(InpEvidenceLookbackBars,Bars-InpTrendEMA-InpDonchianPeriod-InpForwardHorizonBars-5);
   int minShift=InpForwardHorizonBars+1;
   for(int shift=minShift;shift<=maxShift;shift++)
   {
      if(ModelSignalAt(model,shift)!=direction) continue;
      double resultR=0.0;
      if(!ForwardOutcomeR(shift,direction,resultR)) continue;
      e.samples++;
      if(resultR>0.0) e.wins++;
      e.sumR+=resultR;
   }
   FinalizeEvidence(e);
}

bool EvidencePass(DirectionEvidence &e)
{
   return (e.samples>=InpMinEvidenceSamples && e.winRate>=InpMinEvidenceWinRate && e.avgR>InpMinEvidenceAvgR);
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
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()>=dayStart) count++;
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderOpenTime()>=dayStart) count++;
   }
   return count;
}

double TodayNetProfit()
{
   double net=0.0;
   datetime dayStart=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()>=dayStart) net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
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
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==InpMagic && (OrderType()==OP_BUY || OrderType()==OP_SELL)) count++;
   }
   return count;
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

   // Broker feeds differ: MODE_TICKSIZE is commonly reported in points,
   // but some feeds return the tick size directly in price units. Normalize both.
   double tickSizePrice=tickSizeRaw;
   if(tickSizeRaw>=Point*10.0) tickSizePrice=tickSizeRaw*Point;
   if(tickSizePrice<=0)
   {
      Print("LOT SPEC ERROR | normalized tick size is invalid. raw=",DoubleToString(tickSizeRaw,10));
      return 0.0;
   }

   double ticksToStop=stopDistancePrice/tickSizePrice;
   double riskPerLot=ticksToStop*tickValue;
   double rawLots=riskUSD/riskPerLot;
   double minLotRisk=minLot*riskPerLot;

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

   // Never round up to broker minimum if that would exceed the risk budget.
   if(rawLots<minLot)
   {
      Print("LOT BLOCKED | broker minimum lot would risk USD ",DoubleToString(minLotRisk,2),
            ", above allowed USD ",DoubleToString(riskUSD,2),". Risk limit preserved.");
      return 0.0;
   }
   double lots=NormalizeLotsDown(rawLots);
   if(lots<minLot || lots>maxLot) return 0.0;
   return lots;
}

bool TradeGate(string &reason)
{
   reason="OK";
   if(InpMode!=AUTO_EXECUTION) { reason="OBSERVE_ONLY mode"; return false; }
   if(!IsTradeAllowed()) { reason="terminal or EA trading not allowed"; return false; }
   if(MarketInfo(Symbol(),MODE_SPREAD)>InpMaxSpreadPoints) { reason="spread gate"; return false; }
   int openCount=CountOpenTrades();
   if(openCount>=InpMaxOpenTrades)
   {
      reason="maximum open trades reached (open="+IntegerToString(openCount)+
             ", limit="+IntegerToString(InpMaxOpenTrades)+")";
      return false;
   }
   if(CountTodayTrades()>=InpMaxTradesPerDay) { reason="daily trade count limit"; return false; }
   if(TodayNetProfit()<=-MathAbs(InpDailyLossLimitUSD)) { reason="daily loss limit reached"; return false; }
   if(IsTradeContextBusy()) { reason="trade context busy"; return false; }
   return true;
}

bool SendOrder(int direction)
{
   string gateReason="";
   if(!TradeGate(gateReason))
   {
      Print("ORDER BLOCKED | ",gateReason);
      return false;
   }
   RefreshRates();
   double atr=GetATR(1);
   if(atr<=0) { Print("ORDER BLOCKED | invalid ATR"); return false; }
   double stopDistance=atr*InpStopATR;
   double targetDistance=atr*InpTargetATR;
   double riskUSD=MathMin(InpRiskPerTradeUSD,InpHardRiskCapUSD);
   // The configured operating capital is the sizing reference, not a broker-side fund partition.
   // Keep per-trade risk capped at 0.4% of that reference, even if other inputs are raised.
   riskUSD=MathMin(riskUSD,InpOperatingCapitalUSD*0.004);
   if(riskUSD<=0) { Print("ORDER BLOCKED | calculated risk is zero"); return false; }
   double lots=CalculateLotsForRisk(riskUSD,stopDistance);
   if(lots<=0) { Print("ORDER BLOCKED | lot calculation failed; inspect preceding LOT CALC / LOT SPEC diagnostics"); return false; }

   int type=(direction>0?OP_BUY:OP_SELL);
   double price=(direction>0?Ask:Bid);
   double sl=(direction>0?price-stopDistance:price+stopDistance);
   double tp=(direction>0?price+targetDistance:price-targetDistance);
   int stopLevel=(int)MarketInfo(Symbol(),MODE_STOPLEVEL);
   double minStop=stopLevel*Point;
   if(MathAbs(price-sl)<minStop || MathAbs(tp-price)<minStop)
   {
      Print("ORDER BLOCKED | broker stop-level constraint");
      return false;
   }
   price=NormalizeDouble(price,Digits); sl=NormalizeDouble(sl,Digits); tp=NormalizeDouble(tp,Digits);
   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,InpSlippagePoints,sl,tp,"Bitey SBT v1.31 auto",InpMagic,0,clrNONE);
   if(ticket<0)
   {
      Print("ORDER ERROR | code=",GetLastError()," lots=",DoubleToString(lots,2)," riskUSD=",DoubleToString(riskUSD,2));
      return false;
   }
   Print("ORDER OPENED | ticket=",ticket," direction=",(direction>0?"BUY":"SELL"),
         " lots=",DoubleToString(lots,2)," riskUSD<=",DoubleToString(riskUSD,2),
         " SL=",DoubleToString(sl,Digits)," TP=",DoubleToString(tp,Digits));
   return true;
}

void PrintEvidence(string modelName,string direction,DirectionEvidence &e,int signal)
{
   Print(modelName," ",direction," n=",e.samples," wr=",DoubleToString(e.winRate,2),
         " avgR=",DoubleToString(e.avgR,2)," pass=",(EvidencePass(e)?"YES":"NO")," signal=",signal);
}

void EvaluateEngine()
{
   int trend=0,momentum=0,donchian=0,meanrev=0,pullback=0;
   if(!GetModelSignals(1,trend,momentum,donchian,meanrev,pullback))
   {
      Print("DATA_GATE: insufficient history or indicator data.");
      return;
   }

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
            " signals T=",trend," M=",momentum," D=",donchian," R=",meanrev," P=",pullback,
            " spreadPts=",(int)MarketInfo(Symbol(),MODE_SPREAD));

   DirectionEvidence buy[5],sell[5];
   int signals[5];
   signals[0]=trend; signals[1]=momentum; signals[2]=donchian; signals[3]=meanrev; signals[4]=pullback;
   int buyVotes=0,sellVotes=0;
   for(int m=0;m<5;m++)
   {
      BuildEvidence(m,1,buy[m]);
      BuildEvidence(m,-1,sell[m]);
      if(signals[m]>0 && EvidencePass(buy[m])) buyVotes++;
      if(signals[m]<0 && EvidencePass(sell[m])) sellVotes++;
      if(InpPrintDiagnostics)
      {
         PrintEvidence(g_modelNames[m],"BUY",buy[m],(signals[m]>0?1:0));
         PrintEvidence(g_modelNames[m],"SELL",sell[m],(signals[m]<0?-1:0));
      }
      WriteEvidenceRow(g_modelNames[m],"BUY",buy[m],(signals[m]>0?1:0),"EVIDENCE");
      WriteEvidenceRow(g_modelNames[m],"SELL",sell[m],(signals[m]<0?-1:0),"EVIDENCE");
   }

   int decision=0;
   string decisionText="WAIT: insufficient evidence or conflicting directions";
   if(buyVotes>=InpMinModelVotes && sellVotes==0) { decision=1; decisionText="BUY candidate"; }
   else if(sellVotes>=InpMinModelVotes && buyVotes==0) { decision=-1; decisionText="SELL candidate"; }
   else if(buyVotes>0 && sellVotes>0) decisionText="WAIT: conflicting model votes";

   Print("BITEY SBT v1.31 | ",Symbol()," TF=",Period()," BUY votes=",buyVotes," SELL votes=",sellVotes,
         " | TREND signal=",trend," MOMENTUM signal=",momentum," DONCHIAN signal=",donchian," MEANREV signal=",meanrev," PULLBACK signal=",pullback,
         " | DECISION=",decisionText);

   if(decision==0)
   {
      Print("NO ENTRY | reason=NO_QUALIFIED_DIRECTIONAL_SETUP; signals T/M/D/R/P=",
            trend,"/",momentum,"/",donchian,"/",meanrev,"/",pullback,
            "; votes BUY/SELL=",buyVotes,"/",sellVotes,
            ". No trade is forced; wait for a confirmed setup with historical evidence.");
      return;
   }
   string gateReason="";
   if(!TradeGate(gateReason))
   {
      Print("DECISION NOT EXECUTED | ",decisionText," | gate=",gateReason);
      return;
   }
   SendOrder(decision);
}
