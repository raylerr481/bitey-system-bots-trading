#property strict
#property version   "1.984"
#property description "Bitey SBT Assembly Governance Candidate; chart-local research build."
#property description "Live trading is disabled by default. Validate in Strategy Tester/demo before any live use."

// IMPORTANT:
// - This is a standalone research candidate, NOT a drop-in replacement for the production EA.
// - It operates on the chart symbol only; it does not implement the production multi-asset scanner.
// - Historical model evidence is a bar-replay proxy, not broker-executed model-specific P/L.
// - No martingale, no account switching, fixed effective capital reference USD 500.
// - EnableLiveOrders defaults false. Never enable until tested in Strategy Tester and demo.

input int      MagicNumber             = 10102027;
input double   EffectiveCapitalUSD     = 500.00;
input double   MaxRiskUSDPerTrade      = 1.25;
input double   MaxDailyLossUSD         = 10.00;
input int      MaxTradesPerDay         = 3;
input int      MinSamples              = 12;
input double   MinWinRate              = 0.420;
input double   MinAverageR             = 0.020;
input int      EvidenceLookbackBars    = 600;
input int      OutcomeHorizonBars      = 5;
input int      ATRPeriod               = 14;
input double   StopATR                 = 1.50;
input double   TargetATR               = 2.20;
input int      RequiredQualifiedModels = 2;
input int      RequiredIndependentGroups = 2;
input double   MinScoreMarginR         = 0.020;
input double   MinRelativeScoreMargin  = 0.15;
input int      MaxSpreadPoints         = 100;
input bool     EnableLiveOrders        = false;
input bool     AllowBuy                = true;
input bool     AllowSell               = true;

#define MODEL_COUNT 16
#define SIDE_BUY    1
#define SIDE_SELL  -1

string ModelName[MODEL_COUNT] = {
 "TREND","MOMENTUM","DONCHIAN","MEANREV","STRICT_RANGE",
 "ATR_VOLATILITY_BREAKOUT","SESSION_BIAS","RSI_DIVERGENCE",
 "HTF_TREND_CONFIRM","BOLLINGER_EXPANSION","MACD_CONFIRM",
 "LINEAR_REGRESSION","VOLATILITY_SQUEEZE","FIBONACCI_PULLBACK",
 "BREAK_RETEST","VWAP_DEVIATION"
};

int ModelGroup[MODEL_COUNT] = {
 0,0,1,2,2,1,3,2,0,1,0,0,1,2,1,2
}; // 0 trend, 1 breakout, 2 mean-reversion, 3 session

datetime g_lastBar = 0;
datetime g_dayStart = 0;

struct Evidence
{
 int samples;
 int wins;
 double winRate;
 double avgR;
 bool pass;
};

int OnInit()
{
 if(EffectiveCapitalUSD <= 0 || MaxRiskUSDPerTrade <= 0 ||
    MinSamples < 1 || OutcomeHorizonBars < 1 || ATRPeriod < 2)
 {
   Print("SBT INIT REJECTED | reason=INVALID_INPUTS");
   return(INIT_PARAMETERS_INCORRECT);
 }
 g_lastBar = 0;
 g_dayStart = iTime(Symbol(), PERIOD_D1, 0);
 Print("SBT ASSEMBLY CANDIDATE READY | version=1.984 | symbol=",Symbol(),
       " | liveOrders=",EnableLiveOrders," | effectiveCapitalUSD=",DoubleToString(EffectiveCapitalUSD,2),
       " | riskCapUSD=",DoubleToString(MaxRiskUSDPerTrade,2),
       " | groups=trend,breakout,mean_reversion,session | mode=closed-bar");
 return(INIT_SUCCEEDED);
}

void OnTick()
{
 if(Bars < 250) return;
 datetime bar = iTime(Symbol(), Period(), 1);
 if(bar <= 0 || bar == g_lastBar) return;
 g_lastBar = bar;
 EvaluateAssembly();
}

void EvaluateAssembly()
{
 int rawBuy=0, rawSell=0, qualifiedBuy=0, qualifiedSell=0;
 bool buyGroups[4], sellGroups[4];
 ArrayInitialize(buyGroups,false);
 ArrayInitialize(sellGroups,false);
 double buyScore=0.0, sellScore=0.0;
 int bestBuy=-1, bestSell=-1;
 double bestBuyScore=-1e10, bestSellScore=-1e10;
 int buyRejected=0, sellRejected=0;

 for(int m=0; m<MODEL_COUNT; m++)
 {
   int signal=ModelSignal(m,1);
   Evidence eb=BuildEvidence(m,SIDE_BUY);
   Evidence es=BuildEvidence(m,SIDE_SELL);

   if(signal==SIDE_BUY) rawBuy++;
   if(signal==SIDE_SELL) rawSell++;

   if(eb.pass && signal==SIDE_BUY)
   {
     qualifiedBuy++;
     buyGroups[ModelGroup[m]]=true;
     double s=ScoreEvidence(eb);
     buyScore+=s;
     if(s>bestBuyScore){bestBuyScore=s;bestBuy=m;}
   }
   else if(signal==SIDE_BUY) buyRejected++;

   if(es.pass && signal==SIDE_SELL)
   {
     qualifiedSell++;
     sellGroups[ModelGroup[m]]=true;
     double s=ScoreEvidence(es);
     sellScore+=s;
     if(s>bestSellScore){bestSellScore=s;bestSell=m;}
   }
   else if(signal==SIDE_SELL) sellRejected++;

   Print("SBT MODEL AUDIT | model=",ModelName[m],
         " | signal=",SignalText(signal),
         " | BUY n=",eb.samples," wr=",DoubleToString(eb.winRate,3),
         " avgR=",DoubleToString(eb.avgR,3)," result=",(eb.pass?"PASS":"REJECT"),
         " | SELL n=",es.samples," wr=",DoubleToString(es.winRate,3),
         " avgR=",DoubleToString(es.avgR,3)," result=",(es.pass?"PASS":"REJECT"),
         " | evidenceType=BAR_REPLAY_PROXY");
 }

 int buyGroupCount=CountGroups(buyGroups);
 int sellGroupCount=CountGroups(sellGroups);
 double buyAvg=(qualifiedBuy>0?buyScore/qualifiedBuy:0.0);
 double sellAvg=(qualifiedSell>0?sellScore/qualifiedSell:0.0);
 string decision="WAIT";
 int direction=0;
 string reason="NO_SIDE_PASSES_MODEL_AND_INDEPENDENT_GROUP_GATES";

 bool buyEligible=(AllowBuy && qualifiedBuy>=RequiredQualifiedModels &&
                   buyGroupCount>=RequiredIndependentGroups);
 bool sellEligible=(AllowSell && qualifiedSell>=RequiredQualifiedModels &&
                    sellGroupCount>=RequiredIndependentGroups);

 if(buyEligible && !sellEligible){direction=SIDE_BUY;decision="BUY";reason="BUY_PASSES_ASSEMBLY";}
 else if(sellEligible && !buyEligible){direction=SIDE_SELL;decision="SELL";reason="SELL_PASSES_ASSEMBLY";}
 else if(buyEligible && sellEligible)
 {
   double margin=MathMax(MinScoreMarginR,MathMax(buyAvg,sellAvg)*MinRelativeScoreMargin);
   if(buyAvg-sellAvg>=margin){direction=SIDE_BUY;decision="BUY";reason="BUY_WINS_SCORE_MARGIN";}
   else if(sellAvg-buyAvg>=margin){direction=SIDE_SELL;decision="SELL";reason="SELL_WINS_SCORE_MARGIN";}
   else {reason="CONFLICT_SCORE_MARGIN_NOT_MET";}
 }

 Print("SBT ASSEMBLY | symbol=",Symbol()," | bar=",TimeToString(iTime(Symbol(),Period(),1)),
       " | rawBuy=",rawBuy," rawSell=",rawSell,
       " | qualifiedBuy=",qualifiedBuy," qualifiedSell=",qualifiedSell,
       " | rejectedBuy=",buyRejected," rejectedSell=",sellRejected,
       " | buyGroups=",buyGroupCount," sellGroups=",sellGroupCount,
       " | buyAvgEvidenceScore=",DoubleToString(buyAvg,4),
       " sellAvgEvidenceScore=",DoubleToString(sellAvg,4),
       " | bestBuy=",(bestBuy>=0?ModelName[bestBuy]:"NONE"),
       " bestSell=",(bestSell>=0?ModelName[bestSell]:"NONE"),
       " | decision=",decision," | reason=",reason,
       " | liveOrdersEnabled=",EnableLiveOrders);

 if(direction!=0 && EnableLiveOrders) TryOpen(direction);
}

Evidence BuildEvidence(int model, int side)
{
 Evidence e;
 e.samples=0; e.wins=0; e.winRate=0; e.avgR=0; e.pass=false;
 int maxShift=MathMin(EvidenceLookbackBars, Bars-OutcomeHorizonBars-3);
 if(maxShift<OutcomeHorizonBars+3) return e;

 double sumR=0.0;
 for(int shift=OutcomeHorizonBars+2; shift<=maxShift; shift++)
 {
   int sig=ModelSignal(model,shift);
   if(sig!=side) continue;
   double atr=iATR(Symbol(),Period(),ATRPeriod,shift);
   if(atr<=Point) continue;
   double entry=iClose(Symbol(),Period(),shift);
   double exitPrice=iClose(Symbol(),Period(),shift-OutcomeHorizonBars);
   double move=(exitPrice-entry)*side;
   double spreadCost=MarketInfo(Symbol(),MODE_SPREAD)*Point;
   double r=(move-spreadCost)/(atr*StopATR);
   e.samples++;
   sumR+=r;
   if(r>0.0) e.wins++;
 }
 if(e.samples>0)
 {
   e.winRate=(double)e.wins/e.samples;
   e.avgR=sumR/e.samples;
 }
 e.pass=(e.samples>=MinSamples && e.winRate>=MinWinRate && e.avgR>MinAverageR);
 return e;
}

double ScoreEvidence(Evidence &e)
{
 // Shrink small samples toward zero; scores are comparative evidence, not forecasts.
 double shrink=(double)e.samples/(e.samples+20.0);
 return e.avgR*shrink;
}

int CountGroups(bool &groups[])
{
 int n=0;
 for(int i=0;i<4;i++) if(groups[i]) n++;
 return n;
}

int ModelSignal(int model, int s)
{
 double c=iClose(Symbol(),Period(),s), o=iOpen(Symbol(),Period(),s);
 double h=iHigh(Symbol(),Period(),s), l=iLow(Symbol(),Period(),s);
 double c1=iClose(Symbol(),Period(),s+1);
 double atr=iATR(Symbol(),Period(),ATRPeriod,s);
 if(atr<=Point || c<=0 || c1<=0) return 0;
 double rsi=iRSI(Symbol(),Period(),14,PRICE_CLOSE,s);
 double emaFast=iMA(Symbol(),Period(),9,0,MODE_EMA,PRICE_CLOSE,s);
 double emaSlow=iMA(Symbol(),Period(),21,0,MODE_EMA,PRICE_CLOSE,s);
 double emaTrend=iMA(Symbol(),Period(),50,0,MODE_EMA,PRICE_CLOSE,s);
 double adx=iADX(Symbol(),Period(),14,PRICE_CLOSE,MODE_MAIN,s);
 double macd=iMACD(Symbol(),Period(),12,26,9,PRICE_CLOSE,MODE_MAIN,s);
 double macdSig=iMACD(Symbol(),Period(),12,26,9,PRICE_CLOSE,MODE_SIGNAL,s);
 double upper=iBands(Symbol(),Period(),20,2,0,PRICE_CLOSE,MODE_UPPER,s);
 double lower=iBands(Symbol(),Period(),20,2,0,PRICE_CLOSE,MODE_LOWER,s);
 double upperPrev=iBands(Symbol(),Period(),20,2,0,PRICE_CLOSE,MODE_UPPER,s+1);
 double lowerPrev=iBands(Symbol(),Period(),20,2,0,PRICE_CLOSE,MODE_LOWER,s+1);
 double width=upper-lower, widthPrev=upperPrev-lowerPrev;
 double hh=iHigh(Symbol(),Period(),iHighest(Symbol(),Period(),MODE_HIGH,20,s+1));
 double ll=iLow(Symbol(),Period(),iLowest(Symbol(),Period(),MODE_LOW,20,s+1));
 double slope=(iMA(Symbol(),Period(),20,0,MODE_LWMA,PRICE_CLOSE,s)-
               iMA(Symbol(),Period(),20,0,MODE_LWMA,PRICE_CLOSE,s+3))/3.0;
 bool bull=(c>o), bear=(c<o);
 switch(model)
 {
   case 0: // TREND
     if(emaFast>emaSlow && c>emaTrend && adx>=18) return SIDE_BUY;
     if(emaFast<emaSlow && c<emaTrend && adx>=18) return SIDE_SELL;
     break;
   case 1: // MOMENTUM
     if(c-c1>=0.50*atr && c>emaFast) return SIDE_BUY;
     if(c1-c>=0.50*atr && c<emaFast) return SIDE_SELL;
     break;
   case 2: // DONCHIAN
     if(c>hh+0.02*atr) return SIDE_BUY;
     if(c<ll-0.02*atr) return SIDE_SELL;
     break;
   case 3: // MEANREV
     if(adx<25 && rsi<30) return SIDE_BUY;
     if(adx<25 && rsi>70) return SIDE_SELL;
     break;
   case 4: // STRICT_RANGE
     if(adx<20 && MathAbs(emaFast-emaSlow)<0.25*atr && c<=ll+0.20*atr && rsi<45) return SIDE_BUY;
     if(adx<20 && MathAbs(emaFast-emaSlow)<0.25*atr && c>=hh-0.20*atr && rsi>55) return SIDE_SELL;
     break;
   case 5: // ATR_VOLATILITY_BREAKOUT
     if((h-l)>=0.80*atr && bull && c>c1) return SIDE_BUY;
     if((h-l)>=0.80*atr && bear && c<c1) return SIDE_SELL;
     break;
   case 6: // SESSION_BIAS (broker-server hours)
     if(TimeHour(iTime(Symbol(),Period(),s))>=7 && TimeHour(iTime(Symbol(),Period(),s))<=19)
     {
       if(c>emaTrend && emaFast>emaSlow && c>c1) return SIDE_BUY;
       if(c<emaTrend && emaFast<emaSlow && c<c1) return SIDE_SELL;
     }
     break;
   case 7: // RSI_DIVERGENCE simplified proxy
     if(rsi<28 && c>c1 && iRSI(Symbol(),Period(),14,PRICE_CLOSE,s+1)<rsi+3) return SIDE_BUY;
     if(rsi>72 && c<c1 && iRSI(Symbol(),Period(),14,PRICE_CLOSE,s+1)>rsi-3) return SIDE_SELL;
     break;
   case 8: // HTF_TREND_CONFIRM
   {
     int tf=HigherTimeframe(Period());
     double hf=iMA(Symbol(),tf,9,0,MODE_EMA,PRICE_CLOSE,1);
     double hs=iMA(Symbol(),tf,21,0,MODE_EMA,PRICE_CLOSE,1);
     if(hf>hs && c>emaSlow) return SIDE_BUY;
     if(hf<hs && c<emaSlow) return SIDE_SELL;
     break;
   }
   case 9: // BOLLINGER_EXPANSION
     if(width>widthPrev && c>upper && bull) return SIDE_BUY;
     if(width>widthPrev && c<lower && bear) return SIDE_SELL;
     break;
   case 10: // MACD_CONFIRM
     if(macd>macdSig && macd>0 && c>emaSlow) return SIDE_BUY;
     if(macd<macdSig && macd<0 && c<emaSlow) return SIDE_SELL;
     break;
   case 11: // LINEAR_REGRESSION proxy
     if(slope>0.05*atr && c>emaSlow) return SIDE_BUY;
     if(slope< -0.05*atr && c<emaSlow) return SIDE_SELL;
     break;
   case 12: // VOLATILITY_SQUEEZE release proxy
     if(widthPrev<1.50*atr && width>widthPrev*1.05 && c>upper && bull) return SIDE_BUY;
     if(widthPrev<1.50*atr && width>widthPrev*1.05 && c<lower && bear) return SIDE_SELL;
     break;
   case 13: // FIBONACCI_PULLBACK approximate recent swing retracement
   {
     int hiShift=iHighest(Symbol(),Period(),MODE_HIGH,30,s+1);
     int loShift=iLowest(Symbol(),Period(),MODE_LOW,30,s+1);
     double swingH=iHigh(Symbol(),Period(),hiShift), swingL=iLow(Symbol(),Period(),loShift);
     double range=swingH-swingL;
     if(range>atr && emaFast>emaSlow && c>swingL+0.38*range && c<swingL+0.62*range && bull) return SIDE_BUY;
     if(range>atr && emaFast<emaSlow && c<swingH-0.38*range && c>swingH-0.62*range && bear) return SIDE_SELL;
     break;
   }
   case 14: // BREAK_RETEST simplified one-bar retest
     if(c1>hh && l<=hh && c>hh && bull) return SIDE_BUY;
     if(c1<ll && h>=ll && c<ll && bear) return SIDE_SELL;
     break;
   case 15: // VWAP_DEVIATION proxy: rolling typical-price average (not session VWAP)
   {
     double sumPV=0.0, sumV=0.0;
     int n=MathMin(30,Bars-s-1);
     for(int k=s;k<s+n;k++)
     {
       double typical=(iHigh(Symbol(),Period(),k)+iLow(Symbol(),Period(),k)+iClose(Symbol(),Period(),k))/3.0;
       double vol=(double)iVolume(Symbol(),Period(),k);
       sumPV+=typical*vol; sumV+=vol;
     }
     if(sumV<=0) break;
     double vwapProxy=sumPV/sumV;
     if(c<vwapProxy-0.50*atr && rsi<45) return SIDE_BUY;
     if(c>vwapProxy+0.50*atr && rsi>55) return SIDE_SELL;
     break;
   }
 }
 return 0;
}

int HigherTimeframe(int tf)
{
 if(tf < PERIOD_M15) return PERIOD_M15;
 if(tf < PERIOD_M30) return PERIOD_M30;
 if(tf < PERIOD_H1)  return PERIOD_H1;
 if(tf < PERIOD_H4)  return PERIOD_H4;
 if(tf < PERIOD_D1)  return PERIOD_D1;
 return PERIOD_W1;
}

string SignalText(int signal)
{
 if(signal==SIDE_BUY) return "BUY";
 if(signal==SIDE_SELL) return "SELL";
 return "NONE";
}

double PipValuePerLotUSD()
{
 double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
 double tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);
 if(tickValue<=0 || tickSize<=0) return 0.0;
 // MODE_TICKVALUE is normally in deposit currency; this candidate requires USD account currency.
 if(AccountCurrency()!="USD") return 0.0;
 return tickValue/tickSize;
}

void TryOpen(int direction)
{
 if(AccountCurrency()!="USD")
 {
   Print("SBT ORDER BLOCK | reason=ACCOUNT_CURRENCY_NOT_USD | accountCurrency=",AccountCurrency());
   return;
 }
 if(MarketInfo(Symbol(),MODE_SPREAD)>MaxSpreadPoints)
 {
   Print("SBT ORDER BLOCK | reason=SPREAD_LIMIT | spread=",MarketInfo(Symbol(),MODE_SPREAD));
   return;
 }
 if(CountManagedPositions()>=1)
 {
   Print("SBT ORDER BLOCK | reason=ONE_POSITION_PER_CHART_SYMBOL");
   return;
 }
 if(DailyClosedNet()<=-MaxDailyLossUSD)
 {
   Print("SBT ORDER BLOCK | reason=DAILY_LOSS_LIMIT | net=",DoubleToString(DailyClosedNet(),2));
   return;
 }
 if(TradesOpenedToday()>=MaxTradesPerDay)
 {
   Print("SBT ORDER BLOCK | reason=DAILY_TRADE_LIMIT");
   return;
 }

 RefreshRates();
 double atr=iATR(Symbol(),Period(),ATRPeriod,1);
 if(atr<=Point) return;
 double stopDistance=atr*StopATR;
 double targetDistance=atr*TargetATR;
 double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
 double tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);
 double lotStep=MarketInfo(Symbol(),MODE_LOTSTEP);
 double minLot=MarketInfo(Symbol(),MODE_MINLOT);
 double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
 if(tickValue<=0 || tickSize<=0 || lotStep<=0)
 {
   Print("SBT ORDER BLOCK | reason=INVALID_CONTRACT_SPECIFICATION");
   return;
 }
 double riskPerLot=(stopDistance/tickSize)*tickValue;
 if(riskPerLot<=0) return;
 double riskCap=MathMin(MaxRiskUSDPerTrade,EffectiveCapitalUSD*0.0025);
 double lots=MathFloor((riskCap/riskPerLot)/lotStep)*lotStep;
 lots=MathMin(lots,maxLot);
 lots=NormalizeDouble(lots,2);
 if(lots<minLot)
 {
   Print("SBT ORDER BLOCK | reason=MIN_LOT_EXCEEDS_RISK_CAP | minLot=",minLot,
         " | calculatedLots=",DoubleToString(lots,2)," | riskCapUSD=",DoubleToString(riskCap,2));
   return;
 }
 double actualRisk=lots*riskPerLot;
 if(actualRisk>riskCap+0.01)
 {
   Print("SBT ORDER BLOCK | reason=CALCULATED_RISK_EXCEEDS_CAP | actual=",DoubleToString(actualRisk,2),
         " cap=",DoubleToString(riskCap,2));
   return;
 }

 int type=(direction==SIDE_BUY?OP_BUY:OP_SELL);
 double price=(type==OP_BUY?Ask:Bid);
 double sl=(type==OP_BUY?price-stopDistance:price+stopDistance);
 double tp=(type==OP_BUY?price+targetDistance:price-targetDistance);
 int stopLevel=(int)MarketInfo(Symbol(),MODE_STOPLEVEL);
 if(stopDistance < stopLevel*Point || targetDistance < stopLevel*Point)
 {
   Print("SBT ORDER BLOCK | reason=BROKER_STOP_LEVEL_CONFLICT");
   return;
 }
 sl=NormalizeDouble(sl,Digits);
 tp=NormalizeDouble(tp,Digits);
 int ticket=OrderSend(Symbol(),type,lots,price,5,sl,tp,"BiteySBT-AssemblyCandidate",MagicNumber,0,clrNONE);
 if(ticket<0)
 {
   Print("SBT ORDER FAILED | error=",GetLastError()," | symbol=",Symbol(),
         " | lots=",DoubleToString(lots,2)," | intendedRiskUSD=",DoubleToString(actualRisk,2));
   return;
 }
 Print("SBT ORDER ACCEPTED | ticket=",ticket," | direction=",SignalText(direction),
       " | lots=",DoubleToString(lots,2)," | effectiveCapitalUSD=",DoubleToString(EffectiveCapitalUSD,2),
       " | intendedRiskUSD=",DoubleToString(actualRisk,2),
       " | sl=",DoubleToString(sl,Digits)," | tp=",DoubleToString(tp,Digits),
       " | warning=stop_execution_slippage_gaps_and_contract_conversion_can_exceed_intended_risk");
}

int CountManagedPositions()
{
 int count=0;
 for(int i=OrdersTotal()-1;i>=0;i--)
   if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
     if(OrderMagicNumber()==MagicNumber && OrderSymbol()==Symbol() &&
        (OrderType()==OP_BUY || OrderType()==OP_SELL)) count++;
 return count;
}

double DailyClosedNet()
{
 datetime start=iTime(Symbol(),PERIOD_D1,0);
 double net=0.0;
 for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
     if(OrderMagicNumber()==MagicNumber && OrderSymbol()==Symbol() && OrderCloseTime()>=start)
       net+=OrderProfit()+OrderSwap()+OrderCommission();
 return net;
}

int TradesOpenedToday()
{
 datetime start=iTime(Symbol(),PERIOD_D1,0);
 int count=0;
 for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
     if(OrderMagicNumber()==MagicNumber && OrderSymbol()==Symbol() && OrderOpenTime()>=start) count++;
 for(int j=OrdersTotal()-1;j>=0;j--)
   if(OrderSelect(j,SELECT_BY_POS,MODE_TRADES))
     if(OrderMagicNumber()==MagicNumber && OrderSymbol()==Symbol() && OrderOpenTime()>=start) count++;
 return count;
}
