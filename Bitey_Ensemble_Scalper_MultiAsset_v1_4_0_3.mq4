//+------------------------------------------------------------------+
//| Bitey_Ensemble_Scalper_MultiAsset_v1_4_0_3.mq4                      |
//| Scalping / day trading, multi-asset (max 5), bidirectional,       |
//| adaptive SL/TP. Account type (demo/real) NEVER gates orders.      |
//| v1.4.0.3: TP step + log fixes. v1.4.0: cost-aware (commission+spread), lot caps, circuit         |
//| breakers, rollover handling, BE/trail that cover costs.           |
//| Not performance-validated: test on demo/tester before live use.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.43"
#property description "Ensemble scalper v1.4.0: 32 variants, regime aware, max 5 assets, BUY+SELL, cost-aware sizing and filters"

#define EA_VERSION          "1.4.0.3"
#define MAX_SYMBOLS         128
#define HARD_MAX_POSITIONS  5

//--- universe and timeframes
input string           InpSymbolsCSV            = "";      // Blank = symbols in Market Watch (aliases deduplicated)
input ENUM_TIMEFRAMES  InpSignalTF              = PERIOD_M5;
input ENUM_TIMEFRAMES  InpHTF                   = PERIOD_M15; // Higher-timeframe bias (trend regime only)
input bool             InpUseHTFFilter          = true;
input int              InpMagic                 = 21102027;

//--- risk (risk per trade INCLUDES round-turn commission)
input double           InpReferenceCapitalUSD   = 500.0;
input double           InpRiskPctPerTrade       = 0.5;     // 5 positions x 0.5% = 2.5% aggregate
input double           InpMaxAggregateRiskPct   = 2.5;
input double           InpDailyLossPct          = 3.0;     // Blocks NEW entries; open trades stay managed
input int              InpMaxOpenPositions      = 5;       // Clamped to 1..5, one position per asset
input double           InpMaxLotsFX             = 0.30;    // Hard lot cap, forex pairs
input double           InpMaxLotsOther          = 0.10;    // Hard lot cap, metals/crypto/stocks/indices

//--- costs (round-turn commission per 1.00 lot, account currency)
input double           InpCommissionPerLotFX    = 10.0;    // Tradewill statement: 0.01 lot = 0.10
input double           InpCommissionPerLotOther = 15.0;    // Tradewill statement: 0.01 lot = 0.15
input double           InpMaxCostR              = 0.30;    // Skip if (spread+commission) > this fraction of the stop (R)

//--- direction
input bool             InpAllowBuy              = true;
input bool             InpAllowSell             = true;

//--- signal
input int              InpFamilyMinVotes        = 3;       // Variants (of 8) needed for a family to speak
input double           InpTrendADX              = 20.0;    // ADX >= this: trend regime, otherwise range regime
input double           InpMinADX                = 10.0;    // Dead-market filter
input int              InpATRPeriod             = 14;
input double           InpStopATR               = 1.5;
input double           InpRewardRisk            = 1.8;     // Raised from 1.5: winners must pay for the losers

//--- execution filters
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

//--- rollover (swap/spread widening)
input bool             InpBlockRollover         = true;    // No new entries inside the window
input bool             InpFlatBeforeRollover    = true;    // Close open trades when the window starts (avoids swap)
input int              InpRolloverStartMin      = 1410;    // Server minute of day (1410 = 23:30)
input int              InpRolloverEndMin        = 15;      // Server minute of day (15 = 00:15)

//--- circuit breakers
input int              InpMaxConsecLosses       = 4;       // Pause all new entries after N losing closes in a row (0 = off)
input int              InpLossStreakPauseMin    = 60;
input int              InpExpectancyWindow      = 20;      // Last N closed trades per symbol
input int              InpExpectancyMinTrades   = 12;      // Need at least this many before judging a symbol
input int              InpExpectancyBanHours    = 24;      // Ban a symbol this long after its last close if net expectancy < 0

//--- adaptive SL/TP
input bool             InpEnableAdaptiveExits   = true;
input double           InpBreakEvenTriggerATR   = 1.5;     // = 1R with InpStopATR 1.5 (was 1.0: cut winners too early)
input double           InpBreakEvenLockATR      = 0.15;    // Plus commission is added automatically
input double           InpTrailStartATR         = 1.8;
input double           InpTrailDistanceATR      = 1.2;
input double           InpTrailStepATR          = 0.10;    // Minimum SL improvement per modification
input double           InpTPExpandTriggerATR    = 1.5;
input double           InpTPExpandBufferATR     = 1.0;
input double           InpTPExpandStepATR       = 0.25;    // Minimum TP extension per modification (fewer broker requests)
input double           InpTPExpandADXMin        = 22.0;
input double           InpTPMaxDistanceATR      = 5.0;
input double           InpNetTargetR            = 0.0;     // Optional close at +N R net (0 = off; let adaptive TP run)

input bool             InpEnableTrading         = true;    // false = log candidates only
input bool             InpLogRejects            = false;

string   g_symbols[MAX_SYMBOLS];
string   g_keys[MAX_SYMBOLS];
datetime g_lastBar[MAX_SYMBOLS];
int      g_symbolCount = 0;
uint     g_lastCycleTick = 0;
datetime g_lastHeartbeat = 0;
datetime g_lastDailyBlockLog = 0;

string   g_candSym[MAX_SYMBOLS];
int      g_candCmd[MAX_SYMBOLS];
double   g_candScore[MAX_SYMBOLS];

//+------------------------------------------------------------------+
int OnInit()
{
   ParseSymbols();
   if(g_symbolCount<=0) { Print("INIT_ERROR | no symbols found"); return(INIT_FAILED); }
   for(int i=0;i<g_symbolCount;i++)
   {
      g_lastBar[i]=0;
      SymbolSelect(g_symbols[i],true);
   }
   EventSetTimer(1);
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

//+------------------------------------------------------------------+
//| Asset key: strips prefix/suffix so broker aliases collapse        |
//+------------------------------------------------------------------+
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

bool IsCrypto(string sym)
{
   string k=AssetKey(sym);
   string p[17]={"BTC","XBT","ETH","SOL","XRP","LTC","BCH","DOG","ADA","DOT","LIN","AVA","BNB","NEAR","LRC","UNI","ZEC"};
   for(int i=0;i<17;i++)
      if(StringFind(k,p[i])==0) return(true);
   return(false);
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

//+------------------------------------------------------------------+
//| Main cycle: manage exits, collect candidates, open the best ones  |
//+------------------------------------------------------------------+
void RunCycle()
{
   if(!IsTesting())
   {
      uint nowTick=GetTickCount();
      if(g_lastCycleTick!=0 && (nowTick-g_lastCycleTick)<900) return;
      g_lastCycleTick=nowTick;
   }

   ManageExits();

   int maxPos=MaxPositions();
   bool lossBlock=LossStreakBlock();       // circuit breaker: pauses NEW entries only
   int limit=(lossBlock?0:g_symbolCount);
   int nc=0;
   for(int i=0;i<limit;i++)
   {
      string sym=g_symbols[i];
      datetime bt=iTime(sym,InpSignalTF,0);
      if(bt<=0 || bt==g_lastBar[i]) continue;
      g_lastBar[i]=bt;                      // one evaluation per closed bar per symbol

      if(CountOpenPositions()+nc>=maxPos) { Reject(sym,"MAX_POSITIONS"); continue; }
      int cmd; double score; string why;
      if(!Prefilter(sym,why)) { Reject(sym,why); continue; }
      if(!Analyze(sym,cmd,score,why)) { Reject(sym,why); continue; }
      if(cmd==OP_BUY && !InpAllowBuy)  { Reject(sym,"BUY_DISABLED");  continue; }
      if(cmd==OP_SELL && !InpAllowSell) { Reject(sym,"SELL_DISABLED"); continue; }
      g_candSym[nc]=sym; g_candCmd[nc]=cmd; g_candScore[nc]=score; nc++;
   }

   if(nc>0)
   {
      // sort candidates by score, best first
      for(int a=0;a<nc-1;a++)
         for(int b=a+1;b<nc;b++)
            if(g_candScore[b]>g_candScore[a])
            {
               string ts=g_candSym[a]; g_candSym[a]=g_candSym[b]; g_candSym[b]=ts;
               int tc=g_candCmd[a];    g_candCmd[a]=g_candCmd[b];  g_candCmd[b]=tc;
               double td=g_candScore[a]; g_candScore[a]=g_candScore[b]; g_candScore[b]=td;
            }

      double dailyLimit=InpReferenceCapitalUSD*InpDailyLossPct/100.0;
      double dayNet=TodayNet();
      if(dayNet<=-dailyLimit)
      {
         if(g_lastDailyBlockLog==0 || TimeCurrent()-g_lastDailyBlockLog>=300)
         {
            g_lastDailyBlockLog=TimeCurrent();
            Print("DAILY_LOSS_BLOCK | dayNet=",DoubleToString(dayNet,2)," limit=-",DoubleToString(dailyLimit,2)," | no new entries");
         }
      }
      else
      {
         for(int c=0;c<nc;c++)
         {
            if(CountOpenPositions()>=maxPos) break;
            OpenTrade(g_candSym[c],g_candCmd[c],g_candScore[c]);
         }
      }
   }

   datetime now=TimeCurrent();
   if(g_lastHeartbeat==0 || now-g_lastHeartbeat>=300)
   {
      g_lastHeartbeat=now;
      Print("HEARTBEAT | v",EA_VERSION," open=",CountOpenPositions(),"/",maxPos,
            " dayNet=",DoubleToString(TodayNet(),2)," symbols=",g_symbolCount,
            " lossStreakPause=",(lossBlock?"ON":"off"));
   }
}

void Reject(string sym,string reason)
{
   if(InpLogRejects) Print("SYMBOL_REJECT | symbol=",sym," | reason=",reason);
}

//+------------------------------------------------------------------+
//| Cheap checks that do not need indicators                          |
//+------------------------------------------------------------------+
bool QuoteFresh(string sym)
{
   datetime qt=(datetime)MarketInfo(sym,MODE_TIME);
   if(qt<=0) return(false);
   int age=(int)(TimeCurrent()-qt);
   return(age>=-5 && age<=InpMaxQuoteAgeSec);
}

bool SessionOK(string sym)
{
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
   return(true);
}

//+------------------------------------------------------------------+
//| Signal: 4 families x 8 variants, regime aware                     |
//|  trend regime (ADX>=InpTrendADX): trend+momentum+breakout, 2 of 3 |
//|  range regime: Bollinger re-entry + RSI extreme, no opposing mom. |
//+------------------------------------------------------------------+
void Vote(bool buy,bool sell,int &b,int &s)
{
   if(buy && !sell) b++;
   else if(sell && !buy) s++;
}

int FamilyDir(int b,int s)
{
   if(b>=InpFamilyMinVotes && b>2*s) return(1);
   if(s>=InpFamilyMinVotes && s>2*b) return(-1);
   return(0);
}

bool Analyze(string sym,int &cmd,double &score,string &why)
{
   cmd=-1; score=0.0; why="";
   int tf=InpSignalTF;
   double c1=iClose(sym,tf,1), c2=iClose(sym,tf,2);
   double atr=iATR(sym,tf,InpATRPeriod,1);
   double adx=iADX(sym,tf,14,PRICE_CLOSE,MODE_MAIN,1);
   double rsi14=iRSI(sym,tf,14,PRICE_CLOSE,1);
   if(c1<=0 || c2<=0 || atr<=0 || adx<0 || rsi14<0) { why="INDICATOR_DATA_INVALID"; return(false); }
   if(adx<InpMinADX) { why="DEAD_MARKET_ADX"; return(false); }

   // Family 0: EMA stack alignment (8 variants)
   int tb=0,tsl=0;
   int per[9]={5,8,10,13,21,34,50,89,144};
   double ema[9];
   ArrayInitialize(ema,0.0);
   for(int e=0;e<9;e++)
   {
      ema[e]=iMA(sym,tf,per[e],0,MODE_EMA,PRICE_CLOSE,1);
      if(ema[e]<=0) { why="EMA_UNAVAILABLE"; return(false); }
   }
   for(int e2=0;e2<8;e2++)
      Vote(ema[e2]>ema[e2+1] && c1>ema[e2], ema[e2]<ema[e2+1] && c1<ema[e2], tb, tsl);

   // Family 1: RSI momentum (8 variants)
   int mb=0,ms=0;
   int rp[8]={5,7,9,11,14,18,21,28};
   for(int r=0;r<8;r++)
   {
      double rv=iRSI(sym,tf,rp[r],PRICE_CLOSE,1);
      double rprev=iRSI(sym,tf,rp[r],PRICE_CLOSE,2);
      Vote(rv>52 && rv>rprev && rv<75, rv<48 && rv<rprev && rv>25, mb, ms);
   }

   // Family 2: Donchian breakout (8 variants)
   int bb=0,bs=0;
   int lb[8]={5,7,9,12,15,18,22,30};
   for(int d=0;d<8;d++)
   {
      int hi=iHighest(sym,tf,MODE_HIGH,lb[d],2);
      int lo=iLowest(sym,tf,MODE_LOW,lb[d],2);
      double hh=(hi>=0?iHigh(sym,tf,hi):0.0);
      double ll=(lo>=0?iLow(sym,tf,lo):0.0);
      Vote(hh>0 && c1>hh && c1>c2, ll>0 && c1<ll && c1<c2, bb, bs);
   }

   // Family 3: Bollinger re-entry / mean reversion (8 variants)
   int rb=0,rs=0;
   int bp[8]={8,10,12,14,18,20,24,30};
   for(int m=0;m<8;m++)
   {
      double up=iBands(sym,tf,bp[m],2.0,0,PRICE_CLOSE,MODE_UPPER,1);
      double lw=iBands(sym,tf,bp[m],2.0,0,PRICE_CLOSE,MODE_LOWER,1);
      Vote(c2<lw && c1>lw && c1>c2, c2>up && c1<up && c1<c2, rb, rs);
   }

   int dT=FamilyDir(tb,tsl), dM=FamilyDir(mb,ms), dB=FamilyDir(bb,bs), dR=FamilyDir(rb,rs);
   int dir=0, agree=0, win=0;

   if(adx>=InpTrendADX)
   {
      int upF=0, dnF=0;
      if(dT>0) upF++; else if(dT<0) dnF++;
      if(dM>0) upF++; else if(dM<0) dnF++;
      if(dB>0) upF++; else if(dB<0) dnF++;
      if(upF>=2 && dnF==0 && dT>0) { dir=1;  agree=upF; win=tb+mb+bb; }
      else if(dnF>=2 && upF==0 && dT<0) { dir=-1; agree=dnF; win=tsl+ms+bs; }
      else { why="TREND_REGIME_NO_FAMILY_CONSENSUS"; return(false); }

      if(InpUseHTFFilter)
      {
         double hc=iClose(sym,InpHTF,1), he=iMA(sym,InpHTF,50,0,MODE_EMA,PRICE_CLOSE,1);
         if(hc<=0 || he<=0) { why="HTF_DATA_UNAVAILABLE"; return(false); }
         if((dir>0 && hc<=he) || (dir<0 && hc>=he)) { why="HTF_BIAS_AGAINST"; return(false); }
      }
   }
   else
   {
      if(dR>0 && rsi14<=40.0 && dM>=0) { dir=1;  agree=1; win=rb; }
      else if(dR<0 && rsi14>=60.0 && dM<=0) { dir=-1; agree=1; win=rs; }
      else { why="RANGE_REGIME_NO_REVERSION_SETUP"; return(false); }
   }

   // Total cost (spread + commission) relative to the stop is part of the ranking
   double stopRef=atr*InpStopATR;
   double costR=EntryCostR(sym,stopRef);
   score=10.0*agree+win+MathMin(adx,40.0)/4.0-30.0*MathMin(costR,2.0);
   cmd=(dir>0?OP_BUY:OP_SELL);
   return(true);
}

//+------------------------------------------------------------------+
//| Cost of entering + exiting one lot, as a fraction of the stop (R) |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Order entry: stops, cost filter, risk budget, lots                |
//+------------------------------------------------------------------+
bool OpenTrade(string sym,int cmd,double score)
{
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(bid<=0 || ask<bid || point<=0 || atr<=0) { Reject(sym,"ENTRY_DATA_INVALID"); return(false); }
   if(!QuoteFresh(sym)) { Reject(sym,"STALE_QUOTE_AT_ENTRY"); return(false); }

   double spreadPrice=ask-bid;
   double brokerMin=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*point;
   double stopDist=MathMax(atr*InpStopATR,spreadPrice+brokerMin);
   double targetDist=MathMax(stopDist*InpRewardRisk,spreadPrice+brokerMin);
   if(spreadPrice>stopDist*InpMaxSpreadPctOfStop/100.0)
   {
      Print("SPREAD_VS_STOP_REJECT | symbol=",sym," spread=",DoubleToString(spreadPrice,digits),
            " stop=",DoubleToString(stopDist,digits)," maxPct=",DoubleToString(InpMaxSpreadPctOfStop,1));
      return(false);
   }

   double entry=(cmd==OP_BUY?ask:bid);
   double sl=NormalizeDouble(cmd==OP_BUY?entry-stopDist:entry+stopDist,digits);
   double tp=NormalizeDouble(cmd==OP_BUY?entry+targetDist:entry-targetDist,digits);
   stopDist=MathAbs(entry-sl);
   bool ok=false;
   if(cmd==OP_BUY) ok=(sl>0 && tp>0 && sl<bid-brokerMin*0.5 && tp>bid+brokerMin*0.5);
   else            ok=(sl>ask+brokerMin*0.5 && tp>0 && tp<ask-brokerMin*0.5);
   if(!ok) { Print("STOP_PREFLIGHT_REJECT | symbol=",sym," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits)); return(false); }

   // Cost filter: spread + round-turn commission must be a small fraction of the stop
   double costR=EntryCostR(sym,stopDist);
   if(costR>InpMaxCostR)
   {
      Print("COST_REJECT | symbol=",sym," costR=",DoubleToString(costR,3)," max=",DoubleToString(InpMaxCostR,3));
      return(false);
   }

   double maxAgg=InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0;
   double openRisk=CurrentOpenRisk();
   double remaining=maxAgg-openRisk;
   double perTrade=InpReferenceCapitalUSD*InpRiskPctPerTrade/100.0;
   if(remaining<=0.01) { Print("RISK_REJECT | symbol=",sym," reason=AGGREGATE_RISK_CAP open=",DoubleToString(openRisk,2)," cap=",DoubleToString(maxAgg,2)); return(false); }
   double budget=MathMin(perTrade,remaining);
   double lots=LotsForRisk(sym,stopDist,budget);
   if(lots<=0) { Print("RISK_REJECT | symbol=",sym," reason=MIN_LOT_EXCEEDS_BUDGET_OR_CAP budget=",DoubleToString(budget,2)); return(false); }
   double risk=EstimateRisk(sym,lots,stopDist);

   if(!InpEnableTrading)
   {
      Print("DRY_RUN_CANDIDATE | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL")," score=",DoubleToString(score,1),
            " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," costR=",DoubleToString(costR,3),
            " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      return(false);
   }
   if(IsTradeContextBusy()) { Reject(sym,"TRADE_CONTEXT_BUSY"); return(false); }

   ResetLastError();
   int ticket=OrderSend(sym,cmd,lots,entry,InpSlippagePoints,sl,tp,"Bitey Ens v"+EA_VERSION,InpMagic,0,clrNONE);
   if(ticket<0)
   {
      int err=GetLastError();
      Print("ORDER_REJECTED | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL")," error=",err,
            " lots=",DoubleToString(lots,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      return(false);
   }
   Print("ORDER_ACCEPTED | ticket=",ticket," symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
         " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," costR=",DoubleToString(costR,3),
         " score=",DoubleToString(score,1)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
   return(true);
}

//+------------------------------------------------------------------+
//| Position management: adaptive SL/TP, time exit, optional R close |
//+------------------------------------------------------------------+
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

      if(rollover) { CloseTicket(ticket,"ROLLOVER_FLAT"); continue; }   // avoid overnight swap
      if(InpMaxHoldBars>0)
      {
         int barsOpen=iBarShift(sym,InpSignalTF,OrderOpenTime(),false);
         if(barsOpen>=InpMaxHoldBars) { CloseTicket(ticket,"TIME_EXIT"); continue; }
      }
      if(atr<=0) continue;

      if(InpNetTargetR>0.0)
      {
         double refRisk=EstimateRisk(sym,lots,atr*InpStopATR);   // reference R, independent of SL trailing
         if(refRisk<1.0e11 && net>=InpNetTargetR*refRisk) { CloseTicket(ticket,"NET_TARGET_R"); continue; }
      }
      if(!InpEnableAdaptiveExits) continue;

      double minDist=(MarketInfo(sym,MODE_STOPLEVEL)+MarketInfo(sym,MODE_FREEZELEVEL)+2.0)*point;
      double price=(type==OP_BUY?bid:ask);
      double favorable=(type==OP_BUY?price-entry:entry-price);
      double newSL=oldSL, newTP=oldTP;
      bool slUp=false, tpUp=false;

      // Price distance that equals the round-turn commission, so "break-even" really breaks even
      double tvv=MarketInfo(sym,MODE_TICKVALUE), tss=MarketInfo(sym,MODE_TICKSIZE);
      double commPrice=(tvv>0 && tss>0 ? CommissionPerLot(sym)*tss/tvv : 0.0);

      // Break-even + commission + small lock (SL only ever moves toward profit)
      if(InpBreakEvenTriggerATR>0 && favorable>=atr*InpBreakEvenTriggerATR)
      {
         double lockDist=atr*InpBreakEvenLockATR+commPrice;
         double be=(type==OP_BUY?entry+lockDist:entry-lockDist);
         if(type==OP_BUY  && (newSL<=0 || be>newSL) && be<bid-minDist) newSL=be;
         if(type==OP_SELL && (newSL<=0 || be<newSL) && be>ask+minDist) newSL=be;
      }
      // ATR trailing
      if(InpTrailStartATR>0 && InpTrailDistanceATR>0 && favorable>=atr*InpTrailStartATR)
      {
         double tr=(type==OP_BUY?bid-atr*InpTrailDistanceATR:ask+atr*InpTrailDistanceATR);
         if(type==OP_BUY  && tr>newSL+atr*InpTrailStepATR && tr<bid-minDist) newSL=tr;
         if(type==OP_SELL && (newSL<=0 || tr<newSL-atr*InpTrailStepATR) && tr>ask+minDist) newSL=tr;
      }
      newSL=(newSL>0?NormalizeDouble(newSL,digits):0);
      if(type==OP_BUY)  slUp=(newSL>0 && (oldSL<=0 || newSL>oldSL+point*0.5));
      else              slUp=(newSL>0 && (oldSL<=0 || newSL<oldSL-point*0.5));

      // Adaptive TP: extend only in a strong trend when price nears the target
      double adx=iADX(sym,InpSignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
      if(oldTP>0 && favorable>=atr*InpTPExpandTriggerATR && adx>=InpTPExpandADXMin)
      {
         double remainingToTP=(type==OP_BUY?oldTP-bid:ask-oldTP);
         if(remainingToTP<=atr*InpTPExpandBufferATR)
         {
            double curDist=MathAbs(oldTP-entry);
            double want=MathMin(atr*InpTPMaxDistanceATR,MathMax(curDist,favorable+atr*InpTPExpandBufferATR));
            double prop=NormalizeDouble(type==OP_BUY?entry+want:entry-want,digits);
            if(type==OP_BUY  && prop>oldTP+atr*InpTPExpandStepATR && prop>ask+minDist) { newTP=prop; tpUp=true; }
            if(type==OP_SELL && prop<oldTP-atr*InpTPExpandStepATR && prop<bid-minDist) { newTP=prop; tpUp=true; }
         }
      }

      if(!slUp && !tpUp) continue;
      double fSL=(slUp?newSL:oldSL), fTP=(tpUp?newTP:oldTP);
      ResetLastError();
      if(OrderModify(ticket,entry,fSL,fTP,0,clrNONE))
         Print("ADAPTIVE_MODIFY | ticket=",ticket," symbol=",sym,
               " SL ",DoubleToString(oldSL,digits),"->",DoubleToString(fSL,digits),
               " TP ",DoubleToString(oldTP,digits),"->",DoubleToString(fTP,digits));
      else
         Print("ADAPTIVE_MODIFY_FAILED | ticket=",ticket," symbol=",sym," error=",GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Portfolio helpers                                                 |
//+------------------------------------------------------------------+
bool HasPositionForKey(string key)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
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
      if(OrderMagicNumber()==InpMagic && (OrderType()==OP_BUY || OrderType()==OP_SELL)) n++;
   }
   return(n);
}

// Adverse entry-to-stop risk only (incl. commission); a stop at/after break-even counts as zero risk.
double CurrentOpenRisk()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(OrderStopLoss()<=0) return(InpReferenceCapitalUSD);      // unknown risk fails closed
      double d=(OrderType()==OP_BUY?OrderOpenPrice()-OrderStopLoss():OrderStopLoss()-OrderOpenPrice());
      if(d>0) total+=EstimateRisk(OrderSymbol(),OrderLots(),d);
   }
   return(total);
}

double TodayNet()
{
   double net=0.0;
   datetime ds=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
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

// Per-symbol pause: longer after a loss (InpCooldownBars), shorter after a win (InpReentryBars)
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

// Circuit breaker: N losing closes in a row (any symbol) -> pause new entries
bool LossStreakBlock()
{
   if(InpMaxConsecLosses<=0) return(false);
   datetime ct[40]; double nt[40]; bool used[40];
   ArrayInitialize(ct,0);
   ArrayInitialize(nt,0.0);
   ArrayInitialize(used,false);
   int cnt=0, seen=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<300 && cnt<40;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      ct[cnt]=OrderCloseTime();
      nt[cnt]=OrderProfit()+OrderSwap()+OrderCommission();
      used[cnt]=false;
      cnt++;
   }
   if(cnt<InpMaxConsecLosses) return(false);

   int streak=0;
   datetime newest=0;
   for(int k=0;k<cnt;k++)
   {
      int best=-1;
      for(int j=0;j<cnt;j++)
         if(!used[j] && (best<0 || ct[j]>ct[best])) best=j;
      if(best<0) break;
      used[best]=true;
      if(nt[best]<0.0)
      {
         streak++;
         if(newest==0) newest=ct[best];
      }
      else break;
   }
   if(streak<InpMaxConsecLosses) return(false);
   return((TimeCurrent()-newest)<InpLossStreakPauseMin*60);
}

// Per-symbol filter: net expectancy of the last N closed trades < 0 -> ban for InpExpectancyBanHours after the last close
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

//+------------------------------------------------------------------+
//| Sizing (risk includes round-turn commission; lot caps by class)   |
//+------------------------------------------------------------------+
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
//+------------------------------------------------------------------+