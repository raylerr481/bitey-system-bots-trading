//+------------------------------------------------------------------+
//| Bitey_Bollinger_MultiAsset_v1_0_1_AdaptiveSLTP_LeverageControl.mq4                             |
//| Multi-asset MT4 EA: Bollinger rebound + Bollinger breakout        |
//| News selector imported conceptually from Bitey Scalper v1.5.62   |
//| News mode is SHADOW ONLY: SCOUT entries are never vetoed.         |
//| No EMA, RSI, MACD, ADX or other indicator is used for signals.     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.01"
#property description "Multi-asset Bollinger-only signals: rebound and breakout."

#define EA_NAME "Bitey_Bollinger_MultiAsset"
#define EA_VER  "1.0.1-ADAPTIVE-SLTP-LEVERAGE"
#define MAX_SCAN 256
#define NEWS_MAX_ROWS 300

//--- Universe / scanner
input bool             InpScanMarketWatch       = true;       // Scan symbols selected in Market Watch
input string           InpSymbolsCSV            = "";         // Optional explicit symbols; blank = Market Watch
input int              InpMaxSymbols            = 150;
input int              InpScanIntervalSeconds   = 5;
input ENUM_TIMEFRAMES  InpSignalTF              = PERIOD_M5;
input int              InpMinBars               = 250;
input int              InpMaxQuoteAgeSec        = 120;
input bool             InpCryptoExpected24x7    = true;       // Calendar expectation only; live quote/trade permission still required
input bool             InpLogScannerDiagnostics = true;

//--- Bollinger Bands: the ONLY signal indicator
input int              InpBBPeriod              = 20;
input double           InpBBDeviation           = 2.0;
input ENUM_APPLIED_PRICE InpBBPrice              = PRICE_CLOSE;
input bool             InpEnableRebound         = true;
input bool             InpEnableBreakout        = true;
input bool             InpRequireCandleDirection= true;       // Rejection candle direction for rebound
input int              InpEntryWindowSeconds    = 90;         // Only enter during first N seconds of a new signal bar

//--- Adaptive exits. ATR is used ONLY for stop/target sizing and trailing, never for entry signals.
input int              InpATRPeriod             = 14;
input double           InpSL_ATR                = 1.50;
input double           InpMinSL_ATR             = 0.80;
input double           InpMaxSL_ATR             = 3.00;
input double           InpTP_R_multiple         = 1.80;
input bool             InpBreakEvenEnabled      = true;
input double           InpBreakEvenAtR          = 0.80;
input double           InpBreakEvenLockR        = 0.05;
input bool             InpTrailingEnabled       = true;
input double           InpTrailStartR           = 1.20;
input double           InpTrailDistanceATR      = 0.90;
input int              InpModifyThrottleSec     = 5;

//--- Risk and execution
input double           InpStrategicCapitalUSD   = 500.0;       // Fixed strategy capital; account must be USD
input double           InpRiskPercent           = 0.50;        // 0.5% of strategic capital = USD 2.50
input double           InpRiskUSDOverride       = 0.0;         // Optional fixed USD risk; capped by strategic risk
input double           InpMaxAggregateRiskPct   = 2.50;        // 2.5% of strategic capital = USD 12.50
input double           InpMaxMarginUsePctFree   = 20.0;        // Max margin consumed by new position vs current free margin
input double           InpMinAdaptiveTP_R       = 1.40;
input double           InpMaxAdaptiveTP_R       = 2.20;
input double           InpSLStructureBufferATR   = 0.25;        // Buffer beyond signal candle extreme
input int              InpMaxOpenPositions      = 5;
input int              InpMaxPositionsPerSymbol = 1;
input double           InpMaxSpreadPoints       = 100.0;
input double           InpMaxSpreadPctOfSL      = 20.0;
input int              InpSlippagePoints        = 30;
input int              InpMagic                 = 26112201;
input bool             InpAllowBuy              = true;
input bool             InpAllowSell             = true;

//--- Selective leverage: add-on risk must be fully funded by profit protected by the parent SL.
//--- Disabled by default until demo validation. It never increases the aggregate risk ceiling.
input bool             InpEnableFundedAddOns    = false;
input double           InpAddOnMinParentR       = 1.00;
input double           InpAddOnFundingPct       = 50.0;
input double           InpAddOnMaxLotMultiplier = 0.50;
input int              InpMaxAddOnsPerSymbol    = 1;

//--- News guard copied from v1.5.62 file contract. SHADOW ONLY by design.
input bool             InpNewsGuardEnabled      = true;
input bool             InpNewsGuardShadowOnly   = true;        // Must remain true in this release
input string           InpNewsFileName          = "bitey_news_guard.csv";
input bool             InpNewsUseCommonFolder   = true;
input int              InpNewsFileMaxAgeMin     = 30;
input bool             InpNewsUsdAffectsUsdt    = true;
input int              InpNewsLogThrottleMin    = 15;
input int              InpNewsPreProtectLeadMin  = 5;
input int              InpNewsPostProtectMin     = 3;
input double           InpNewsProtectMinNetUSD   = 0.10;
input double           InpNewsProtectKeepPct     = 75.0;

//--- State
string   g_symbols[MAX_SCAN];
datetime g_lastSignalBar[MAX_SCAN];
datetime g_lastModify[MAX_SCAN];
int      g_symbolCount=0;
datetime g_lastScan=0;
datetime g_newsLastLoad=0;
datetime g_newsLastStateLog=0;
datetime g_newsUpdated=0;
bool     g_newsFileOk=false;
int      g_newsCount=0;
string   g_newsScope[NEWS_MAX_ROWS];
string   g_newsKey[NEWS_MAX_ROWS];
datetime g_newsFrom[NEWS_MAX_ROWS];
datetime g_newsUntil[NEWS_MAX_ROWS];
datetime g_newsEvent[NEWS_MAX_ROWS];
string   g_newsReason[NEWS_MAX_ROWS];
string   g_newsLogSymbol[NEWS_MAX_ROWS];
datetime g_newsLogTime[NEWS_MAX_ROWS];
int      g_newsLogCount=0;

//+------------------------------------------------------------------+
string Upper(string value)
{
   StringToUpper(value);
   return(value);
}

bool IsCryptoSymbol(string symbol)
{
   string s=Upper(symbol);
   string tokens=" BTC ETH XRP LTC BCH ADA DOT SOL DOGE AVAX LINK XLM TRX TON BNB USDT USDC ";
   string bases[]={"BTC","ETH","XRP","LTC","BCH","ADA","DOT","SOL","DOGE","AVAX","LINK","XLM","TRX","TON","BNB"};
   for(int i=0;i<ArraySize(bases);i++)
      if(StringFind(s,bases[i])==0 || StringFind(s,bases[i]+".")>=0 || StringFind(s,bases[i]+"m")>=0)
         return(true);
   if(StringFind(s,"USDT")>=0 || StringFind(s,"USDC")>=0) return(true);
   return(false);
}

bool AddSymbol(string symbol)
{
   StringTrimLeft(symbol); StringTrimRight(symbol);
   if(symbol=="") return(false);
   for(int i=0;i<g_symbolCount;i++) if(g_symbols[i]==symbol) return(true);
   if(g_symbolCount>=MathMin(MAX_SCAN,MathMax(1,InpMaxSymbols))) return(false);
   if(!SymbolSelect(symbol,true)) return(false);
   g_symbols[g_symbolCount]=symbol;
   g_lastSignalBar[g_symbolCount]=0;
   g_lastModify[g_symbolCount]=0;
   g_symbolCount++;
   return(true);
}

void BuildUniverse()
{
   g_symbolCount=0;
   if(StringLen(InpSymbolsCSV)>0)
   {
      string items[];
      int n=StringSplit(InpSymbolsCSV,StringGetCharacter(",",0),items);
      for(int i=0;i<n;i++) AddSymbol(items[i]);
   }
   else
   {
      int total=SymbolsTotal(InpScanMarketWatch);
      for(int i=0;i<total && g_symbolCount<MathMin(MAX_SCAN,InpMaxSymbols);i++)
      {
         string s=SymbolName(i,InpScanMarketWatch);
         if(s!="") AddSymbol(s);
      }
   }
   Print("SCANNER_UNIVERSE | symbols=",g_symbolCount,
         " source=",(StringLen(InpSymbolsCSV)>0?"EXPLICIT_CSV":(InpScanMarketWatch?"MARKET_WATCH":"ALL_BROKER_SYMBOLS")),
         " crypto24x7Expected=",(InpCryptoExpected24x7?"true":"false"),
         " note=24X7_IS_EXPECTATION_NOT_LIVE_FEED_OR_BROKER_PERMISSION_PROOF");
}

bool QuoteReady(string symbol,string &why)
{
   why="";
   if(MarketInfo(symbol,MODE_TRADEALLOWED)<=0.0) { why="SYMBOL_TRADE_DISABLED"; return(false); }
   datetime tickTime=(datetime)MarketInfo(symbol,MODE_TIME);
   if(tickTime<=0) { why="NO_TICK_TIMESTAMP"; return(false); }
   int age=(int)(TimeCurrent()-tickTime);
   if(age<0 || age>InpMaxQuoteAgeSec)
   {
      why="STALE_QUOTE ageSec="+IntegerToString(age);
      return(false);
   }
   double bid=MarketInfo(symbol,MODE_BID), ask=MarketInfo(symbol,MODE_ASK);
   double point=MarketInfo(symbol,MODE_POINT);
   if(bid<=0.0 || ask<=bid || point<=0.0) { why="INVALID_BID_ASK_POINT"; return(false); }
   // A 24/7 crypto calendar never overrides terminal/account permissions.
   // Broker permission and a fresh tick remain authoritative for every asset.
   if(!IsTradeAllowed()) { why="TERMINAL_TRADE_NOT_ALLOWED"; return(false); }
   return(true);
}

int CountOurPositions(string symbol,int typeFilter)
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(symbol!="" && OrderSymbol()!=symbol) continue;
      int t=OrderType();
      if(t!=OP_BUY && t!=OP_SELL) continue;
      if(typeFilter>=0 && t!=typeFilter) continue;
      n++;
   }
   return(n);
}

double PriceValuePerUnit(string symbol)
{
   double point=MarketInfo(symbol,MODE_POINT);
   double tickSizePoints=MarketInfo(symbol,MODE_TICKSIZE);
   double tickValue=MarketInfo(symbol,MODE_TICKVALUE);
   if(point<=0.0 || tickSizePoints<=0.0 || tickValue<=0.0) return(0.0);
   double tickSizePrice=tickSizePoints*point;
   if(tickSizePrice<=0.0) return(0.0);
   return(tickValue/tickSizePrice);
}

double OpenRiskMoney()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      string s=OrderSymbol();
      double v=PriceValuePerUnit(s);
      if(v<=0.0) return(1.0e100); // Unknown contract value: fail closed for new risk
      double stop=OrderStopLoss();
      if(stop<=0.0) return(1.0e100);
      double distance=(type==OP_BUY?OrderOpenPrice()-stop:stop-OrderOpenPrice());
      if(distance>0.0) total+=distance*OrderLots()*v;
   }
   return(total);
}

double StrategyCapitalUSD() { return(InpStrategicCapitalUSD); }

double EntryRiskBudget()
{
   double strategicRisk=StrategyCapitalUSD()*InpRiskPercent/100.0;
   if(InpRiskUSDOverride>0.0) return(MathMin(InpRiskUSDOverride,strategicRisk));
   return(strategicRisk);
}

double AggregateRiskCapUSD() { return(StrategyCapitalUSD()*InpMaxAggregateRiskPct/100.0); }

bool AdaptiveDistances(string symbol,int signal,double entry,double atr,double &slDist,double &tpDist)
{
   if(atr<=0.0 || entry<=0.0) return(false);
   double baseSL=atr*InpSL_ATR;
   double structural=(signal>0 ? entry-iLow(symbol,InpSignalTF,1)+atr*InpSLStructureBufferATR
                               : iHigh(symbol,InpSignalTF,1)-entry+atr*InpSLStructureBufferATR);
   if(structural>atr*InpMaxSL_ATR) return(false); // Never compress a structural stop inside the signal candle.
   slDist=MathMax(atr*InpMinSL_ATR,MathMax(baseSL,structural));
   slDist=MathMin(slDist,atr*InpMaxSL_ATR);
   if(slDist<=0.0) return(false);
   double upper=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_UPPER,1);
   double lower=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_LOWER,1);
   double width=(upper>lower ? upper-lower : 0.0);
   double widthAtr=(width>0.0 ? width/atr : 2.0);
   double adaptiveR=1.30+0.25*widthAtr;
   adaptiveR=MathMax(InpMinAdaptiveTP_R,MathMin(InpMaxAdaptiveTP_R,adaptiveR));
   tpDist=slDist*adaptiveR;
   return(tpDist>0.0);
}

double CalcLots(string symbol,double stopDistance,double riskMoney)
{
   double v=PriceValuePerUnit(symbol);
   double minLot=MarketInfo(symbol,MODE_MINLOT);
   double maxLot=MarketInfo(symbol,MODE_MAXLOT);
   double step=MarketInfo(symbol,MODE_LOTSTEP);
   if(v<=0.0 || stopDistance<=0.0 || riskMoney<=0.0 || step<=0.0 || minLot<=0.0) return(0.0);
   double raw=riskMoney/(stopDistance*v);
   double lots=MathFloor(raw/step+1e-9)*step;
   // Never round UP to broker minimum if that exceeds the money-risk budget.
   if(lots<minLot) return(0.0);
   lots=MathMin(lots,maxLot);
   int lotDigits=2;
   if(step>=1.0) lotDigits=0;
   else if(step>=0.1) lotDigits=1;
   else if(step<0.01) lotDigits=3;
   return(NormalizeDouble(lots,lotDigits));
}

bool IsNewSignalBar(int index,string symbol,datetime &barTime)
{
   barTime=iTime(symbol,InpSignalTF,0);
   if(barTime<=0 || barTime==g_lastSignalBar[index]) return(false);
   g_lastSignalBar[index]=barTime;
   return(true);
}

// Signal codes: 2=breakout buy, 1=rebound buy, -1=rebound sell, -2=breakout sell, 0=none, 99=conflict.
int BollingerSignal(string symbol,string &signalName,string &detail)
{
   signalName="NONE"; detail="";
   if(iBars(symbol,InpSignalTF)<MathMax(InpMinBars,InpBBPeriod+5)) { detail="INSUFFICIENT_HISTORY"; return(0); }
   double upper1=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_UPPER,1);
   double lower1=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_LOWER,1);
   double upper2=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_UPPER,2);
   double lower2=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_LOWER,2);
   if(upper1<=0.0 || lower1<=0.0 || upper2<=0.0 || lower2<=0.0) { detail="BOLLINGER_DATA_UNAVAILABLE"; return(0); }

   double o1=iOpen(symbol,InpSignalTF,1), c1=iClose(symbol,InpSignalTF,1);
   double h1=iHigh(symbol,InpSignalTF,1), l1=iLow(symbol,InpSignalTF,1);
   double c2=iClose(symbol,InpSignalTF,2);
   bool bull=(c1>o1), bear=(c1<o1);

   bool reboundBuy=(l1<=lower1 && c1>lower1 && (!InpRequireCandleDirection || bull));
   bool reboundSell=(h1>=upper1 && c1<upper1 && (!InpRequireCandleDirection || bear));
   bool breakoutBuy=(c1>upper1 && c2<=upper2);
   bool breakoutSell=(c1<lower1 && c2>=lower2);

   bool buy=(InpEnableRebound && reboundBuy)||(InpEnableBreakout && breakoutBuy);
   bool sell=(InpEnableRebound && reboundSell)||(InpEnableBreakout && breakoutSell);
   if(buy && sell) { signalName="CONFLICT"; detail="OPPOSING_BOLLINGER_SETUPS_SAME_BAR"; return(99); }
   if(!buy && !sell) return(0);

   if(breakoutBuy) { signalName="BREAKOUT_BUY"; return(2); }
   if(reboundBuy) { signalName="REBOUND_BUY"; return(1); }
   if(breakoutSell) { signalName="BREAKOUT_SELL"; return(-2); }
   if(reboundSell) { signalName="REBOUND_SELL"; return(-1); }
   return(0);
}

//--- News guard file contract: #updated_epoch_utc=..., then scope,key,fromEpochUTC,untilEpochUTC,BLOCK,reason,eventEpochUTC
void NewsGuardLoad()
{
   datetime now=TimeGMT();
   if(g_newsLastLoad>0 && now-g_newsLastLoad<30) return;
   g_newsLastLoad=now;
   g_newsCount=0; g_newsFileOk=false; g_newsUpdated=0;
   int flags=FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE;
   if(InpNewsUseCommonFolder) flags|=FILE_COMMON;
   int h=FileOpen(InpNewsFileName,flags);
   if(h==INVALID_HANDLE)
   {
      if(now-g_newsLastStateLog>=900)
      {
         g_newsLastStateLog=now;
         Print("NEWS_GUARD_STATE | file=",InpNewsFileName," status=FILE_NOT_FOUND_FAIL_OPEN err=",GetLastError());
      }
      return;
   }
   while(!FileIsEnding(h) && g_newsCount<NEWS_MAX_ROWS)
   {
      string line=FileReadString(h);
      StringTrimLeft(line); StringTrimRight(line);
      if(line=="") continue;
      if(StringGetCharacter(line,0)=='#')
      {
         int p=StringFind(line,"updated_epoch_utc=");
         if(p>=0) g_newsUpdated=(datetime)StrToInteger(StringSubstr(line,p+18));
         continue;
      }
      string parts[];
      int n=StringSplit(line,StringGetCharacter(",",0),parts);
      if(n<6 || parts[4]!="BLOCK") continue;
      g_newsScope[g_newsCount]=parts[0];
      g_newsKey[g_newsCount]=Upper(parts[1]);
      g_newsFrom[g_newsCount]=(datetime)StrToInteger(parts[2]);
      g_newsUntil[g_newsCount]=(datetime)StrToInteger(parts[3]);
      g_newsReason[g_newsCount]=parts[5];
      g_newsEvent[g_newsCount]=(n>=7?(datetime)StrToInteger(parts[6]):g_newsFrom[g_newsCount]+900);
      g_newsCount++;
   }
   FileClose(h);
   g_newsFileOk=(g_newsUpdated>0 && now-g_newsUpdated<=InpNewsFileMaxAgeMin*60);
   if(!g_newsFileOk && now-g_newsLastStateLog>=900)
   {
      g_newsLastStateLog=now;
      Print("NEWS_GUARD_STATE | file=",InpNewsFileName," status=STALE_OR_NO_HEADER_FAIL_OPEN updatedUTC=",
            TimeToString(g_newsUpdated,TIME_DATE|TIME_SECONDS)," maxAgeMin=",InpNewsFileMaxAgeMin);
   }
}

void NewsSymbolCurrencies(string symbol,string &c1,string &c2)
{
   c1=""; c2="";
   string s=Upper(symbol);
   if(StringFind(s,"USDT")>=0 || StringFind(s,"USDC")>=0)
   {
      if(InpNewsUsdAffectsUsdt) c1="USD";
      return;
   }
   if(StringLen(s)>=6)
   {
      string a=StringSubstr(s,0,3), b=StringSubstr(s,3,3);
      string known=" USD EUR GBP JPY CHF CAD AUD NZD MXN ZAR SEK NOK DKK PLN CZK HUF TRY SGD HKD CNH CNY ";
      if(StringFind(known," "+a+" ")>=0 && StringFind(known," "+b+" ")>=0) { c1=a; c2=b; }
   }
}

bool NewsGuardWouldBlock(string symbol,string &why)
{
   why="";
   if(!InpNewsGuardEnabled) return(false);
   NewsGuardLoad();
   if(!g_newsFileOk || g_newsCount<=0) return(false);
   datetime now=TimeGMT();
   string c1,c2; NewsSymbolCurrencies(symbol,c1,c2);
   string us=Upper(symbol);
   for(int i=0;i<g_newsCount;i++)
   {
      if(now<g_newsFrom[i] || now>g_newsUntil[i]) continue;
      bool hit=false;
      if(g_newsScope[i]=="ALL") hit=true;
      else if(g_newsScope[i]=="SYM" && g_newsKey[i]==us) hit=true;
      else if(g_newsScope[i]=="CCY" && StringLen(g_newsKey[i])>0 &&
              (g_newsKey[i]==c1 || g_newsKey[i]==c2)) hit=true;
      if(hit)
      {
         why=g_newsScope[i]+":"+g_newsKey[i]+":"+g_newsReason[i];
         return(true);
      }
   }
   return(false);
}

void NewsShadowLog(string symbol)
{
   if(!InpNewsGuardEnabled) return;
   string why="";
   if(!NewsGuardWouldBlock(symbol,why)) return;
   datetime now=TimeGMT();
   int idx=-1;
   for(int i=0;i<g_newsLogCount;i++) if(g_newsLogSymbol[i]==symbol) { idx=i; break; }
   bool logNow=true;
   if(idx>=0)
   {
      if(now-g_newsLogTime[idx]<InpNewsLogThrottleMin*60) logNow=false;
      else g_newsLogTime[idx]=now;
   }
   else if(g_newsLogCount<NEWS_MAX_ROWS)
   {
      g_newsLogSymbol[g_newsLogCount]=symbol;
      g_newsLogTime[g_newsLogCount]=now;
      g_newsLogCount++;
   }
   if(logNow)
      Print("NEWS_GUARD_SHADOW_WOULD_BLOCK | symbol=",symbol," reason=",why,
            " shadowOnly=true action=SCOUT_ENTRY_NOT_BLOCKED serverTime=",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   // Safety invariant: no return value from this function can veto a SCOUT.
}

bool NewsEventNear(string symbol,double &minutesToEvent,string &why)
{
   minutesToEvent=0.0; why="";
   if(!InpNewsGuardEnabled || !g_newsFileOk || g_newsCount<=0) return(false);
   string c1,c2; NewsSymbolCurrencies(symbol,c1,c2);
   string us=Upper(symbol);
   datetime now=TimeGMT();
   bool found=false; double best=0.0;
   for(int i=0;i<g_newsCount;i++)
   {
      bool hit=false;
      if(g_newsScope[i]=="ALL") hit=true;
      else if(g_newsScope[i]=="SYM" && g_newsKey[i]==us) hit=true;
      else if(g_newsScope[i]=="CCY" && StringLen(g_newsKey[i])>0 &&
              (g_newsKey[i]==c1 || g_newsKey[i]==c2)) hit=true;
      if(!hit) continue;
      double mins=(double)(g_newsEvent[i]-now)/60.0;
      if(mins>InpNewsPreProtectLeadMin || mins<-InpNewsPostProtectMin) continue;
      if(!found || MathAbs(mins)<MathAbs(best))
      {
         found=true; best=mins;
         why=g_newsScope[i]+":"+g_newsKey[i]+":"+g_newsReason[i];
      }
   }
   minutesToEvent=best;
   return(found);
}

//--- Entry and execution
bool SendScout(string symbol,int signal,string signalName)
{
   int cmd=(signal>0?OP_BUY:OP_SELL);
   if((cmd==OP_BUY && !InpAllowBuy)||(cmd==OP_SELL && !InpAllowSell)) return(false);
   if(CountOurPositions("",-1)>=InpMaxOpenPositions) return(false);
   if(CountOurPositions(symbol,-1)>=InpMaxPositionsPerSymbol) return(false);

   string quoteWhy="";
   if(!QuoteReady(symbol,quoteWhy)) { Print("ENTRY_SKIP | symbol=",symbol," reason=QUOTE_NOT_READY detail=",quoteWhy); return(false); }
   double point=MarketInfo(symbol,MODE_POINT);
   int digits=(int)MarketInfo(symbol,MODE_DIGITS);
   double atr=iATR(symbol,InpSignalTF,InpATRPeriod,1);
   double bid=MarketInfo(symbol,MODE_BID), ask=MarketInfo(symbol,MODE_ASK);
   double entryPrice=(cmd==OP_BUY?ask:bid);
   double slDist=0.0,tpDist=0.0;
   if(point<=0.0 || atr<=0.0 || !AdaptiveDistances(symbol,signal,entryPrice,atr,slDist,tpDist))
   { Print("ENTRY_SKIP | symbol=",symbol," reason=ADAPTIVE_ATR_BB_DISTANCE_UNAVAILABLE"); return(false); }
   double stopLevel=MathMax(MarketInfo(symbol,MODE_STOPLEVEL),MarketInfo(symbol,MODE_FREEZELEVEL))*point;
   if(slDist<=stopLevel+point || tpDist<=stopLevel+point)
   {
      Print("ENTRY_SKIP | symbol=",symbol," reason=BROKER_STOP_LEVEL slDist=",DoubleToString(slDist,digits),
            " required=",DoubleToString(stopLevel+point,digits));
      return(false);
   }

   bid=MarketInfo(symbol,MODE_BID); ask=MarketInfo(symbol,MODE_ASK);
   double spread=ask-bid;
   if(spread>InpMaxSpreadPoints*point || spread>slDist*InpMaxSpreadPctOfSL/100.0)
   {
      Print("ENTRY_SKIP | symbol=",symbol," reason=SPREAD_GATE spreadPts=",DoubleToString(spread/point,1));
      return(false);
   }

   double riskBudget=EntryRiskBudget();
   double lots=CalcLots(symbol,slDist,riskBudget);
   if(lots<=0.0)
   {
      Print("ENTRY_SKIP | symbol=",symbol," reason=MIN_LOT_EXCEEDS_RISK_BUDGET riskUSD=",DoubleToString(riskBudget,2));
      return(false);
   }
   double value=PriceValuePerUnit(symbol);
   double newRisk=lots*slDist*value;
   double aggregateCap=AggregateRiskCapUSD();
   if(value<=0.0 || OpenRiskMoney()+newRisk>aggregateCap)
   {
      Print("ENTRY_SKIP | symbol=",symbol," reason=AGGREGATE_RISK_CAP newRisk=",DoubleToString(newRisk,2),
            " openRisk=",DoubleToString(OpenRiskMoney(),2)," cap=",DoubleToString(aggregateCap,2));
      return(false);
   }

   int type=cmd;
   double price=(cmd==OP_BUY?ask:bid);
   double sl=(cmd==OP_BUY?price-slDist:price+slDist);
   double tp=(cmd==OP_BUY?price+tpDist:price-tpDist);
   price=NormalizeDouble(price,digits); sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);
   ResetLastError();
   double freeBefore=AccountFreeMargin();
   double freeAfter=AccountFreeMarginCheck(symbol,cmd,lots);
   double marginRequired=freeBefore-freeAfter;
   if(freeAfter<=0.0 || marginRequired<=0.0 || marginRequired>freeBefore*InpMaxMarginUsePctFree/100.0)
   {
      Print("ENTRY_SKIP | symbol=",symbol," reason=MARGIN_GUARD lots=",DoubleToString(lots,3),
            " marginRequired=",DoubleToString(marginRequired,2)," freeMargin=",DoubleToString(freeBefore,2),
            " maxUsePct=",DoubleToString(InpMaxMarginUsePctFree,1));
      return(false);
   }
   int ticket=OrderSend(symbol,type,lots,price,InpSlippagePoints,sl,tp,
                        EA_NAME+" "+signalName,InpMagic,0,(cmd==OP_BUY?clrDodgerBlue:clrTomato));
   if(ticket>0)
   {
      GlobalVariableSet("BBM_INITR_"+IntegerToString(ticket),slDist);
      Print("SCOUT_OPEN | ticket=",ticket," symbol=",symbol," signal=",signalName,
            " lots=",DoubleToString(lots,3)," riskUSD=",DoubleToString(newRisk,2),
            " strategicCapitalUSD=",DoubleToString(StrategyCapitalUSD(),2),
            " adaptiveTP_R=",DoubleToString(tpDist/slDist,2)," marginRequired=",DoubleToString(marginRequired,2),
            " sl=",DoubleToString(sl,digits)," tp=",DoubleToString(tp,digits),
            " strategy=BOLLINGER_ONLY newsMode=SHADOW");
      return(true);
   }
   int err=GetLastError();
   Print("ORDER_SEND_FAIL | symbol=",symbol," signal=",signalName," error=",err);
   return(false);
}

void ManageOpenPositions()
{
   NewsGuardLoad();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      string symbol=OrderSymbol();
      string quoteWhy="";
      if(!QuoteReady(symbol,quoteWhy)) { if(InpLogScannerDiagnostics) Print("MANAGE_SKIP | ticket=",OrderTicket()," symbol=",symbol," reason=STALE_OR_INVALID_QUOTE detail=",quoteWhy); continue; }
      double point=MarketInfo(symbol,MODE_POINT);
      int digits=(int)MarketInfo(symbol,MODE_DIGITS);
      double atr=iATR(symbol,InpSignalTF,InpATRPeriod,1);
      if(point<=0.0 || atr<=0.0) continue;
      double dir=(type==OP_BUY?1.0:-1.0);
      double bid=MarketInfo(symbol,MODE_BID), ask=MarketInfo(symbol,MODE_ASK);
      double market=(type==OP_BUY?bid:ask);
      string riskKey="BBM_INITR_"+IntegerToString(OrderTicket());
      double initialRisk=(GlobalVariableCheck(riskKey)?GlobalVariableGet(riskKey):MathAbs(OrderOpenPrice()-OrderStopLoss()));
      if(initialRisk<=0.0) continue;
      double favorable=dir*(market-OrderOpenPrice());
      double r=favorable/initialRisk;
      double candidate=OrderStopLoss();
      bool improve=false;
      if(InpBreakEvenEnabled && r>=InpBreakEvenAtR)
      {
         double be=OrderOpenPrice()+dir*(InpBreakEvenLockR*initialRisk);
         if(type==OP_BUY && (candidate<=0.0 || be>candidate+point)) { candidate=be; improve=true; }
         if(type==OP_SELL && (candidate<=0.0 || be<candidate-point)) { candidate=be; improve=true; }
      }
      if(InpTrailingEnabled && r>=InpTrailStartR)
      {
         double trail=market-dir*(atr*InpTrailDistanceATR);
         if(type==OP_BUY && trail>candidate+point) { candidate=trail; improve=true; }
         if(type==OP_SELL && (candidate<=0.0 || trail<candidate-point)) { candidate=trail; improve=true; }
      }

      // Event-window protection: secure a fraction of existing net profit with SL only.
      // It never widens an SL and never changes or vetoes a SCOUT entry.
      double eventMinutes=0.0; string eventWhy="";
      double liveNet=OrderProfit()+OrderSwap()+OrderCommission();
      if(liveNet>=InpNewsProtectMinNetUSD && InpNewsProtectKeepPct>0.0 &&
         InpNewsProtectKeepPct<100.0 && NewsEventNear(symbol,eventMinutes,eventWhy))
      {
         double moneyPerPrice=PriceValuePerUnit(symbol)*OrderLots();
         double closeCost=MathAbs(OrderCommission())+MathMax(0.0,-OrderSwap());
         if(moneyPerPrice>0.0)
         {
            double targetNet=liveNet*InpNewsProtectKeepPct/100.0;
            double requiredGross=targetNet-OrderSwap()-OrderCommission()+closeCost;
            double lockMove=requiredGross/moneyPerPrice;
            double newsSL=OrderOpenPrice()+dir*lockMove;
            double minDistNews=MathMax(MarketInfo(symbol,MODE_STOPLEVEL),MarketInfo(symbol,MODE_FREEZELEVEL))*point;
            bool valid=(type==OP_BUY ? (newsSL>OrderOpenPrice() && newsSL<bid-minDistNews)
                                    : (newsSL<OrderOpenPrice() && newsSL>ask+minDistNews));
            bool tighter=(type==OP_BUY ? (candidate<=0.0 || newsSL>candidate+point)
                                       : (candidate<=0.0 || newsSL<candidate-point));
            if(valid && tighter)
            {
               candidate=newsSL; improve=true;
               Print("NEWS_PRE_PROTECT_STOP_ARMED | ticket=",OrderTicket()," symbol=",symbol,
                     " netNow=",DoubleToString(liveNet,2)," protectedNetPct=",DoubleToString(InpNewsProtectKeepPct,1),
                     " minutesToEvent=",DoubleToString(eventMinutes,1)," event=",eventWhy,
                     " action=PROTECTIVE_SL_ONLY_NO_WIDENING");
            }
         }
      }
      if(!improve) continue;
      // Never widen the original or already-tightened stop.
      if(type==OP_BUY && OrderStopLoss()>0.0 && candidate<=OrderStopLoss()+point) continue;
      if(type==OP_SELL && OrderStopLoss()>0.0 && candidate>=OrderStopLoss()-point) continue;
      double minDist=MathMax(MarketInfo(symbol,MODE_STOPLEVEL),MarketInfo(symbol,MODE_FREEZELEVEL))*point;
      if(type==OP_BUY && candidate>=bid-minDist) continue;
      if(type==OP_SELL && candidate<=ask+minDist) continue;
      string throttleKey="BBM_MOD_"+IntegerToString(OrderTicket());
      datetime last=0;
      if(GlobalVariableCheck(throttleKey)) last=(datetime)GlobalVariableGet(throttleKey);
      if(TimeCurrent()-last<InpModifyThrottleSec) continue;
      ResetLastError();
      if(OrderModify(OrderTicket(),OrderOpenPrice(),NormalizeDouble(candidate,digits),OrderTakeProfit(),0,clrNONE))
      {
         GlobalVariableSet(throttleKey,(double)TimeCurrent());
         Print("PROTECTIVE_SL_UPDATE | ticket=",OrderTicket()," symbol=",symbol,
               " currentR=",DoubleToString(r,2)," sl=",DoubleToString(candidate,digits),
               " invariant=SL_NEVER_WIDENED");
      }
      else
      {
         int e=GetLastError();
         if(e!=1) Print("SL_MODIFY_FAIL | ticket=",OrderTicket()," symbol=",symbol," error=",e);
      }
   }
}

//--- Optional funded add-on. Only uses locked profit; aggregate risk cap remains absolute.
bool TryFundedAddOn(string symbol,int signal,string signalName)
{
   // Hard-disabled in v1.0.1. No pyramiding: exposure is controlled by risk sizing and margin checks.
   return(false);
}

//+------------------------------------------------------------------+
void ScanOne(int index)
{
   string symbol=g_symbols[index], why="";
   if(!QuoteReady(symbol,why))
   {
      if(InpLogScannerDiagnostics) Print("SCAN_SKIP | symbol=",symbol," reason=",why,
         " cryptoExpected24x7=",(IsCryptoSymbol(symbol)&&InpCryptoExpected24x7?"true":"false"));
      return;
   }
   if(iBars(symbol,InpSignalTF)<MathMax(InpMinBars,InpBBPeriod+5))
   {
      if(InpLogScannerDiagnostics) Print("SCAN_SKIP | symbol=",symbol," reason=INSUFFICIENT_HISTORY bars=",iBars(symbol,InpSignalTF));
      return;
   }
   datetime bar=0;
   if(!IsNewSignalBar(index,symbol,bar)) return;
   int age=(int)(TimeCurrent()-bar);
   if(age<0 || age>InpEntryWindowSeconds)
   {
      Print("SCAN_SKIP | symbol=",symbol," reason=ENTRY_WINDOW_EXPIRED barAgeSec=",age);
      return;
   }
   string name="",detail="";
   int signal=BollingerSignal(symbol,name,detail);
   if(signal==99)
   {
      Print("SIGNAL_ABSTAIN | symbol=",symbol," reason=",detail," strategy=BOLLINGER_ONLY");
      return;
   }
   if(signal==0)
   {
      if(detail!="") Print("SIGNAL_UNAVAILABLE | symbol=",symbol," reason=",detail);
      return;
   }
   NewsShadowLog(symbol); // Observational only: SCOUT entries remain eligible.
   if(CountOurPositions(symbol,-1)>0)
   {
      if(TryFundedAddOn(symbol,signal,name)) return;
      Print("SIGNAL_SKIP | symbol=",symbol," signal=",name," reason=SYMBOL_POSITION_LIMIT");
      return;
   }
   SendScout(symbol,signal,name);
}

void OnTimer()
{
   if(g_symbolCount<=0 || TimeCurrent()-g_lastScan<MathMax(1,InpScanIntervalSeconds)) return;
   g_lastScan=TimeCurrent();
   ManageOpenPositions();
   for(int i=0;i<g_symbolCount;i++) ScanOne(i);
}

int OnInit()
{
   if(InpBBPeriod<2 || InpBBDeviation<=0.0 || InpRiskPercent<=0.0 ||
      InpMaxAggregateRiskPct<=0.0 || InpMaxOpenPositions<1 || InpStrategicCapitalUSD<=0.0 ||
      InpMaxMarginUsePctFree<=0.0 || InpMaxMarginUsePctFree>100.0 ||
      InpMinAdaptiveTP_R<1.0 || InpMaxAdaptiveTP_R<InpMinAdaptiveTP_R || InpSLStructureBufferATR<0.0)
   {
      Print("INIT_FAILED | reason=INVALID_INPUT_CONFIGURATION");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(AccountCurrency()!="USD")
   {
      Print("INIT_FAILED | reason=ACCOUNT_CURRENCY_MUST_BE_USD_FOR_FIXED_USD_RISK currency=",AccountCurrency());
      return(INIT_FAILED);
   }
   if(!InpNewsGuardShadowOnly)
   {
      Print("INIT_FAILED | reason=NEWS_GUARD_MUST_REMAIN_SHADOW_ONLY_IN_V1_0_1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   BuildUniverse();
   if(g_symbolCount<=0)
   {
      Print("INIT_FAILED | reason=EMPTY_SYMBOL_UNIVERSE");
      return(INIT_FAILED);
   }
   EventSetTimer(1);
   Print("EA_READY | name=",EA_NAME," version=",EA_VER,
         " symbols=",g_symbolCount,
         " signalIndicators=BOLLINGER_BANDS_ONLY",
         " strategicCapitalUSD=",DoubleToString(StrategyCapitalUSD(),2),
         " riskPerTradeUSD=",DoubleToString(EntryRiskBudget(),2),
         " aggregateRiskCapUSD=",DoubleToString(AggregateRiskCapUSD(),2),
         " adaptiveSL=ATR_PLUS_SIGNAL_STRUCTURE adaptiveTP=BB_WIDTH_VS_ATR",
         " marginGuardMaxFreePct=",DoubleToString(InpMaxMarginUsePctFree,1),
         " pyramiding=HARD_DISABLED",
         " modes=REBOUND+BREAKOUT conflictPolicy=ABSTAIN",
         " newsGuard=SHADOW_ONLY scoutsNotBlocked=true",
         " fundedAddOns=HARD_DISABLED",
         " crypto24x7=EXPECTED_ONLY_FRESH_QUOTE_AND_BROKER_PERMISSION_REQUIRED");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("EA_STOP | name=",EA_NAME," reason=",reason);
}

void OnTick()
{
   ManageOpenPositions();
}
//+------------------------------------------------------------------+