//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.29_WalkForwardAdaptive.mq4                     |
//| MT4 / EURUSD H1                                                  |
//+------------------------------------------------------------------+
#property strict
#property version "2.29"

input double RiskPercent = 0.25;
input int MaxOpenTrades = 1;
input int MagicNumber = 2035029;

// Indicators
input int ATRPeriod = 14;
input int ADXPeriod = 14;
input int RSIPeriod = 14;
input int FastEMA = 8;
input int SlowEMA = 21;
input int TrendEMA = 200;

// Trade geometry
input double SL_ATR = 1.30;
input double TP_ATR = 2.60;

// Execution filters
input int MaxSpreadPoints = 30;
input double MaxSpreadATR = 0.35;
input int SessionStart = 7;
input int SessionEnd = 20;
input int CooldownBars = 3;

// Walk forward
input int TrainBars = 120;
input int OOSBars = 50;
input int AuditGap = 2;
input int AuditHorizon = 12;
input int RecalibrationBars = 12;

input int MinTrainTrades = 8;
input int MinOOSTrades = 3;

// Validation levels
input double StrictPF = 1.05;
input double StrictEXP = 0.00;
input double StrictDD = 8.0;

input double RelaxedPF = 0.90;
input double RelaxedEXP = -0.02;
input double RelaxedDD = 12.0;

input double OpportunityPF = 0.80;
input double OpportunityEXP = -0.05;
input double OpportunityDD = 15.0;

// Context
input bool UseContextGate = true;
input double TrendADX = 22.0;
input double RangeADX = 18.0;

// Protection
input bool UseLossProtection = true;
input int MaxLossStreak = 3;
input int LossPauseBars = 6;

input bool UseFlipProtection = true;
input int MaxDirectionFlips = 2;

// Logging
input bool Verbose = true;

enum Strategy
{
   TREND=0,
   MEANREV,
   MOMENTUM,
   BREAKOUT,
   SESSION,
   DIVERGENCE,
   RANGE,
   FRACTAL_HTF,
   STRATEGY_COUNT
};

enum Regime
{
   UNKNOWN=0,
   TREND_UP,
   TREND_DOWN,
   RANGE_REGIME,
   BREAKOUT_REGIME,
   HIGH_VOL
};

struct Stats
{
   int trades;
   int wins;
   int losses;
   double profit;
   double loss;
   double net;
   double pf;
   double exp;
   double dd;
};

int BestStrategy=-1;
double BestScore=-999999;

datetime LastBar=0;

int BarsSinceCalibration=999999;
int LastTradeShift=999999;

int LossStreak=0;
int LastDirection=0;
int DirectionFlips=0;
int PauseUntilShift=999999;

long SignalDetected[STRATEGY_COUNT];
long QualifiedSignals[STRATEGY_COUNT];
long OpenedTrades[STRATEGY_COUNT];

long PositionBlocks=0;
long ContextBlocks=0;
long LossBlocks=0;
long FlipBlocks=0;
long OrderErrors=0;
long NoSignal=0;
long WFRefreshes=0;

//+------------------------------------------------------------------+

string StrategyName(int s)
{
   if(s==TREND) return "TREND";
   if(s==MEANREV) return "MEANREV";
   if(s==MOMENTUM) return "MOMENTUM";
   if(s==BREAKOUT) return "BREAKOUT";
   if(s==SESSION) return "SESSION";
   if(s==DIVERGENCE) return "DIVERGENCE";
   if(s==RANGE) return "RANGE";
   if(s==FRACTAL_HTF) return "FRACTAL_HTF";
   return "UNKNOWN";
}

//+------------------------------------------------------------------+

double ATR(int shift)
{
   return iATR(NULL,PERIOD_H1,ATRPeriod,shift);
}

double ADX(int shift)
{
   return iADX(NULL,PERIOD_H1,ADXPeriod,PRICE_CLOSE,MODE_MAIN,shift);
}

double RSI(int shift)
{
   return iRSI(NULL,PERIOD_H1,RSIPeriod,PRICE_CLOSE,shift);
}

double EMA(int period,int shift)
{
   return iMA(NULL,PERIOD_H1,period,0,MODE_EMA,PRICE_CLOSE,shift);
}

//+------------------------------------------------------------------+

bool NewBar()
{
   datetime t=iTime(NULL,PERIOD_H1,0);

   if(t!=LastBar)
   {
      LastBar=t;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+

int OpenPositions()
{
   int n=0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      if(OrderMagicNumber()!=MagicNumber)
         continue;

      if(OrderType()==OP_BUY || OrderType()==OP_SELL)
         n++;
   }

   return n;
}

//+------------------------------------------------------------------+

bool SessionOK(int shift)
{
   int h=TimeHour(iTime(NULL,PERIOD_H1,shift));

   if(SessionStart<=SessionEnd)
      return h>=SessionStart && h<SessionEnd;

   return h>=SessionStart || h<SessionEnd;
}

//+------------------------------------------------------------------+

bool SpreadOK()
{
   double spread=(Ask-Bid)/Point;
   double a=ATR(1);

   if(spread>MaxSpreadPoints)
      return false;

   if(a>0 && spread*Point/a>MaxSpreadATR)
      return false;

   return true;
}

//+------------------------------------------------------------------+

Regime GetRegime(int shift)
{
   double a=ATR(shift);
   double oldATR=ATR(shift+5);
   double adx=ADX(shift);

   double fast=EMA(FastEMA,shift);
   double slow=EMA(SlowEMA,shift);
   double trend=EMA(TrendEMA,shift);
   double close=iClose(NULL,PERIOD_H1,shift);

   if(a<=0)
      return UNKNOWN;

   if(oldATR>0 && a/oldATR>=1.45)
      return HIGH_VOL;

   if(adx>=TrendADX)
   {
      if(fast>slow && close>trend)
         return TREND_UP;

      if(fast<slow && close<trend)
         return TREND_DOWN;
   }

   if(adx<=RangeADX)
      return RANGE_REGIME;

   double hi=iHigh(
      NULL,
      PERIOD_H1,
      iHighest(NULL,PERIOD_H1,MODE_HIGH,12,shift+1)
   );

   double lo=iLow(
      NULL,
      PERIOD_H1,
      iLowest(NULL,PERIOD_H1,MODE_LOW,12,shift+1)
   );

   if(close>hi || close<lo)
      return BREAKOUT_REGIME;

   return UNKNOWN;
}

//+------------------------------------------------------------------+

bool ContextOK(
   int strategy,
   int direction,
   int shift
)
{
   if(!UseContextGate)
      return true;

   Regime regime=GetRegime(shift);

   double adx=ADX(shift);
   double fast=EMA(FastEMA,shift);
   double slow=EMA(SlowEMA,shift);
   double trend=EMA(TrendEMA,shift);
   double close=iClose(NULL,PERIOD_H1,shift);

   bool up =
      fast>slow &&
      close>trend &&
      adx>=TrendADX;

   bool down =
      fast<slow &&
      close<trend &&
      adx>=TrendADX;

   bool range=(adx<=RangeADX);

   if(strategy==TREND ||
      strategy==MOMENTUM ||
      strategy==FRACTAL_HTF)
   {
      if(direction==1)
         return up;

      if(direction==-1)
         return down;

      return false;
   }

   if(strategy==BREAKOUT)
      return regime==BREAKOUT_REGIME ||
             regime==HIGH_VOL;

   if(strategy==MEANREV ||
      strategy==RANGE ||
      strategy==DIVERGENCE)
      return range;

   if(strategy==SESSION)
   {
      if(direction==1)
         return up || range;

      if(direction==-1)
         return down || range;
   }

   return true;
}

//+------------------------------------------------------------------+

bool RawSignal(
   int strategy,
   int shift,
   int &direction,
   double &strength
)
{
   direction=0;
   strength=0;

   if(shift<2 || shift+30>=Bars)
      return false;

   double close=iClose(NULL,PERIOD_H1,shift);
   double open=iOpen(NULL,PERIOD_H1,shift);

   double atr=ATR(shift);
   double fast=EMA(FastEMA,shift);
   double slow=EMA(SlowEMA,shift);
   double trend=EMA(TrendEMA,shift);

   double rsi=RSI(shift);
   double adx=ADX(shift);

   if(atr<=0)
      return false;

   // TREND
   if(strategy==TREND)
   {
      if(fast>slow &&
         close>trend &&
         adx>=TrendADX &&
         close>open)
      {
         direction=1;
         strength=(close-trend)/atr;
         return true;
      }

      if(fast<slow &&
         close<trend &&
         adx>=TrendADX &&
         close<open)
      {
         direction=-1;
         strength=(trend-close)/atr;
         return true;
      }
   }

   // MEAN REVERSION
   if(strategy==MEANREV)
   {
      if(rsi<=30 && close<fast)
      {
         direction=1;
         strength=(30-rsi)/10;
         return true;
      }

      if(rsi>=70 && close>fast)
      {
         direction=-1;
         strength=(rsi-70)/10;
         return true;
      }
   }

   // MOMENTUM
   if(strategy==MOMENTUM)
   {
      double c1=iClose(NULL,PERIOD_H1,shift+1);
      double c2=iClose(NULL,PERIOD_H1,shift+2);

      if(close>c1 &&
         c1>c2 &&
         close>fast &&
         fast>slow &&
         adx>=TrendADX)
      {
         direction=1;
         strength=(close-c2)/atr;
         return true;
      }

      if(close<c1 &&
         c1<c2 &&
         close<fast &&
         fast<slow &&
         adx>=TrendADX)
      {
         direction=-1;
         strength=(c2-close)/atr;
         return true;
      }
   }

   // BREAKOUT
   if(strategy==BREAKOUT)
   {
      double hi=iHigh(
         NULL,
         PERIOD_H1,
         iHighest(NULL,PERIOD_H1,MODE_HIGH,12,shift+1)
      );

      double lo=iLow(
         NULL,
         PERIOD_H1,
         iLowest(NULL,PERIOD_H1,MODE_LOW,12,shift+1)
      );

      if(close>hi &&
         close-open>0.20*atr)
      {
         direction=1;
         strength=0.5+(close-hi)/atr;
         return true;
      }

      if(close<lo &&
         open-close>0.20*atr)
      {
         direction=-1;
         strength=0.5+(lo-close)/atr;
         return true;
      }
   }

   // SESSION
   if(strategy==SESSION)
   {
      int hour=TimeHour(
         iTime(NULL,PERIOD_H1,shift)
      );

      double body=MathAbs(close-open);

      if(hour>=7 &&
         hour<=10 &&
         body>=0.20*atr)
      {
         direction=close>open ? 1 : -1;
         strength=body/atr;
         return true;
      }
   }

   // DIVERGENCE
   if(strategy==DIVERGENCE)
   {
      double r1=RSI(shift+3);
      double r2=RSI(shift+0);

      double p1=iClose(NULL,PERIOD_H1,shift+3);
      double p2=close;

      if(p2<p1 &&
         r2>r1 &&
         r2<50)
      {
         direction=1;
         strength=MathAbs(r2-r1)/10;
         return true;
      }

      if(p2>p1 &&
         r2<r1 &&
         r2>50)
      {
         direction=-1;
         strength=MathAbs(r2-r1)/10;
         return true;
      }
   }

   // RANGE
   if(strategy==RANGE)
   {
      double hi=iHigh(
         NULL,
         PERIOD_H1,
         iHighest(NULL,PERIOD_H1,MODE_HIGH,20,shift+1)
      );

      double lo=iLow(
         NULL,
         PERIOD_H1,
         iLowest(NULL,PERIOD_H1,MODE_LOW,20,shift+1)
      );

      double width=hi-lo;

      if(adx<=RangeADX && width>0)
      {
         double pos=(close-lo)/width;

         if(pos<=0.20)
         {
            direction=1;
            strength=(0.20-pos)*5;
            return true;
         }

         if(pos>=0.80)
         {
            direction=-1;
            strength=(pos-0.80)*5;
            return true;
         }
      }
   }

   // FRACTAL / HIGHER TIMEFRAME
   if(strategy==FRACTAL_HTF)
   {
      int h4shift=shift/4+1;

      double h4fast=iMA(
         NULL,
         PERIOD_H4,
         8,
         0,
         MODE_EMA,
         PRICE_CLOSE,
         h4shift
      );

      double h4slow=iMA(
         NULL,
         PERIOD_H4,
         21,
         0,
         MODE_EMA,
         PRICE_CLOSE,
         h4shift
      );

      if(h4fast>h4slow &&
         fast>slow &&
         close>trend)
      {
         direction=1;
         strength=1;
         return true;
      }

      if(h4fast<h4slow &&
         fast<slow &&
         close<trend)
      {
         direction=-1;
         strength=1;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+

bool QualityOK(
   int strategy,
   int direction,
   int shift
)
{
   double atr=ATR(shift);

   if(atr<=0)
      return false;

   double body=MathAbs(
      iClose(NULL,PERIOD_H1,shift)-
      iOpen(NULL,PERIOD_H1,shift)
   );

   if(body<atr*0.05)
      return false;

   if(strategy==TREND ||
      strategy==MOMENTUM ||
      strategy==BREAKOUT ||
      strategy==FRACTAL_HTF)
   {
      double fast=EMA(FastEMA,shift);
      double slow=EMA(SlowEMA,shift);
      double close=iClose(NULL,PERIOD_H1,shift);

      if(MathAbs(fast-slow)<atr*0.05)
         return false;

      if(direction==1 && close<=fast)
         return false;

      if(direction==-1 && close>=fast)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+

bool Signal(
   int strategy,
   int shift,
   int &direction,
   double &strength
)
{
   if(!RawSignal(
      strategy,
      shift,
      direction,
      strength))
      return false;

   if(!QualityOK(
      strategy,
      direction,
      shift))
      return false;

   if(!ContextOK(
      strategy,
      direction,
      shift))
      return false;

   return true;
}

//+------------------------------------------------------------------+

double SimTrade(
   int direction,
   int entryShift
)
{
   double atr=ATR(entryShift);

   if(atr<=0)
      return 0;

   double entry=iClose(
      NULL,
      PERIOD_H1,
      entryShift
   );

   double slDistance=atr*SL_ATR;
   double tpDistance=atr*TP_ATR;

   double sl=
      direction==1 ?
      entry-slDistance :
      entry+slDistance;

   double tp=
      direction==1 ?
      entry+tpDistance :
      entry-tpDistance;

   int endShift=
      entryShift-AuditHorizon;

   if(endShift<1)
      endShift=1;

   for(int s=entryShift-1;
       s>=endShift;
       s--)
   {
      double high=iHigh(
         NULL,PERIOD_H1,s);

      double low=iLow(
         NULL,PERIOD_H1,s);

      bool hitSL=false;
      bool hitTP=false;

      if(direction==1)
      {
         hitSL=low<=sl;
         hitTP=high>=tp;
      }
      else
      {
         hitSL=high>=sl;
         hitTP=low<=tp;
      }

      // Conservative same-bar assumption.
      if(hitSL && hitTP)
         return -RiskPercent;

      if(hitSL)
         return -RiskPercent;

      if(hitTP)
         return RiskPercent*
                TP_ATR/SL_ATR;
   }

   double last=iClose(
      NULL,
      PERIOD_H1,
      endShift
   );

   double move=
      direction*(last-entry);

   double result=
      move/slDistance*RiskPercent;

   if(result>RiskPercent*TP_ATR/SL_ATR)
      result=RiskPercent*TP_ATR/SL_ATR;

   if(result<-RiskPercent)
      result=-RiskPercent;

   return result;
}

//+------------------------------------------------------------------+

void AddResult(
   Stats &s,
   double result
)
{
   s.trades++;
   s.net+=result;

   if(result>0)
   {
      s.wins++;
      s.profit+=result;
   }
   else
   if(result<0)
   {
      s.losses++;
      s.loss+=MathAbs(result);
   }
}

//+------------------------------------------------------------------+

void FinishStats(Stats &s)
{
   if(s.loss>0)
      s.pf=s.profit/s.loss;
   else
      s.pf=s.profit>0 ? 999 : 0;

   if(s.trades>0)
      s.exp=s.net/s.trades;

   // Conservative drawdown estimate.
   // The actual tester DD remains the authoritative value.
   if(s.losses>0)
      s.dd=MathMin(100.0,
                   s.losses*RiskPercent);
   else
      s.dd=0;
}

//+------------------------------------------------------------------+

bool Audit(
   int strategy,
   int decisionShift,
   int newest,
   int count,
   Stats &s
)
{
   s.trades=0;
   s.wins=0;
   s.losses=0;
   s.profit=0;
   s.loss=0;
   s.net=0;
   s.pf=0;
   s.exp=0;
   s.dd=0;

   int oldest=newest+count-1;

   if(oldest+AuditHorizon+5>=Bars)
      return false;

   for(int shift=newest;
       shift<=oldest;
       shift++)
   {
      // Never allow the simulated trade to reach
      // the current decision point.
      if(shift-AuditHorizon<=decisionShift)
         continue;

      int direction=0;
      double strength=0;

      if(!Signal(
         strategy,
         shift,
         direction,
         strength))
         continue;

      double result=
         SimTrade(direction,shift);

      AddResult(s,result);
   }

   FinishStats(s);

   return true;
}

//+------------------------------------------------------------------+

double Score(
   Stats &train,
   Stats &oos,
   int &tier
)
{
   tier=0;

   if(train.trades>=MinTrainTrades &&
      oos.trades>=MinOOSTrades &&
      oos.pf>=StrictPF &&
      oos.exp>=StrictEXP &&
      oos.dd<=StrictDD)
   {
      tier=3;
   }
   else
   if(train.trades>=MinTrainTrades/2 &&
      oos.trades>=2 &&
      oos.pf>=RelaxedPF &&
      oos.exp>=RelaxedEXP &&
      oos.dd<=RelaxedDD)
   {
      tier=2;
   }
   else
   if(oos.trades>=2 &&
      oos.pf>=OpportunityPF &&
      oos.exp>=OpportunityEXP &&
      oos.dd<=OpportunityDD)
   {
      tier=1;
   }
   else
   {
      return -999999;
   }

   double score=tier*100;

   score+=MathMin(
      50.0,
      MathMax(-50.0,oos.pf*20)
   );

   score+=MathMin(
      30.0,
      MathMax(-30.0,oos.exp*100)
   );

   score+=MathMin(
      20.0,
      oos.trades
   );

   score-=MathMin(
      20.0,
      oos.dd
   );

   return score;
}

//+------------------------------------------------------------------+

void WalkForward(int decisionShift)
{
   BestStrategy=-1;
   BestScore=-999999;

   int oosNewest=
      decisionShift+AuditGap;

   int trainNewest=
      oosNewest+OOSBars;

   if(trainNewest+
      TrainBars+
      AuditHorizon+10>=Bars)
   {
      if(Verbose)
         Print(
            "B29 WAIT: insufficient historical data"
         );

      return;
   }

   for(int strategy=0;
       strategy<STRATEGY_COUNT;
       strategy++)
   {
      Stats train;
      Stats oos;

      if(!Audit(
         strategy,
         decisionShift,
         trainNewest,
         TrainBars,
         train))
         continue;

      if(!Audit(
         strategy,
         decisionShift,
         oosNewest,
         OOSBars,
         oos))
         continue;

      int tier=0;

      double score=
         Score(
            train,
            oos,
            tier
         );

      if(Verbose)
      {
         Print(
            "B29 WF ",
            StrategyName(strategy),
            " TRAIN=",train.trades,
            " PF=",DoubleToString(train.pf,2),
            " EXP=",DoubleToString(train.exp,3),
            " OOS=",oos.trades,
            " PF=",DoubleToString(oos.pf,2),
            " EXP=",DoubleToString(oos.exp,3),
            " DD=",DoubleToString(oos.dd,2),
            " TIER=",tier,
            " SCORE=",DoubleToString(score,2)
         );
      }

      if(score>BestScore)
      {
         BestScore=score;
         BestStrategy=strategy;
      }
   }

   BarsSinceCalibration=0;
   WFRefreshes++;

   if(Verbose)
   {
      Print(
         "B29 BEST=",
         StrategyName(BestStrategy),
         " SCORE=",
         DoubleToString(BestScore,2)
      );
   }
}

//+------------------------------------------------------------------+

bool LossProtectionOK(int shift)
{
   if(!UseLossProtection)
      return true;

   if(shift<PauseUntilShift)
   {
      LossBlocks++;
      return false;
   }

   if(LossStreak>=MaxLossStreak)
   {
      PauseUntilShift=
         shift-LossPauseBars;

      LossBlocks++;

      if(Verbose)
         Print(
            "B29 LOSS PAUSE streak=",
            LossStreak
         );

      return false;
   }

   return true;
}

//+------------------------------------------------------------------+

bool DirectionOK(int direction)
{
   if(!UseFlipProtection)
      return true;

   if(LastDirection==0)
      return true;

   if(direction!=LastDirection)
   {
      if(DirectionFlips>=MaxDirectionFlips)
      {
         FlipBlocks++;
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+

double CalculateLots(
   double stopDistance
)
{
   if(stopDistance<=0)
      return 0;

   double riskMoney=
      AccountBalance()*
      RiskPercent/100.0;

   double tickValue=
      MarketInfo(Symbol(),MODE_TICKVALUE);

   double tickSize=
      MarketInfo(Symbol(),MODE_TICKSIZE);

   if(tickValue<=0 ||
      tickSize<=0)
      return 0;

   double lossPerLot=
      stopDistance/tickSize*
      tickValue;

   if(lossPerLot<=0)
      return 0;

   double lots=
      riskMoney/lossPerLot;

   double minLot=
      MarketInfo(Symbol(),MODE_MINLOT);

   double maxLot=
      MarketInfo(Symbol(),MODE_MAXLOT);

   double step=
      MarketInfo(Symbol(),MODE_LOTSTEP);

   if(step<=0)
      step=0.01;

   lots=
      MathFloor(lots/step)*step;

   lots=
      MathMax(minLot,
              MathMin(maxLot,lots));

   return NormalizeDouble(lots,2);
}

//+------------------------------------------------------------------+

bool ExecuteTrade(
   int strategy,
   int direction,
   double strength,
   int shift
)
{
   RefreshRates();

   double atr=ATR(1);

   if(atr<=0)
      return false;

   double stopDistance=
      atr*SL_ATR;

   double targetDistance=
      atr*TP_ATR;

   double price=
      direction==1 ? Ask : Bid;

   double sl=
      direction==1 ?
      price-stopDistance :
      price+stopDistance;

   double tp=
      direction==1 ?
      price+targetDistance :
      price-targetDistance;

   int stopLevel=
      (int)MarketInfo(
         Symbol(),
         MODE_STOPLEVEL
      );

   if(stopDistance<
      stopLevel*Point)
      return false;

   if(targetDistance<
      stopLevel*Point)
      return false;

   sl=NormalizeDouble(sl,Digits);
   tp=NormalizeDouble(tp,Digits);

   double lots=
      CalculateLots(stopDistance);

   if(lots<=0)
      return false;

   int type=
      direction==1 ?
      OP_BUY :
      OP_SELL;

   string comment=
      "B29_"+StrategyName(strategy);

   int ticket=
      OrderSend(
         Symbol(),
         type,
         lots,
         price,
         5,
         sl,
         tp,
         comment,
         MagicNumber,
         0,
         clrNONE
      );

   if(ticket<0)
   {
      OrderErrors++;

      if(Verbose)
         Print(
            "B29 OrderSend ERROR=",
            GetLastError()
         );

      return false;
   }

   OpenedTrades[strategy]++;

   LastTradeShift=shift;

   if(LastDirection!=0 &&
      direction!=LastDirection)
      DirectionFlips++;

   LastDirection=direction;

   if(Verbose)
   {
      Print(
         "B29 OPEN ",
         StrategyName(strategy),
         " ticket=",ticket,
         " direction=",direction,
         " lots=",DoubleToString(lots,2),
         " SL=",DoubleToString(sl,Digits),
         " TP=",DoubleToString(tp,Digits)
      );
   }

   return true;
}

//+------------------------------------------------------------------+

void UpdateLossState()
{
   static datetime LastProcessedClose=0;

   datetime latest=LastProcessedClose;
   double latestProfit=0;

   for(int i=OrdersHistoryTotal()-1;
       i>=0;
       i--)
   {
      if(!OrderSelect(
         i,
         SELECT_BY_POS,
         MODE_HISTORY))
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      if(OrderMagicNumber()!=MagicNumber)
         continue;

      if(OrderType()!=OP_BUY &&
         OrderType()!=OP_SELL)
         continue;

      if(OrderCloseTime()<=LastProcessedClose)
         continue;

      if(OrderCloseTime()>latest)
      {
         latest=OrderCloseTime();

         latestProfit=
            OrderProfit()+
            OrderSwap()+
            OrderCommission();
      }
   }

   if(latest>LastProcessedClose)
   {
      LastProcessedClose=latest;

      if(latestProfit<0)
         LossStreak++;
      else
      if(latestProfit>0)
         LossStreak=0;

      if(Verbose)
         Print(
            "B29 CLOSED profit=",
            DoubleToString(latestProfit,2),
            " LOSS_STREAK=",
            LossStreak
         );
   }
}

//+------------------------------------------------------------------+

int SelectSignal(
   int shift,
   int &direction,
   double &strength
)
{
   direction=0;
   strength=0;

   if(BestStrategy<0)
      return -1;

   if(Signal(
      BestStrategy,
      shift,
      direction,
      strength))
   {
      QualifiedSignals[BestStrategy]++;
      return BestStrategy;
   }

   // Secondary strategies.
   int best=-1;
   double bestStrength=-999999;

   for(int strategy=0;
       strategy<STRATEGY_COUNT;
       strategy++)
   {
      if(strategy==BestStrategy)
         continue;

      int d=0;
      double s=0;

      if(!RawSignal(
         strategy,
         shift,
         d,
         s))
         continue;

      if(!QualityOK(
         strategy,
         d,
         shift))
         continue;

      if(!ContextOK(
         strategy,
         d,
         shift))
         continue;

      // Reduce the influence of SESSION.
      if(strategy==SESSION)
         s*=0.85;

      if(s>bestStrength)
      {
         bestStrength=s;
         best=strategy;
         direction=d;
         strength=s;
      }
   }

   if(best>=0)
   {
      QualifiedSignals[best]++;
      return best;
   }

   return -1;
}

//+------------------------------------------------------------------+

void Diagnostics()
{
   Print(
      "========== B29 DIAGNOSTICS =========="
   );

   Print(
      "BEST=",
      StrategyName(BestStrategy),
      " SCORE=",
      DoubleToString(BestScore,2)
   );

   Print(
      "WF_REFRESH=",
      WFRefreshes,
      " POSITION_BLOCK=",
      PositionBlocks,
      " CONTEXT_BLOCK=",
      ContextBlocks,
      " LOSS_BLOCK=",
      LossBlocks,
      " FLIP_BLOCK=",
      FlipBlocks,
      " ORDER_ERRORS=",
      OrderErrors,
      " NO_SIGNAL=",
      NoSignal
   );

   for(int i=0;
       i<STRATEGY_COUNT;
       i++)
   {
      Print(
         StrategyName(i),
         " DETECTED=",
         SignalDetected[i],
         " QUALIFIED=",
         QualifiedSignals[i],
         " OPENED=",
         OpenedTrades[i]
      );
   }

   Print(
      "====================================="
   );
}

//+------------------------------------------------------------------+

int OnInit()
{
   for(int i=0;
       i<STRATEGY_COUNT;
       i++)
   {
      SignalDetected[i]=0;
      QualifiedSignals[i]=0;
      OpenedTrades[i]=0;
   }

   LastBar=
      iTime(NULL,PERIOD_H1,0);

   Print(
      "AI Trading Bot v2.29 WalkForwardAdaptive"
   );

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+

void OnDeinit(
   const int reason
)
{
   Diagnostics();
}

//+------------------------------------------------------------------+

void OnTick()
{
   UpdateLossState();

   if(!NewBar())
      return;

   int shift=1;

   BarsSinceCalibration++;

   // Walk-forward recalibration.
   if(
      BestStrategy<0 ||
      BarsSinceCalibration>=RecalibrationBars
   )
   {
      WalkForward(shift);
   }

   // Existing position.
   if(OpenPositions()>=MaxOpenTrades)
   {
      PositionBlocks++;

      if(Verbose)
         Print("B29 BLOCK POSITION");

      return;
   }

   // Trading session.
   if(!SessionOK(shift))
      return;

   // Spread.
   if(!SpreadOK())
      return;

   // Cooldown.
   if(
      LastTradeShift<999999 &&
      LastTradeShift-shift<CooldownBars
   )
      return;

   // Loss protection.
   if(!LossProtectionOK(shift))
      return;

   int direction=0;
   double strength=0;

   int strategy=
      SelectSignal(
         shift,
         direction,
         strength
      );

   if(strategy<0)
   {
      NoSignal++;
      return;
   }

   // Direction flip protection.
   if(!DirectionOK(direction))
      return;

   // Final context validation.
   if(!ContextOK(
      strategy,
      direction,
      shift))
   {
      ContextBlocks++;
      return;
   }

   // Open only here.
   ExecuteTrade(
      strategy,
      direction,
      strength,
      shift
   );
}
//+------------------------------------------------------------------+