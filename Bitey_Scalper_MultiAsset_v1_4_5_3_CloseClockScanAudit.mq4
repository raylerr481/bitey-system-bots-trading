//+------------------------------------------------------------------+
//| Bitey_Scalper_MultiAsset_v1_4_5_3_CloseClockScanAudit.mq4                         |
//| Diagnostic-only market-data scanner; no new orders are permitted.  |
//| Existing positions remain managed by the original exit controls.  |
//| No strategy, sizing, or risk parameters are intentionally changed.|
//+------------------------------------------------------------------+
#property strict
#property version   "1.453"
#property description "Bitey v1.4.5.3 diagnostic-only scanner: close attribution, clock audit, scan summaries and market-data diagnostics"

#define EA_VERSION          "1.4.5.3"
#define MAX_SYMBOLS         256
#define HARD_MAX_POSITIONS  5

//--- universe and timeframes
input string           InpSymbolsCSV            = "";      // Blank = Market Watch; broker-listed USDT symbols are always added
input ENUM_TIMEFRAMES  InpSignalTF              = PERIOD_M5;
input ENUM_TIMEFRAMES  InpHTF                   = PERIOD_M15; // Higher-timeframe bias (trend regime only)
input bool             InpUseHTFFilter          = true;
input int              InpMagic                 = 21102026;

//--- risk
input double           InpReferenceCapitalUSD   = 500.0;
input double           InpRiskPctPerTrade       = 0.5;     // 5 positions x 0.5% = 2.5% aggregate
input double           InpMaxAggregateRiskPct   = 2.5;
input double           InpMaxCurrencyRiskPct    = 1.5;     // Maximum stop-risk attributed to either FX currency
input double           InpDailyLossPct          = 3.0;     // Blocks NEW entries; open trades stay managed
input int              InpMaxOpenPositions      = 5;       // Clamped to 1..5, one position per asset

//--- direction
input bool             InpAllowBuy              = true;
input bool             InpAllowSell             = true;

//--- signal
input int              InpFamilyMinVotes        = 3;       // Variants (of 8) needed for a family to speak
input double           InpTrendADX              = 20.0;    // ADX >= this: trend regime, otherwise range regime
input double           InpMinADX                = 10.0;    // Dead-market filter
input int              InpATRPeriod             = 14;
input double           InpStopATR               = 1.5;
input double           InpRewardRisk            = 1.5;

//--- execution filters
input double           InpMaxSpreadPctOfStop    = 12.0;    // Diagnostic warning threshold
input double           InpHardMaxSpreadPctOfStop = 35.0;    // Hard execution-quality cap; 0 = disabled
input double           InpMinEntryScore          = 0.0;     // Reject weak/negative-ranked signals below this score
input int              InpMaxSpreadPoints       = 0;       // Optional absolute cap, 0 = off
input int              InpMaxQuoteAgeSec        = 120;
input int              InpSlippagePoints        = 20;
input int              InpBroker133CooldownMinutes = 60; // 0 = block until EA restart
input int              InpBroker133RecheckMinutes  = 60; // Permission-only recheck interval after cooldown
input int              InpMinBars               = 250;
input bool             InpUseSessionFilter      = true;    // Server hours; crypto is exempt
input int              InpSessionStartHour      = 7;
input int              InpSessionEndHour        = 21;
input int              InpCooldownBars          = 6;       // Bars to wait on a symbol after a losing trade
input int              InpMaxHoldBars           = 48;      // Time exit (0 = off)

//--- adaptive SL/TP
input bool             InpEnableAdaptiveExits   = true;
input double           InpBreakEvenTriggerATR   = 1.0;
input double           InpBreakEvenLockATR      = 0.15;
input double           InpTrailStartATR         = 1.5;
input double           InpTrailDistanceATR      = 1.2;
input double           InpTrailStepATR          = 0.10;    // Minimum SL improvement per modification
input double           InpTPExpandTriggerATR    = 1.0;
input double           InpTPExpandBufferATR     = 1.0;
input double           InpTPExpandADXMin        = 22.0;
input double           InpTPMaxDistanceATR      = 5.0;
input double           InpSmallProfitCloseUSD   = 0.10;    // Close when estimated net after closing costs reaches +0.10 account currency
input double           InpSmallLossCloseUSD     = 0.0;     // DISABLED by default; broker-side initial SL remains the loss protection
input int              InpSmallLossMinHoldSeconds = 60;      // If explicitly enabled, never use this exit during the first 60 seconds
input int              InpProgressionLookbackBars = 3;     // Closed-bar EMA slope lookback for directional progression
input double           InpProgressionADXMin     = 18.0;    // Minimum ADX for directional progression confirmation
input double           InpTrendRunnerTriggerNetUSD = 0.20;  // Activate profit runner only after this estimated net profit (account currency)
input double           InpWeakTrendTrailATR     = 0.60;    // Tighten trailing distance when progression turns against the trade
input double           InpNetTargetR            = 0.0;     // Optional close at +N R net (0 = off; let adaptive TP run)
input double           InpNetLockMinUSD          = 0.10;    // Minimum net amount protected after runner activation
input double           InpNetLockGivebackPct     = 35.0;    // Protect (100-this)% of peak floating net profit
input double           InpNetLockStepUSD         = 0.05;    // Persist peak after each small improvement
input double           InpEstimatedCloseCommissionPerLot = 0.0; // Configure broker close commission per 1.0 lot, account currency
input int              InpNetLockSlippagePoints  = 3;       // Adverse stop-fill slippage reserve

#define DIAGNOSTIC_ONLY_BUILD true
input bool             InpEnableTrading         = false;   // secondary safety: candidate logging only
input bool             InpLogRejects            = false;
input bool             InpLogBarScanDiagnostics  = true;    // Log per-symbol bar-scan state changes
input bool             InpShowScanDashboard     = true;    // Show scan counts and last indicator snapshot on chart

string   g_symbols[MAX_SYMBOLS];
string   g_keys[MAX_SYMBOLS];
datetime g_lastBar[MAX_SYMBOLS];
bool     g_barBaselineSet[MAX_SYMBOLS];
string   g_lastBarDiagState[MAX_SYMBOLS];
string   g_lastMarketDataDiagState[MAX_SYMBOLS];
int      g_symbolCount = 0;
uint     g_lastCycleTick = 0;
datetime g_lastHeartbeat = 0;
uint     g_lastHeartbeatTick = 0;
uint     g_lastDailyLossLogTick = 0;
int      g_cycleNewBars = 0;
int      g_cycleNoNewBar = 0;
int      g_cycleHistoryUnavailable = 0;
int      g_cycleInsufficientHistory = 0;
int      g_cyclePrefilterOK = 0;
int      g_cycleIndicatorRuns = 0;
int      g_cycleSignalCandidates = 0;
int      g_cycleBuySignals = 0;
int      g_cycleSellSignals = 0;
int      g_cyclePrefilterRejects = 0;
int      g_cycleSignalRejects = 0;
int      g_cycleCapacityRejects = 0;
datetime g_lastPermissionDiagnostic = 0;
datetime g_lastQuoteStamp[MAX_SYMBOLS];
uint     g_lastQuoteChangeTick[MAX_SYMBOLS];
string   g_lastScanSymbol = "-";
string   g_lastIndicatorSummary = "Waiting for first indicator evaluation";
string   g_lastExecutionRejectCategory = "";
datetime g_sessionStartTime = 0;
bool     g_sessionBlocked[MAX_SYMBOLS];
uint     g_sessionBlockUntilTick[MAX_SYMBOLS];
uint     g_sessionNextPermissionCheckTick[MAX_SYMBOLS];
datetime g_sessionBlockUntilTime[MAX_SYMBOLS];
int      g_sessionCandidates[MAX_SYMBOLS];
int      g_sessionAttempts[MAX_SYMBOLS];
int      g_sessionAccepted[MAX_SYMBOLS];
int      g_sessionRejected[MAX_SYMBOLS];
int      g_sessionClosed[MAX_SYMBOLS];
double   g_sessionNet[MAX_SYMBOLS];
int      g_processedCloseTickets[2048];
int      g_processedCloseCount = 0;
int      g_eaCloseReasonTickets[2048];
string   g_eaCloseReasonText[2048];
int      g_eaCloseReasonCount = 0;

string   g_candSym[MAX_SYMBOLS];
int      g_candCmd[MAX_SYMBOLS];
double   g_candScore[MAX_SYMBOLS];
double   g_candSpreadPct[MAX_SYMBOLS];
double   g_candPriority[MAX_SYMBOLS];
int      g_lastExecutionErrorCode = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   ParseSymbols();
   if(g_symbolCount<=0) { Print("INIT_ERROR | no symbols found"); return(INIT_FAILED); }
   g_sessionStartTime=TimeCurrent();
   for(int i=0;i<g_symbolCount;i++)
   {
      g_sessionBlocked[i]=false;
      g_sessionBlockUntilTick[i]=0;
      g_sessionNextPermissionCheckTick[i]=0;
      g_sessionBlockUntilTime[i]=0;
      g_sessionCandidates[i]=0;
      g_sessionAttempts[i]=0;
      g_sessionAccepted[i]=0;
      g_sessionRejected[i]=0;
      g_sessionClosed[i]=0;
      g_sessionNet[i]=0.0;
      g_lastBar[i]=0;
      g_barBaselineSet[i]=false;
      g_lastBarDiagState[i]="";
      g_lastMarketDataDiagState[i]="";
      bool symbolSelected=SymbolSelect(g_symbols[i],true);
      Print("SYMBOL_SELECT_DIAGNOSTIC | symbol=",g_symbols[i],
            " selected=",(symbolSelected?"true":"false"),
            " tradeAllowed=",(MarketInfo(g_symbols[i],MODE_TRADEALLOWED)>0?"true":"false"));
      // Capture the already-existing current bar as the startup baseline.
      // It must not be counted as a newly formed bar on the first RunCycle.
      datetime startupBar=iTime(g_symbols[i],InpSignalTF,0);
      if(startupBar>0)
      {
         g_lastBar[i]=startupBar;
         g_barBaselineSet[i]=true;
         g_lastBarDiagState[i]="INITIAL_BASELINE";
         if(InpLogBarScanDiagnostics)
         {
            datetime startupTick=(datetime)MarketInfo(g_symbols[i],MODE_TIME);
            int startupBarAge=(int)MathMax(0,TimeCurrent()-startupBar);
            int startupQuoteAge=(startupTick>0?(int)MathMax(0,TimeCurrent()-startupTick):-1);
            Print("BAR_SCAN_SYMBOL | symbol=",g_symbols[i],
                  " tf=",(int)InpSignalTF,
                  " state=INITIAL_BASELINE bars=",iBars(g_symbols[i],InpSignalTF),
                  " minBars=",InpMinBars,
                  " currentBarTime=",(long)startupBar,
                  " barAgeSec=",startupBarAge,
                  " quoteAgeSec=",startupQuoteAge,
                  " note=EXISTING_BAR_NOT_COUNTED_AS_NEW");
         }
      }
      g_lastQuoteStamp[i]=(datetime)MarketInfo(g_symbols[i],MODE_TIME);
      // A cached quote is NOT trusted at startup. Wait until a post-init quote-time change is observed.
      g_lastQuoteChangeTick[i]=0;
   }
   LogPotentialAliasGroups();
   EventSetTimer(1);
   if(AccountCurrency()!="USD") Print("RISK_WARNING | reference capital is USD but account currency is ",AccountCurrency(),"; verify conversion before trading");
   if(InpEstimatedCloseCommissionPerLot<=0.0) Print("NET_LOCK_WARNING | set InpEstimatedCloseCommissionPerLot if broker charges closing commission; exact net lock cannot be guaranteed otherwise");
   Print("EARLY_LOSS_EXIT_CONFIG | enabled=",(InpSmallLossCloseUSD>0.0?"true":"false")," threshold=",DoubleToString(InpSmallLossCloseUSD,2)," minHoldSeconds=",MathMax(0,InpSmallLossMinHoldSeconds)," protection=BROKER_INITIAL_SL_AND_RISK_LIMITS");
   Print("BITEY_ENSEMBLE_INIT | version=",EA_VERSION," | universe=MARKET_WATCH_PLUS_ALL_BROKER_USDT_ADDITIVE | quoteFreshness=STRICT_POST_INIT maxQuoteAgeSec=",InpMaxQuoteAgeSec," | tradeAudit=PER_TICKET_GROSS_COMMISSION_SWAP_NET | symbols=",g_symbolCount,
         " | maxPositions=",MaxPositions()," | tf=",(int)InpSignalTF,
         " | profitRunner=NET_+",DoubleToString(InpTrendRunnerTriggerNetUSD,2)," lockFloor=+",DoubleToString(InpNetLockMinUSD,2)," | accountMode=NOT_A_GATE | diagnosticOnly=",(DIAGNOSTIC_ONLY_BUILD?"ON":"OFF"),
          " | trading=",(InpEnableTrading?"ON":"OFF"));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick()  { RunCycle(); }
void OnTimer() { RunCycle(); }

int MaxPositions()
{
   return(MathMin(HARD_MAX_POSITIONS,MathMax(1,InpMaxOpenPositions)));
}

int SessionSymbolIndex(string sym)
{
   string key=AssetKey(sym);
   for(int i=0;i<g_symbolCount;i++)
      if(g_keys[i]==key) return(i);
   return(-1);
}

bool SessionSymbolBlocked(string sym)
{
   int idx=SessionSymbolIndex(sym);
   if(idx<0 || !g_sessionBlocked[idx]) return(false);

   // Zero keeps the symbol blocked until EA reinitialization.
   // GetTickCount measures elapsed time independently of server quote time.
   if(InpBroker133CooldownMinutes<=0) return(true);

   uint nowTick=GetTickCount();
   if((int)(nowTick-g_sessionBlockUntilTick[idx])<0) return(true);
   if((int)(nowTick-g_sessionNextPermissionCheckTick[idx])<0) return(true);

   // Permission-only probe: never send a test order to "check" broker access.
   bool symbolAllowed=(MarketInfo(sym,MODE_TRADEALLOWED)>0);
   bool permissionsReady=TradePermissionsReady(sym,"BROKER_133_COOLDOWN_EXPIRED");
   if(symbolAllowed && permissionsReady)
   {
      g_sessionBlocked[idx]=false;
      g_sessionBlockUntilTick[idx]=0;
      g_sessionNextPermissionCheckTick[idx]=0;
      g_sessionBlockUntilTime[idx]=0;
      Print("SESSION_SYMBOL_UNBLOCK | symbol=",sym,
            " reason=COOLDOWN_EXPIRED_AND_PERMISSIONS_READY",
            " permissionProbeOnly=true no_test_order=true");
      return(false);
   }

   int recheckMinutes=MathMax(1,InpBroker133RecheckMinutes);
   g_sessionNextPermissionCheckTick[idx]=nowTick+(uint)(recheckMinutes*60000);
   Print("SESSION_SYMBOL_BLOCK_RETAINED | symbol=",sym,
         " reason=PERMISSIONS_NOT_READY_AFTER_COOLDOWN",
         " symbolTradeAllowed=",(symbolAllowed?"true":"false"),
         " nextCheckMinutes=",recheckMinutes,
         " no_order_sent=true");
   return(true);
}

// Session-only, bounded adjustment. It is inactive until five closed trades
// exist for the symbol and only uses account-currency net results on USD accounts.
double SessionPerformanceAdjustment(string sym)
{
   if(AccountCurrency()!="USD") return(0.0);
   int idx=SessionSymbolIndex(sym);
   if(idx<0 || g_sessionClosed[idx]<5) return(0.0);
   double avg=g_sessionNet[idx]/g_sessionClosed[idx];
   return(MathMax(-2.0,MathMin(2.0,avg*2.0)));
}

//+------------------------------------------------------------------+
//| Record EA-originated market closes for later history attribution  |
//+------------------------------------------------------------------+
void RecordEAClosedReason(int ticket,string reason)
{
   if(ticket<=0 || g_eaCloseReasonCount>=2048) return;
   for(int i=0;i<g_eaCloseReasonCount;i++)
      if(g_eaCloseReasonTickets[i]==ticket) return;
   g_eaCloseReasonTickets[g_eaCloseReasonCount]=ticket;
   g_eaCloseReasonText[g_eaCloseReasonCount]=reason;
   g_eaCloseReasonCount++;
}

string ClassifyHistoricalClose(int ticket,double closePrice,double sl,double tp,string sym)
{
   for(int i=0;i<g_eaCloseReasonCount;i++)
      if(g_eaCloseReasonTickets[i]==ticket)
         return("EA_MARKET_CLOSE_CONFIRMED:"+g_eaCloseReasonText[i]);
   double point=MarketInfo(sym,MODE_POINT);
   double tickSize=MarketInfo(sym,MODE_TICKSIZE);
   double tolerance=MathMax(point*3.0,tickSize*1.5);
   bool nearSL=(sl>0.0 && MathAbs(closePrice-sl)<=tolerance);
   bool nearTP=(tp>0.0 && MathAbs(closePrice-tp)<=tolerance);
   if(nearSL && nearTP) return("SLTP_MATCH_AMBIGUOUS");
   if(nearSL) return("SL_HIT_PROBABLE_NOT_PROVEN");
   if(nearTP) return("TP_HIT_PROBABLE_NOT_PROVEN");
   return("BROKER_MANUAL_OR_OTHER_UNKNOWN");
}

//+------------------------------------------------------------------+
void SyncClosedTradeStats()
{
   int total=OrdersHistoryTotal();
   for(int i=total-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(OrderCloseTime()<g_sessionStartTime) continue;
      int ticket=OrderTicket();
      bool seen=false;
      for(int j=0;j<g_processedCloseCount;j++)
         if(g_processedCloseTickets[j]==ticket) { seen=true; break; }
      if(seen) continue;
      if(g_processedCloseCount>=2048)
      {
         Print("TRADE_AUDIT_CAPACITY_WARNING | ticket=",ticket," capacity=2048 action=stop_session_audit");
         break;
      }
      g_processedCloseTickets[g_processedCloseCount++]=ticket;

      // MT4 history is the source of truth for realized gross P/L and booked costs.
      // EA close records are definitive; SL/TP price matches remain probable only.
      string closeClassification=ClassifyHistoricalClose(ticket,OrderClosePrice(),OrderStopLoss(),OrderTakeProfit(),OrderSymbol());
      long serverLocalOffset=(long)TimeLocal()-(long)TimeCurrent();
      double gross=OrderProfit();
      double swap=OrderSwap();
      double commission=OrderCommission();
      double net=gross+swap+commission;
      string side=(OrderType()==OP_BUY?"BUY":"SELL");
      Print("TRADE_CLOSE_AUDIT | scope=EA_SESSION_ONLY ticket=",ticket,
            " symbol=",OrderSymbol()," side=",side,
            " lots=",DoubleToString(OrderLots(),3),
            " openTimeServer=",TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),
            " closeTimeServer=",TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),
            " closeTimeLocalEstimate=",TimeToString(OrderCloseTime()+serverLocalOffset,TIME_DATE|TIME_SECONDS),
            " closeClassification=",closeClassification,
            " auditTimeServer=",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
            " auditTimeLocal=",TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
            " auditTimeGMT=",TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
            " serverLocalOffsetSec=",serverLocalOffset,
            " openPrice=",DoubleToString(OrderOpenPrice(),(int)MarketInfo(OrderSymbol(),MODE_DIGITS)),
            " closePrice=",DoubleToString(OrderClosePrice(),(int)MarketInfo(OrderSymbol(),MODE_DIGITS)),
            " gross=",DoubleToString(gross,2),
            " commission=",DoubleToString(commission,2),
            " swap=",DoubleToString(swap,2),
            " net=",DoubleToString(net,2),
            " magic=",OrderMagicNumber());

      int idx=SessionSymbolIndex(OrderSymbol());
      if(idx>=0)
      {
         g_sessionClosed[idx]++;
         g_sessionNet[idx]+=net;
         Print("SESSION_TRADE_STAT | symbol=",OrderSymbol()," ticket=",ticket,
               " gross=",DoubleToString(gross,2),
               " commission=",DoubleToString(commission,2),
               " swap=",DoubleToString(swap,2),
               " net=",DoubleToString(net,2),
               " symbolClosed=",g_sessionClosed[idx],
               " symbolSessionNet=",DoubleToString(g_sessionNet[idx],2));
      }
   }
}

void LogSessionSymbolStats()
{
   for(int i=0;i<g_symbolCount;i++)
   {
      if(g_sessionCandidates[i]+g_sessionAttempts[i]+g_sessionClosed[i]==0 && !g_sessionBlocked[i]) continue;
      Print("SESSION_SYMBOL_STATS | symbol=",g_symbols[i],
            " candidates=",g_sessionCandidates[i],
            " attempts=",g_sessionAttempts[i],
            " accepted=",g_sessionAccepted[i],
            " rejected=",g_sessionRejected[i],
            " closed=",g_sessionClosed[i],
            " net=",DoubleToString(g_sessionNet[i],2),
            " broker133Blocked=",(g_sessionBlocked[i]?"true":"false"),
            " sample=EA_SESSION_ONLY");
   }
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
   string p[24]={"BTC","XBT","ETH","SOL","XRP","LTC","BCH","DOG","ADA","DOT","LIN","AVA","BNB","NEA","ZEC","LRC","UNI","TRX","ETC","FIL","ATOM","LINK","SHIB","TON"};
   for(int i=0;i<24;i++)
      if(StringFind(k,p[i])==0) return(true);
   return(false);
}

void ParseSymbols()
{
   g_symbolCount=0;
   string csv=InpSymbolsCSV;
   StringTrimLeft(csv); StringTrimRight(csv);

   // Preserve the existing configured universe. If no CSV is supplied,
   // start with every symbol already present in Market Watch.
   if(StringLen(csv)==0)
   {
      int selectedTotal=SymbolsTotal(true);
      for(int i=0;i<selectedTotal && g_symbolCount<MAX_SYMBOLS;i++)
         AddSymbol(SymbolName(i,true));
   }
   else
   {
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

   // Add every broker-catalog symbol containing USDT, without removing
   // or replacing any non-USDT symbol already in the configured universe.
   int brokerTotal=SymbolsTotal(false);
   int usdtAdded=0;
   for(int j=0;j<brokerTotal && g_symbolCount<MAX_SYMBOLS;j++)
   {
      string brokerSymbol=SymbolName(j,false);
      string upperSymbol=brokerSymbol;
      StringToUpper(upperSymbol);
      if(StringFind(upperSymbol,"USDT")<0) continue;
      int before=g_symbolCount;
      AddSymbol(brokerSymbol);
      if(g_symbolCount>before) usdtAdded++;
   }
   Print("SYMBOL_UNIVERSE_ADDITIVE | marketWatchOrConfigured+brokerUSDT=true brokerCatalog=",brokerTotal,
         " usdtAdded=",usdtAdded," total=",g_symbolCount,
         " capacity=",MAX_SYMBOLS," note=NO_NON_USDT_SYMBOLS_REMOVED");
}

void AddSymbol(string s)
{
   if(StringLen(s)<=0 || g_symbolCount>=MAX_SYMBOLS) return;
   string k=AssetKey(s);
   if(StringLen(k)<3) return;
   // Keep distinct quote contracts such as BTCUSD and BTCUSDT in the scan
   // universe. AssetKey remains unchanged for the existing portfolio/risk logic.
   string identity=s;
   StringToUpper(identity);
   for(int i=0;i<g_symbolCount;i++)
   {
      string existing=g_symbols[i];
      StringToUpper(existing);
      if(existing==identity) return;
   }
   g_symbols[g_symbolCount]=s;
   g_keys[g_symbolCount]=k;
   g_symbolCount++;
}

//+------------------------------------------------------------------+
//| Report possible aliases without removing or merging instruments  |
//+------------------------------------------------------------------+
void LogPotentialAliasGroups()
{
   int groups=0;
   for(int i=0;i<g_symbolCount;i++)
   {
      bool first=true;
      for(int p=0;p<i;p++)
         if(g_keys[p]==g_keys[i]) { first=false; break; }
      if(!first) continue;

      int members=0;
      string peers="";
      for(int j=i;j<g_symbolCount;j++)
      {
         if(g_keys[j]!=g_keys[i]) continue;
         members++;
         if(StringLen(peers)>0) peers+=";";
         peers+=g_symbols[j];
      }
      if(members>1)
      {
         groups++;
         Print("POTENTIAL_ASSET_ALIAS_GROUP | assetKey=",g_keys[i],
               " count=",members," symbols=",peers,
               " action=REPORT_ONLY_NO_SYMBOL_REMOVED_OR_MERGED");
      }
   }
   Print("POTENTIAL_ALIAS_SUMMARY | groups=",groups,
         " symbols=",g_symbolCount,
         " identity=EXISTING_ASSETKEY_HEURISTIC_NOT_BROKER_PROOF");
}

//+------------------------------------------------------------------+
//| Per-symbol scan diagnostics: emit only when a symbol changes state|
//+------------------------------------------------------------------+
void LogBarScanSymbolState(int index,string sym,string state,int bars,datetime barTime)
{
   if(!InpLogBarScanDiagnostics) return;
   if(index<0 || index>=MAX_SYMBOLS) return;
   if(g_lastBarDiagState[index]==state) return;
   g_lastBarDiagState[index]=state;
   datetime tickTime=(datetime)MarketInfo(sym,MODE_TIME);
   int barAge=(barTime>0?(int)MathMax(0,TimeCurrent()-barTime):-1);
   int quoteAge=(tickTime>0?(int)MathMax(0,TimeCurrent()-tickTime):-1);
   Print("BAR_SCAN_SYMBOL | symbol=",sym,
         " tf=",(int)InpSignalTF,
         " state=",state,
         " bars=",bars,
         " minBars=",InpMinBars,
         " currentBarTime=",(long)barTime,
         " barAgeSec=",barAge,
         " quoteAgeSec=",quoteAge);
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
   SyncClosedTradeStats();

   int maxPos=MaxPositions();
   int nc=0;
   for(int i=0;i<g_symbolCount;i++)
   {
      string sym=g_symbols[i];
      int bars=iBars(sym,InpSignalTF);
      datetime bt=iTime(sym,InpSignalTF,0);
      if(bt<=0)
      {
         g_cycleHistoryUnavailable++;
         LogBarScanSymbolState(i,sym,"HISTORY_UNAVAILABLE",bars,bt);
         continue;
      }
      // If history was unavailable during OnInit, establish a baseline now.
      // Do not treat the first subsequently loaded historical bar as a new bar.
      if(!g_barBaselineSet[i])
      {
         g_lastBar[i]=bt;
         g_barBaselineSet[i]=true;
         LogBarScanSymbolState(i,sym,"INITIAL_BASELINE",bars,bt);
         continue;
      }
      if(bt==g_lastBar[i])
      {
         g_cycleNoNewBar++;
         LogBarScanSymbolState(i,sym,"NO_NEW_BAR",bars,bt);
         continue;
      }
      g_lastBar[i]=bt;                      // process each newly observed signal-timeframe bar once
      g_cycleNewBars++;
      g_lastScanSymbol=sym;
      if(bars<InpMinBars)
      {
         g_cycleInsufficientHistory++;
         LogBarScanSymbolState(i,sym,"NEW_BAR_INSUFFICIENT_HISTORY",bars,bt);
      }
      else
         LogBarScanSymbolState(i,sym,"NEW_BAR_READY",bars,bt);

      // Candidate capacity is independent of the live-position limit.
      // Collect signals across the whole universe; execution below stops only
      // after the configured number of positions have actually been accepted.
      if(nc>=MAX_SYMBOLS)
      {
         Reject(sym,"CANDIDATE_BUFFER_FULL");
         g_cycleCapacityRejects++;
         continue;
      }
      int cmd; double score; string why;
      if(!Prefilter(sym,why)) { Reject(sym,why); g_cyclePrefilterRejects++; continue; }
      g_cyclePrefilterOK++;
      g_cycleIndicatorRuns++;
      if(!Analyze(sym,cmd,score,why)) { Reject(sym,why); g_cycleSignalRejects++; continue; }
      if(cmd==OP_BUY && !InpAllowBuy)  { Reject(sym,"BUY_DISABLED");  g_cycleSignalRejects++; continue; }
      if(cmd==OP_SELL && !InpAllowSell) { Reject(sym,"SELL_DISABLED"); g_cycleSignalRejects++; continue; }
      if(score<InpMinEntryScore) { Reject(sym,"ENTRY_SCORE_BELOW_MINIMUM"); g_cycleSignalRejects++; continue; }
      double qBid=MarketInfo(sym,MODE_BID),qAsk=MarketInfo(sym,MODE_ASK);
      double qPoint=MarketInfo(sym,MODE_POINT);
      double qAtr=iATR(sym,InpSignalTF,InpATRPeriod,1);
      double qSpreadPct=1000.0;
      if(qBid>0.0 && qAsk>=qBid && qPoint>0.0 && qAtr>0.0)
      {
         double qSpread=qAsk-qBid;
         double qBrokerMin=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*qPoint;
         double qStop=MathMax(qAtr*InpStopATR,qSpread+qBrokerMin);
         if(qStop>0.0) qSpreadPct=100.0*qSpread/qStop;
      }
      // Quality affects ordering only. Hard spread, risk and permission checks remain in OpenTrade().
      double qPenalty=MathMin(10.0,MathMax(0.0,qSpreadPct-InpMaxSpreadPctOfStop)*0.20);
      double qSessionAdjustment=SessionPerformanceAdjustment(sym);
      double qPriority=score-qPenalty+qSessionAdjustment;
      g_candSym[nc]=sym; g_candCmd[nc]=cmd; g_candScore[nc]=score;
      g_candSpreadPct[nc]=qSpreadPct; g_candPriority[nc]=qPriority; nc++;
      int sessionIdx=SessionSymbolIndex(sym);
      if(sessionIdx>=0) g_sessionCandidates[sessionIdx]++;
      g_cycleSignalCandidates++;
      if(cmd==OP_BUY) g_cycleBuySignals++; else g_cycleSellSignals++;
   }

   // Evaluate the daily loss guard on EVERY cycle, even with zero candidates.
   double dailyLimit=InpReferenceCapitalUSD*InpDailyLossPct/100.0;
   double dayNet=TodayNet();
   bool dailyLossBlocked=(dayNet<=-dailyLimit);
   if(dailyLossBlocked)
   {
      uint dailyNowTick=GetTickCount();
      if(g_lastDailyLossLogTick==0 || dailyNowTick-g_lastDailyLossLogTick>=60000)
      {
         g_lastDailyLossLogTick=dailyNowTick;
         Print("DAILY_LOSS_BLOCK | dayNet=",DoubleToString(dayNet,2),
               " limit=-",DoubleToString(dailyLimit,2),
               " candidates=",nc,
               " action=NO_NEW_ENTRIES_OPEN_POSITIONS_REMAIN_MANAGED");
      }
   }

   if(nc>0)
   {
      // sort candidates by score, best first
      for(int a=0;a<nc-1;a++)
         for(int b=a+1;b<nc;b++)
            if(g_candPriority[b]>g_candPriority[a])
            {
               string ts=g_candSym[a]; g_candSym[a]=g_candSym[b]; g_candSym[b]=ts;
               int tc=g_candCmd[a];    g_candCmd[a]=g_candCmd[b];  g_candCmd[b]=tc;
               double td=g_candScore[a]; g_candScore[a]=g_candScore[b]; g_candScore[b]=td;
               td=g_candSpreadPct[a]; g_candSpreadPct[a]=g_candSpreadPct[b]; g_candSpreadPct[b]=td;
               td=g_candPriority[a]; g_candPriority[a]=g_candPriority[b]; g_candPriority[b]=td;
            }

      if(DIAGNOSTIC_ONLY_BUILD)
      {
         Print("DIAGNOSTIC_ONLY_BLOCK | candidates=",nc,
               " buy=",g_cycleBuySignals," sell=",g_cycleSellSignals,
               " action=NO_ORDER_SEND exits_for_existing_positions=MANAGED");
      }
      else if(dailyLossBlocked)
      {
         Print("DAILY_LOSS_BLOCK | dayNet=",DoubleToString(dayNet,2),
               " limit=-",DoubleToString(dailyLimit,2),
               " candidates=",nc," action=NO_NEW_ENTRIES");
      }
      else
      {
         int attempted=0,accepted=0,executionRejected=0;
         int candidateBuy=0,candidateSell=0,attemptedBuy=0,attemptedSell=0;
         int rejectSpread=0,rejectRisk=0,rejectPermission=0,rejectBroker=0;
         int rejectStops=0,rejectOther=0,dryRunCount=0;
         int brokerErr133=0,brokerErr4109=0,brokerErr146=0,brokerErrOther=0;
         for(int c=0;c<nc;c++)
         {
            if(g_candCmd[c]==OP_BUY) candidateBuy++; else if(g_candCmd[c]==OP_SELL) candidateSell++;
            // The hard cap applies to accepted/open trades, never to candidates.
            if(CountOpenPositions()>=maxPos) break;
            attempted++;
            if(g_candCmd[c]==OP_BUY) attemptedBuy++; else if(g_candCmd[c]==OP_SELL) attemptedSell++;
            double qPenalty=g_candScore[c]-g_candPriority[c];
            Print("EXECUTION_PRIORITY | symbol=",g_candSym[c],
                  " side=",(g_candCmd[c]==OP_BUY?"BUY":"SELL"),
                  " signalScore=",DoubleToString(g_candScore[c],1),
                  " spreadPctOfStop=",DoubleToString(g_candSpreadPct[c],1),
                  " qualityPenalty=",DoubleToString(qPenalty,1),
                  " sessionNetAdjustment=",DoubleToString(SessionPerformanceAdjustment(g_candSym[c]),1),
                  " priorityScore=",DoubleToString(g_candPriority[c],1),
                  " rank=",attempted,"/",nc);
            int statIdx=SessionSymbolIndex(g_candSym[c]);
            if(statIdx>=0) g_sessionAttempts[statIdx]++;
            if(OpenTrade(g_candSym[c],g_candCmd[c],g_candScore[c]))
            {
               accepted++;
               if(statIdx>=0) g_sessionAccepted[statIdx]++;
            }
            else
            {
               executionRejected++;
               if(statIdx>=0) g_sessionRejected[statIdx]++;
               if(g_lastExecutionRejectCategory=="SPREAD") rejectSpread++;
               else if(g_lastExecutionRejectCategory=="RISK") rejectRisk++;
               else if(g_lastExecutionRejectCategory=="TRADE_PERMISSION") rejectPermission++;
               else if(g_lastExecutionRejectCategory=="BROKER_ERROR")
               {
                  rejectBroker++;
                  if(g_lastExecutionErrorCode==133) brokerErr133++;
                  else if(g_lastExecutionErrorCode==4109) brokerErr4109++;
                  else if(g_lastExecutionErrorCode==146) brokerErr146++;
                  else brokerErrOther++;
               }
               else if(g_lastExecutionRejectCategory=="STOP_PREFLIGHT") rejectStops++;
               else if(g_lastExecutionRejectCategory=="DRY_RUN") dryRunCount++;
               else rejectOther++;
            }
         }
         int capacityNotAttempted=MathMax(0,nc-attempted);
         Print("CANDIDATE_EXECUTION_SUMMARY | collected=",nc,
               " candidateBuy=",candidateBuy," candidateSell=",candidateSell,
               " attempted=",attempted," attemptedBuy=",attemptedBuy," attemptedSell=",attemptedSell,
               " accepted=",accepted," executionRejected=",executionRejected,
               " rejectSpread=",rejectSpread," rejectRisk=",rejectRisk,
               " rejectTradePermission=",rejectPermission," rejectBrokerError=",rejectBroker,
               " brokerErr133=",brokerErr133," brokerErr4109=",brokerErr4109,
               " brokerErr146=",brokerErr146," brokerErrOther=",brokerErrOther,
               " rejectStopPreflight=",rejectStops," rejectOther=",rejectOther," dryRun=",dryRunCount,
               " capacityNotAttempted=",capacityNotAttempted,
               " ranking=SIGNAL_MINUS_SPREAD_PLUS_SESSION_NET_ADJUSTMENT",
               " openAfter=",CountOpenPositions(),"/",maxPos,
               " remainingCandidates=",capacityNotAttempted);
      }
   }

   UpdateScanDashboard(nc);

   datetime now=TimeCurrent();
   uint nowTick=GetTickCount();
   if(g_lastHeartbeatTick==0 || nowTick-g_lastHeartbeatTick>=300000)
   {
      g_lastHeartbeatTick=nowTick;
      g_lastHeartbeat=now;
      long serverLocalOffset=(long)TimeLocal()-(long)TimeCurrent();
      Print("SCAN_CYCLE_SUMMARY | windowSec=300 assets=",g_symbolCount,
            " newBarsScanned=",g_cycleNewBars,
            " indicatorsEvaluated=",g_cycleIndicatorRuns,
            " candidates=",g_cycleSignalCandidates,
            " prefilterRejected=",g_cyclePrefilterRejects,
            " signalRejected=",g_cycleSignalRejects,
            " historyUnavailable=",g_cycleHistoryUnavailable,
            " insufficientHistory=",g_cycleInsufficientHistory,
            " prefilterOK=",g_cyclePrefilterOK,
            " noNewBar=",g_cycleNoNewBar,
            " buy=",g_cycleBuySignals," sell=",g_cycleSellSignals,
            " dailyLossBlocked=",(dailyLossBlocked?"true":"false"),
            " dayNet=",DoubleToString(dayNet,2),
            " dailyLossLimit=-",DoubleToString(dailyLimit,2));
      Print("CLOCK_DIAGNOSTIC | serverTime=",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
            " localTime=",TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
            " gmtTime=",TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
            " serverLocalOffsetSec=",serverLocalOffset,
            " note=LOCAL_ESTIMATE_USES_CURRENT_OFFSET_NOT_HISTORICAL_DST");
      Print("HEARTBEAT | v",EA_VERSION," open=",CountOpenPositions(),"/",maxPos,
            " dayNet=",DoubleToString(dayNet,2),
            " dailyLossLimit=-",DoubleToString(dailyLimit,2),
            " dailyLossBlocked=",(dailyLossBlocked?"true":"false"),
            " diagnosticOnly=",(DIAGNOSTIC_ONLY_BUILD?"true":"false"),
            " assetsInUniverse=",g_symbolCount,
            " newBarsScanned=",g_cycleNewBars,
            " noNewBar=",g_cycleNoNewBar,
            " historyUnavailable=",g_cycleHistoryUnavailable,
            " insufficientHistory=",g_cycleInsufficientHistory,
            " prefilterOK=",g_cyclePrefilterOK,
            " indicatorsEvaluated=",g_cycleIndicatorRuns," candidates=",g_cycleSignalCandidates,
            " buy=",g_cycleBuySignals," sell=",g_cycleSellSignals,
            " prefilterRejected=",g_cyclePrefilterRejects," signalRejected=",g_cycleSignalRejects," capacitySkipped=",g_cycleCapacityRejects);
      for(int md=0;md<g_symbolCount;md++) LogMarketDataState(md,g_symbols[md]);
      int quoteFresh=0,quoteStale=0,quoteMissing=0,quoteNeverRefreshed=0,quoteOldestAge=0;
      CountQuoteStates(quoteFresh,quoteStale,quoteMissing,quoteNeverRefreshed,quoteOldestAge);
      string feedStatus="NO_FRESH_QUOTES";
      if(quoteFresh==g_symbolCount && quoteStale==0 && quoteMissing==0)
         feedStatus="ALL_QUOTES_FRESH";
      else if(quoteFresh>0)
         feedStatus="PARTIAL_QUOTES_FRESH";
      else if(quoteMissing==g_symbolCount)
         feedStatus="NO_QUOTES";
      LogSessionSymbolStats();
      Print("MARKET_DATA_DIAGNOSTICS | freshQuotes=",quoteFresh," staleQuotes=",quoteStale,
            " missingQuotes=",quoteMissing," neverRefreshedAfterInit=",quoteNeverRefreshed," oldestObservedAgeSec=",quoteOldestAge,
            " feedStatus=",feedStatus,
            " universe=",g_symbolCount,
            " note=QUOTE_FRESHNESS_DOES_NOT_GUARANTEE_SYMBOL_TRADE_PERMISSION");
      // Reset interval counters after each 5-minute heartbeat.
      g_cycleNewBars=0; g_cycleNoNewBar=0; g_cycleHistoryUnavailable=0; g_cycleInsufficientHistory=0;
      g_cyclePrefilterOK=0; g_cycleIndicatorRuns=0; g_cycleSignalCandidates=0;
      g_cycleBuySignals=0; g_cycleSellSignals=0; g_cyclePrefilterRejects=0; g_cycleSignalRejects=0; g_cycleCapacityRejects=0;
   }
}

void UpdateScanDashboard(int candidates)
{
   if(!InpShowScanDashboard) { Comment(""); return; }
   string panel="BITEY SCALPER v"+EA_VERSION+" | SCAN DASHBOARD\n";
   panel+="Activos en universo: "+IntegerToString(g_symbolCount)+" / "+IntegerToString(MAX_SYMBOLS)+"\n";
   panel+="Barras nuevas escaneadas: "+IntegerToString(g_cycleNewBars)+" | Prefiltro OK: "+IntegerToString(g_cyclePrefilterOK)+"\n";
   panel+="Indicadores evaluados: "+IntegerToString(g_cycleIndicatorRuns)+" | Candidatos: "+IntegerToString(candidates)+" (BUY "+IntegerToString(g_cycleBuySignals)+" / SELL "+IntegerToString(g_cycleSellSignals)+")\n";
   panel+="Descartes prefiltro: "+IntegerToString(g_cyclePrefilterRejects)+" | Sin señal: "+IntegerToString(g_cycleSignalRejects)+" | Saltos por capacidad: "+IntegerToString(g_cycleCapacityRejects)+"\n";
   panel+="Modo diagnóstico: "+(DIAGNOSTIC_ONLY_BUILD?"ON - NO NEW ORDERS":"OFF")+"\n";
   panel+="Posiciones: "+IntegerToString(CountOpenPositions())+"/"+IntegerToString(MaxPositions())+" | P/L día+flotante: "+DoubleToString(TodayNet(),2)+"\n";
   panel+="Último activo: "+g_lastScanSymbol+"\n";
   panel+="INDICADORES: "+g_lastIndicatorSummary;
   Comment(panel);
}

void Reject(string sym,string reason)
{
   if(InpLogRejects) Print("SYMBOL_REJECT | symbol=",sym," | reason=",reason);
}

//+------------------------------------------------------------------+
//| Cheap checks that do not need indicators                          |
//+------------------------------------------------------------------+
// Quote age uses the local monotonic tick counter because server time can stop on idle markets.
int QuoteAgeSeconds(string sym)
{
   int idx=-1;
   for(int i=0;i<g_symbolCount;i++) if(g_symbols[i]==sym) { idx=i; break; }
   if(idx<0) return(2147483647);
   datetime qt=(datetime)MarketInfo(sym,MODE_TIME);
   if(qt<=0) return(2147483647);
   if(qt!=g_lastQuoteStamp[idx])
   {
      g_lastQuoteStamp[idx]=qt;
      g_lastQuoteChangeTick[idx]=GetTickCount();
      return(0);
   }
   // No post-initialization quote change has been observed: fail closed.
   if(g_lastQuoteChangeTick[idx]==0) return(2147483647);
   uint elapsed=GetTickCount()-g_lastQuoteChangeTick[idx];
   return((int)(elapsed/1000));
}

bool QuoteFresh(string sym)
{
   int age=QuoteAgeSeconds(sym);
   return(age>=0 && age<=InpMaxQuoteAgeSec);
}

void CountQuoteStates(int &fresh,int &stale,int &missing,int &neverRefreshed,int &oldestAge)
{
   fresh=0; stale=0; missing=0; neverRefreshed=0; oldestAge=0;
   for(int i=0;i<g_symbolCount;i++)
   {
      datetime qt=(datetime)MarketInfo(g_symbols[i],MODE_TIME);
      if(qt<=0) { missing++; continue; }
      int age=QuoteAgeSeconds(g_symbols[i]);
      if(age<=InpMaxQuoteAgeSec) fresh++; else stale++;
      if(age>=2147483647) { neverRefreshed++; oldestAge=2147483647; }
      else if(oldestAge<2147483647 && age>oldestAge) oldestAge=age;
   }
}

//+------------------------------------------------------------------+
//| v1.4.5.2 diagnostics only: separate quote freshness from history    |
//| and never infer a closed session from an old tick.                |
//+------------------------------------------------------------------+
void LogMarketDataState(int index,string sym)
{
   if(index<0 || index>=g_symbolCount) return;

   datetime tickTime=(datetime)MarketInfo(sym,MODE_TIME);
   int quoteAge=QuoteAgeSeconds(sym);
   string quoteState="NO_SERVER_TICK";
   if(tickTime>0)
   {
      if(quoteAge>=2147483647) quoteState="NO_POST_INIT_TICK_CHANGE";
      else if(quoteAge<=InpMaxQuoteAgeSec) quoteState="FRESH";
      else quoteState="STALE";
   }

   int barsSignal=iBars(sym,InpSignalTF);
   datetime barSignal=iTime(sym,InpSignalTF,0);
   datetime prevSignal=iTime(sym,InpSignalTF,1);
   int barsHigher=iBars(sym,InpHTF);
   datetime barHigher=iTime(sym,InpHTF,0);
   datetime prevHigher=iTime(sym,InpHTF,1);

   string historyState="HISTORY_UNAVAILABLE";
   if(barsSignal>=InpMinBars && barSignal>0) historyState="HISTORY_READY";
   else if(barsSignal>0 && barSignal>0) historyState="HISTORY_INSUFFICIENT";

   long syncSignalValue=0, syncHigherValue=0, selectedValue=0;
   bool syncSignalKnown=SeriesInfoInteger(sym,InpSignalTF,SERIES_SYNCHRONIZED,syncSignalValue);
   bool syncHigherKnown=SeriesInfoInteger(sym,InpHTF,SERIES_SYNCHRONIZED,syncHigherValue);
   bool selectedKnown=SymbolInfoInteger(sym,SYMBOL_SELECT,selectedValue);
   bool signalSynchronized=(syncSignalKnown && syncSignalValue!=0);
   bool higherSynchronized=(syncHigherKnown && syncHigherValue!=0);
   bool symbolSelected=(selectedKnown && selectedValue!=0);
   bool tradeAllowed=(MarketInfo(sym,MODE_TRADEALLOWED)>0);

   double bid=MarketInfo(sym,MODE_BID);
   double ask=MarketInfo(sym,MODE_ASK);
   bool quotePricesValid=(bid>0.0 && ask>=bid);

   string sessionState=(IsCrypto(sym)?"SESSION_NOT_APPLICABLE":"SESSION_UNCONFIRMED");
   int dot=StringFind(sym,".");
   string suffix=(dot>=0?StringSubstr(sym,dot):"NONE");
   string combined=quoteState+"|"+historyState+
      "|M5="+IntegerToString(barsSignal)+":"+IntegerToString((int)barSignal)+
      "|M15="+IntegerToString(barsHigher)+":"+IntegerToString((int)barHigher)+
      "|SYNC="+(signalSynchronized?"1":"0")+":"+(higherSynchronized?"1":"0")+
      "|SELECT="+(symbolSelected?"1":"0")+
      "|TRADE="+(tradeAllowed?"1":"0")+
      "|PRICE="+(quotePricesValid?"1":"0")+
      "|TICK="+IntegerToString((int)tickTime);
   if(g_lastMarketDataDiagState[index]==combined) return;
   g_lastMarketDataDiagState[index]=combined;

   int signalBarAge=(barSignal>0?(int)MathMax(0,TimeCurrent()-barSignal):-1);
   int higherBarAge=(barHigher>0?(int)MathMax(0,TimeCurrent()-barHigher):-1);
   int quoteAgeForLog=(quoteAge>=2147483647?-1:quoteAge);

   Print("MARKET_DATA_SYMBOL | symbol=",sym,
         " quoteState=",quoteState,
         " quoteAgeSec=",quoteAgeForLog,
         " quoteAgeMeaning=",(quoteAge>=2147483647?"NO_POST_INIT_CHANGE_OR_UNKNOWN":"MONOTONIC_SECONDS"),
         " tickTime=",(long)tickTime,
         " historyState=",historyState,
         " signalTF=",(int)InpSignalTF,
         " signalBars=",barsSignal,
         " signalBarTime=",(long)barSignal,
         " signalPrevClosedBarTime=",(long)prevSignal,
         " signalBarAgeSec=",signalBarAge,
         " higherTF=",(int)InpHTF,
         " higherBars=",barsHigher,
         " higherBarTime=",(long)barHigher,
         " higherPrevClosedBarTime=",(long)prevHigher,
         " higherBarAgeSec=",higherBarAge,
         " signalSeriesSyncKnown=",(syncSignalKnown?"true":"false"),
         " signalSeriesSynchronized=",(signalSynchronized?"true":"false"),
         " higherSeriesSyncKnown=",(syncHigherKnown?"true":"false"),
         " higherSeriesSynchronized=",(higherSynchronized?"true":"false"),
         " symbolSelectKnown=",(selectedKnown?"true":"false"),
         " symbolSelected=",(symbolSelected?"true":"false"),
         " symbolTradeAllowed=",(tradeAllowed?"true":"false"),
         " bid=",DoubleToString(bid,(int)MarketInfo(sym,MODE_DIGITS)),
         " ask=",DoubleToString(ask,(int)MarketInfo(sym,MODE_DIGITS)),
         " quotePricesValid=",(quotePricesValid?"true":"false"),
         " contractSuffix=",suffix,
         " existingCryptoPrefixHeuristic=",(IsCrypto(sym)?"true":"false"),
         " sessionState=",sessionState,
         " maxQuoteAgeSec=",InpMaxQuoteAgeSec,
         " brokerSessionSchedule=NOT_CONFIRMED",
         " note=QUOTE_FRESHNESS_DOES_NOT_PROVE_NEW_BAR_OR_TRADE_PERMISSION");
}

bool SessionOK(string sym)
{
   if(!InpUseSessionFilter || IsCrypto(sym)) return(true);
   int h=TimeHour(TimeCurrent());
   if(InpSessionStartHour<InpSessionEndHour) return(h>=InpSessionStartHour && h<InpSessionEndHour);
   return(h>=InpSessionStartHour || h<InpSessionEndHour);
}

bool TradePermissionsReady(string sym,string stage)
{
   bool terminalAllowed=IsTradeAllowed();
   bool expertEnabled=IsExpertEnabled();
   // Use the supported MQL4 terminal/account-level permission check.
   bool symbolAllowed=(MarketInfo(sym,MODE_TRADEALLOWED)>0);
   bool contextBusy=IsTradeContextBusy();
   bool ready=(terminalAllowed && expertEnabled && symbolAllowed && !contextBusy);
   datetime now=TimeCurrent();
   bool logNow=(g_lastPermissionDiagnostic==0 || now-g_lastPermissionDiagnostic>=60);
   if(logNow)
   {
      string reason="TERMINAL_TRADING_NOT_ALLOWED";
      if(contextBusy) reason="TRADE_CONTEXT_BUSY";
      else if(!expertEnabled) reason="EXPERT_TRADING_DISABLED";
      else if(!symbolAllowed) reason="SYMBOL_TRADING_DISABLED";
      Print("TRADE_PERMISSION_DIAGNOSTICS | stage=",stage," symbol=",sym,
            " terminalIsTradeAllowed=",(terminalAllowed?"true":"false"),
            " expertEnabled=",(expertEnabled?"true":"false"),
            " terminalAccountPermission=",(terminalAllowed?"true":"false"),
            " symbolTradeAllowed=",(symbolAllowed?"true":"false"),
            " tradeContextBusy=",(contextBusy?"true":"false"),
            " result=",(ready?"READY":"BLOCKED"));
      if(!ready)
         Print("TRADE_PERMISSION_BLOCK | stage=",stage," symbol=",sym," reason=",reason);
      g_lastPermissionDiagnostic=now;
   }
   return(ready);
}

string TradeErrorDescription(int err)
{
   switch(err)
   {
      case 7:   return("NOT_ENOUGH_RIGHTS");
      case 128: return("TRADE_TIMEOUT");
      case 129: return("INVALID_PRICE");
      case 130: return("INVALID_STOPS");
      case 131: return("INVALID_TRADE_VOLUME");
      case 132: return("MARKET_CLOSED");
      case 133: return("TRADE_DISABLED");
      case 134: return("NOT_ENOUGH_MONEY");
      case 135: return("PRICE_CHANGED");
      case 136: return("OFF_QUOTES");
      case 137: return("BROKER_BUSY");
      case 138: return("REQUOTE");
      case 146: return("TRADE_CONTEXT_BUSY");
      case 148: return("TOO_MANY_ORDERS");
      case 4109:return("EXPERT_TRADING_NOT_ALLOWED");
   }
   return("UNCLASSIFIED_TRADE_ERROR");
}

bool Prefilter(string sym,string &why)
{
   why="";
   if(SessionSymbolBlocked(sym)) { why="SESSION_BLOCKED_AFTER_BROKER_133"; return(false); }
   // Strict freshness gate runs before permission/indicator work.
   // Quotes cached before EA initialization remain untrusted until they update.
   int quoteAge=QuoteAgeSeconds(sym);
   if(quoteAge>InpMaxQuoteAgeSec)
   {
      why=(quoteAge>=2147483647?"QUOTE_NOT_REFRESHED_AFTER_INIT_OR_MISSING":"STALE_QUOTE ageSec="+IntegerToString(quoteAge));
      return(false);
   }
   if(!TradePermissionsReady(sym,"PREFILTER")) { why="TRADE_PERMISSION_BLOCKED"; return(false); }
   if(MarketInfo(sym,MODE_TRADEALLOWED)==0) { why="SYMBOL_TRADING_DISABLED"; return(false); }
   if(iBars(sym,InpSignalTF)<InpMinBars) { why="INSUFFICIENT_HISTORY"; return(false); }
   if(!SessionOK(sym)) { why="OUTSIDE_SESSION"; return(false); }
   if(HasPositionForKey(AssetKey(sym))) { why="POSITION_ALREADY_OPEN"; return(false); }
   if(InCooldown(sym)) { why="LOSS_COOLDOWN"; return(false); }
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
   double ema50=ema[6], ema144=ema[8];
   double bb20Upper=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_UPPER,1);
   double bb20Lower=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_LOWER,1);
   int dc20High=iHighest(sym,tf,MODE_HIGH,20,2);
   int dc20Low=iLowest(sym,tf,MODE_LOW,20,2);
   double donchianHigh=(dc20High>=0?iHigh(sym,tf,dc20High):0.0);
   double donchianLow=(dc20Low>=0?iLow(sym,tf,dc20Low):0.0);
   string regime=(adx>=InpTrendADX?"TREND":"RANGE");
   string htf="OFF";
   if(InpUseHTFFilter)
   {
      double htfClose=iClose(sym,InpHTF,1), htfEma=iMA(sym,InpHTF,50,0,MODE_EMA,PRICE_CLOSE,1);
      htf=(htfClose>0 && htfEma>0?(htfClose>htfEma?"BULL":"BEAR"):"NO_DATA");
   }
   g_lastIndicatorSummary=StringFormat("%s TF=%d | ADX14=%.1f %s | ATR%d=%.5f | RSI14=%.1f | EMA50/144=%.5f/%.5f | votes T%d/%d M%d/%d D%d/%d BB%d/%d | BB20[%.5f..%.5f] | Donchian20[%.5f..%.5f] | HTF=%s",
      sym,tf,adx,regime,InpATRPeriod,atr,rsi14,ema50,ema144,tb,tsl,mb,ms,bb,bs,rb,rs,bb20Lower,bb20Upper,donchianLow,donchianHigh,htf);
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

   // Spread cost is part of the ranking: tighter spread -> better score
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
   double stopRef=atr*InpStopATR;
   double spreadRatio=(stopRef>0?(ask-bid)/stopRef:1.0);
   score=10.0*agree+win+MathMin(adx,40.0)/4.0-30.0*spreadRatio;
   cmd=(dir>0?OP_BUY:OP_SELL);
   return(true);
}

//+------------------------------------------------------------------+
//| Order entry: stops, spread-vs-stop, risk budget, lots             |
//+------------------------------------------------------------------+
bool OpenTrade(string sym,int cmd,double score)
{
   g_lastExecutionRejectCategory="";
   if(DIAGNOSTIC_ONLY_BUILD)
   {
      g_lastExecutionRejectCategory="DRY_RUN";
      Print("DIAGNOSTIC_ONLY_HARD_BLOCK | symbol=",sym,
            " action=ORDER_SEND_FORBIDDEN");
      return(false);
   }
   if(SessionSymbolBlocked(sym))
   {
      g_lastExecutionRejectCategory="TRADE_PERMISSION";
      Print("SESSION_SYMBOL_BLOCK | symbol=",sym," reason=PREVIOUS_BROKER_133 no_retry=true");
      return(false);
   }
   g_lastExecutionErrorCode=0;
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(bid<=0 || ask<bid || point<=0 || atr<=0) { g_lastExecutionRejectCategory="OTHER"; Reject(sym,"ENTRY_DATA_INVALID"); return(false); }
   if(!QuoteFresh(sym)) { g_lastExecutionRejectCategory="OTHER"; Reject(sym,"STALE_QUOTE_AT_ENTRY"); return(false); }

   double spreadPrice=ask-bid;
   double brokerMin=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*point;
   double stopDist=MathMax(atr*InpStopATR,spreadPrice+brokerMin);
   double targetDist=MathMax(stopDist*InpRewardRisk,spreadPrice+brokerMin);
   // The warning threshold is informational; the hard cap rejects excessive spread.
   // Entry-to-SL already uses executable Ask (BUY) or Bid (SELL) entry price.
   // Adding spread again would double-count it; reserve only adverse slippage here.
   double spreadPctOfStop=(stopDist>0.0?100.0*spreadPrice/stopDist:0.0);
   if(InpMaxSpreadPctOfStop>0.0 && spreadPctOfStop>InpMaxSpreadPctOfStop)
      Print("HIGH_SPREAD_WARNING | symbol=",sym," spread=",DoubleToString(spreadPrice,digits),
            " stop=",DoubleToString(stopDist,digits)," spreadPctOfStop=",DoubleToString(spreadPctOfStop,1),
            " diagnosticThreshold=",DoubleToString(InpMaxSpreadPctOfStop,1),
            " action=CHECK_HARD_CAP");
   if(InpHardMaxSpreadPctOfStop>0.0 && spreadPctOfStop>InpHardMaxSpreadPctOfStop)
   {
      Print("EXECUTION_QUALITY_REJECT | symbol=",sym," spreadPctOfStop=",DoubleToString(spreadPctOfStop,1),
            " hardMax=",DoubleToString(InpHardMaxSpreadPctOfStop,1)," reason=SPREAD_TOO_LARGE");
      g_lastExecutionRejectCategory="SPREAD";
      return(false);
   }

   double entry=(cmd==OP_BUY?ask:bid);
   double sl=NormalizeDouble(cmd==OP_BUY?entry-stopDist:entry+stopDist,digits);
   double tp=NormalizeDouble(cmd==OP_BUY?entry+targetDist:entry-targetDist,digits);
   stopDist=MathAbs(entry-sl);
   bool ok=false;
   if(cmd==OP_BUY) ok=(sl>0 && tp>0 && sl<bid-brokerMin*0.5 && tp>bid+brokerMin*0.5);
   else            ok=(sl>ask+brokerMin*0.5 && tp>0 && tp<ask-brokerMin*0.5);
   if(!ok) { g_lastExecutionRejectCategory="STOP_PREFLIGHT"; Print("STOP_PREFLIGHT_REJECT | symbol=",sym," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits)); return(false); }

   double maxAgg=InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0;
   double openRisk=CurrentOpenRisk();
   double remaining=maxAgg-openRisk;
   double perTrade=InpReferenceCapitalUSD*InpRiskPctPerTrade/100.0;
   if(remaining<=0.01) { g_lastExecutionRejectCategory="RISK"; Print("RISK_REJECT | symbol=",sym," reason=AGGREGATE_RISK_CAP open=",DoubleToString(openRisk,2)," cap=",DoubleToString(maxAgg,2)); return(false); }
   double budget=MathMin(perTrade,remaining);
   double riskDistance=stopDist+MathMax(0,InpSlippagePoints)*point;
   double lots=LotsForRisk(sym,riskDistance,budget);
   if(lots<=0) { g_lastExecutionRejectCategory="RISK"; Print("RISK_REJECT | symbol=",sym," reason=MIN_LOT_EXCEEDS_BUDGET budget=",DoubleToString(budget,2)," riskDistance=",DoubleToString(riskDistance,digits)); return(false); }
   double risk=EstimateRisk(sym,lots,riskDistance);
   if(!CurrencyRiskAllowed(sym,lots,riskDistance,risk)) { g_lastExecutionRejectCategory="RISK"; return(false); }

   if(!InpEnableTrading)
   {
      Print("DRY_RUN_CANDIDATE | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL")," score=",DoubleToString(score,1),
            " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," riskDistance=",DoubleToString(riskDistance,digits),
            " spread=",DoubleToString(spreadPrice,digits)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      g_lastExecutionRejectCategory="DRY_RUN";
      return(false);
   }
   if(!TradePermissionsReady(sym,"PRE_ORDER")) { g_lastExecutionRejectCategory="TRADE_PERMISSION"; return(false); }

   ResetLastError();
   int ticket=OrderSend(sym,cmd,lots,entry,InpSlippagePoints,sl,tp,"Bitey Ens v"+EA_VERSION,InpMagic,0,clrNONE);
   if(ticket<0)
   {
      int err=GetLastError();
      g_lastExecutionErrorCode=err;
      Print("ORDER_REJECTED | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
            " error=",err," errorName=",TradeErrorDescription(err),
            " lots=",DoubleToString(lots,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      g_lastExecutionRejectCategory="BROKER_ERROR";
      if(err==133)
      {
         int blockedIdx=SessionSymbolIndex(sym);
         if(blockedIdx>=0)
         {
            g_sessionBlocked[blockedIdx]=true;
            uint nowTick=GetTickCount();
            int cooldownMinutes=MathMax(0,InpBroker133CooldownMinutes);
            g_sessionBlockUntilTick[blockedIdx]=nowTick+(uint)(cooldownMinutes*60000);
            g_sessionNextPermissionCheckTick[blockedIdx]=g_sessionBlockUntilTick[blockedIdx];
            g_sessionBlockUntilTime[blockedIdx]=(cooldownMinutes>0?TimeCurrent()+cooldownMinutes*60:0);
         }
         Print("SESSION_SYMBOL_BLOCK | symbol=",sym,
               " reason=TRADE_DISABLED_133 no_retry=true cooldownMinutes=",MathMax(0,InpBroker133CooldownMinutes),
               " scope=",(InpBroker133CooldownMinutes>0?"TEMPORARY_PERMISSION_RECHECK":"UNTIL_EA_RESTART"),
               " unlockRequiresPermissionCheck=true");
      }
      if(err==133 || err==4109 || err==146)
         TradePermissionsReady(sym,"ORDER_SEND_FAILURE");
      return(false);
   }
   Print("ORDER_ACCEPTED | ticket=",ticket," symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
         " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," riskDistance=",DoubleToString(riskDistance,digits),
         " spread=",DoubleToString(spreadPrice,digits)," score=",DoubleToString(score,1),
         " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
   return(true);
}

//+------------------------------------------------------------------+
//| Directional progression: closed-bar EMA alignment and slope      |
//| Returns +1 favorable, -1 adverse, 0 neutral / not confirmed.     |
//+------------------------------------------------------------------+
int DirectionalProgression(string sym,int orderType,double atr)
{
   if(atr<=0.0) return(0);
   int lookback=MathMax(1,InpProgressionLookbackBars);
   double fastNow=iMA(sym,InpSignalTF,8,0,MODE_EMA,PRICE_CLOSE,1);
   double fastPast=iMA(sym,InpSignalTF,8,0,MODE_EMA,PRICE_CLOSE,lookback+1);
   double slowNow=iMA(sym,InpSignalTF,21,0,MODE_EMA,PRICE_CLOSE,1);
   double closeNow=iClose(sym,InpSignalTF,1);
   double adx=iADX(sym,InpSignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
   if(fastNow<=0.0 || fastPast<=0.0 || slowNow<=0.0 || closeNow<=0.0 || adx<InpProgressionADXMin)
      return(0);
   double slopeMin=atr*0.02;
   if(orderType==OP_BUY)
   {
      if(fastNow>slowNow && fastNow-fastPast>=slopeMin && closeNow>fastNow) return(1);
      if(fastNow<slowNow && fastNow-fastPast<=-slopeMin && closeNow<fastNow) return(-1);
   }
   else if(orderType==OP_SELL)
   {
      if(fastNow<slowNow && fastPast-fastNow>=slopeMin && closeNow<fastNow) return(1);
      if(fastNow>slowNow && fastPast-fastNow<=-slopeMin && closeNow>fastNow) return(-1);
   }
   return(0);
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
   if(ok)
   {
      RecordEAClosedReason(ticket,reason);
      string pk=NetPeakKey(ticket); if(GlobalVariableCheck(pk)) GlobalVariableDel(pk);
      string rk=RunnerActiveKey(ticket); if(GlobalVariableCheck(rk)) GlobalVariableDel(rk);
   }
   return(ok);
}

void ManageExits()
{
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

      // Evaluate directional progression before any small-profit decision.
      // The signal uses closed candles only; an uncertain/weak signal is neutral.
      int progression=(atr>0.0?DirectionalProgression(sym,type,atr):0);

      // Conservative estimated net after booked costs, estimated closing commission
      // and adverse execution reserve. All thresholds are in account currency.
      double closeCommissionEstimate=MathMax(0.0,InpEstimatedCloseCommissionPerLot)*lots;
      double closeSlippageReserve=0.0;
      if(InpNetLockSlippagePoints>0)
         closeSlippageReserve=EstimateRisk(sym,lots,InpNetLockSlippagePoints*point);
      double estimatedNetAfterCloseCosts=net-closeCommissionEstimate-closeSlippageReserve;
      bool costEstimateValid=(closeSlippageReserve<1.0e11);

      // Mode A: +0.10 is the fallback close only while a trend runner has NOT
      // been activated. If closed-bar progression is favorable, let the trade
      // reach +0.20 net before activating the runner.
      string runnerKey=RunnerActiveKey(ticket);
      bool runnerActive=(GlobalVariableCheck(runnerKey) && GlobalVariableGet(runnerKey)>0.5);
      if(!runnerActive && costEstimateValid && progression>0 &&
         estimatedNetAfterCloseCosts>=InpTrendRunnerTriggerNetUSD)
      {
         GlobalVariableSet(runnerKey,1.0);
         runnerActive=true;
         Print("PROFIT_RUNNER_ACTIVATED | ticket=",ticket," symbol=",sym,
               " estimatedNetAfterCloseCosts=",DoubleToString(estimatedNetAfterCloseCosts,2),
               " trigger=+",DoubleToString(InpTrendRunnerTriggerNetUSD,2),
               " progression=",progression,
               " action=LET_WINNER_RUN_AND_LOCK_NET");
      }

      // Without a confirmed runner, bank at least the small net target once
      // progression is neutral/adverse. An active runner is never closed here:
      // its progressive broker-side SL manages the giveback.
      if(!runnerActive && costEstimateValid && InpSmallProfitCloseUSD>0.0 &&
         estimatedNetAfterCloseCosts>=InpSmallProfitCloseUSD && progression<=0)
      {
         Print("NET_RANGE_PROFIT_CLOSE | ticket=",ticket," symbol=",sym,
               " estimatedNetAfterCloseCosts=",DoubleToString(estimatedNetAfterCloseCosts,2),
               " target=+",DoubleToString(InpSmallProfitCloseUSD,2),
               " progression=",progression,
               " action=CLOSE");
         CloseTicket(ticket,"NET_RANGE_PROFIT_PLUS_0_10");
         continue;
      }

      // Optional small-loss exit is OFF by default. Opening commission and spread
      // can make a new position appear slightly negative immediately; a fixed-cent
      // threshold here caused premature closes. Broker-side initial SL and portfolio
      // risk limits remain the primary loss protections.
      int heldSeconds=(int)MathMax(0,TimeCurrent()-OrderOpenTime());
      if(costEstimateValid && InpSmallLossCloseUSD>0.0 &&
         heldSeconds>=MathMax(0,InpSmallLossMinHoldSeconds) &&
         estimatedNetAfterCloseCosts<=-InpSmallLossCloseUSD)
      {
         Print("NET_LOSS_LIMIT | ticket=",ticket," symbol=",sym," heldSeconds=",heldSeconds,
               " estimatedNetAfterCloseCosts=",DoubleToString(estimatedNetAfterCloseCosts,2),
               " limit=-",DoubleToString(InpSmallLossCloseUSD,2),
               " action=CLOSE");
         CloseTicket(ticket,"NET_LOSS_MINUS_0_10");
         continue;
      }

      if(InpMaxHoldBars>0)
      {
         int barsOpen=iBarShift(sym,InpSignalTF,OrderOpenTime(),false);
         if(barsOpen>=InpMaxHoldBars) { CloseTicket(ticket,"TIME_EXIT"); continue; }
      }
      if(atr<=0) continue;

      if(InpNetTargetR>0.0)
      {
         double initialDist=(oldSL>0.0?MathAbs(entry-oldSL):atr*InpStopATR);
         double refRisk=EstimateRisk(sym,lots,initialDist); // current protective-stop distance proxy
         if(refRisk<1.0e11 && net>=InpNetTargetR*refRisk) { CloseTicket(ticket,"NET_TARGET_R"); continue; }
      }
      if(!InpEnableAdaptiveExits) continue;

      double minDist=(MarketInfo(sym,MODE_STOPLEVEL)+MarketInfo(sym,MODE_FREEZELEVEL)+2.0)*point;
      double price=(type==OP_BUY?bid:ask);
      double favorable=(type==OP_BUY?price-entry:entry-price);
      double newSL=oldSL, newTP=oldTP;
      bool slUp=false, tpUp=false;

      // Break-even + small lock (SL only ever moves toward profit)
      if(InpBreakEvenTriggerATR>0 && favorable>=atr*InpBreakEvenTriggerATR)
      {
         double be=(type==OP_BUY?entry+atr*InpBreakEvenLockATR:entry-atr*InpBreakEvenLockATR);
         if(type==OP_BUY  && (newSL<=0 || be>newSL) && be<bid-minDist) newSL=be;
         if(type==OP_SELL && (newSL<=0 || be<newSL) && be>ask+minDist) newSL=be;
      }
      // ATR trailing. If closed-bar progression turns adverse, tighten (never widen) the trail.
      if(InpTrailStartATR>0 && InpTrailDistanceATR>0 && favorable>=atr*InpTrailStartATR)
      {
         double trailDistance=InpTrailDistanceATR;
         if(progression<0 && InpWeakTrendTrailATR>0.0)
            trailDistance=MathMin(trailDistance,InpWeakTrendTrailATR);
         double tr=(type==OP_BUY?bid-atr*trailDistance:ask+atr*trailDistance);
         if(type==OP_BUY  && tr>newSL+atr*InpTrailStepATR && tr<bid-minDist) newSL=tr;
         if(type==OP_SELL && (newSL<=0 || tr<newSL-atr*InpTrailStepATR) && tr>ask+minDist) newSL=tr;
      }
      // Cost-aware net-profit lock: never loosens an existing protective stop.
      double netLockSL=0.0;
      if(NetProfitLockStop(ticket,sym,type,entry,lots,net,point,digits,minDist,price,netLockSL))
      {
         if(type==OP_BUY  && (newSL<=0 || netLockSL>newSL)) newSL=netLockSL;
         if(type==OP_SELL && (newSL<=0 || netLockSL<newSL)) newSL=netLockSL;
      }

      newSL=(newSL>0?NormalizeDouble(newSL,digits):0);
      if(type==OP_BUY)  slUp=(newSL>0 && (oldSL<=0 || newSL>oldSL+point*0.5));
      else              slUp=(newSL>0 && (oldSL<=0 || newSL<oldSL-point*0.5));

      // Adaptive TP: extend only when direction AND EMA slope confirm positive progression.
      // Neutral/unclear progression leaves the original broker-side TP untouched.
      double adx=iADX(sym,InpSignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
      if(oldTP>0 && progression>0 && favorable>=atr*InpTPExpandTriggerATR && adx>=InpTPExpandADXMin)
      {
         double remainingToTP=(type==OP_BUY?oldTP-bid:ask-oldTP);
         if(remainingToTP<=atr*InpTPExpandBufferATR)
         {
            double curDist=MathAbs(oldTP-entry);
            double want=MathMin(atr*InpTPMaxDistanceATR,MathMax(curDist,favorable+atr*InpTPExpandBufferATR));
            double prop=NormalizeDouble(type==OP_BUY?entry+want:entry-want,digits);
            if(type==OP_BUY  && prop>oldTP+point && prop>ask+minDist) { newTP=prop; tpUp=true; }
            if(type==OP_SELL && prop<oldTP-point && prop<bid-minDist) { newTP=prop; tpUp=true; }
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
//| Persistent peak-profit tracking and cost-aware net-profit lock    |
//+------------------------------------------------------------------+
string NetPeakKey(int ticket)
{
   return("BiteyNP_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket));
}

string RunnerActiveKey(int ticket)
{
   return("BiteyRunner_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket));
}

bool NetProfitLockStop(int ticket,string sym,int type,double entry,double lots,double net,
                       double point,int digits,double minDist,double marketPrice,double &stopOut)
{
   stopOut=0.0;
   if(InpTrendRunnerTriggerNetUSD<=0.0 || InpNetLockGivebackPct<0.0 || InpNetLockGivebackPct>=100.0) return(false);
   string key=NetPeakKey(ticket);
   double peak=(GlobalVariableCheck(key)?GlobalVariableGet(key):0.0);
   if(net>peak)
   {
      if(net-peak>=MathMax(0.01,InpNetLockStepUSD) || peak<=0.0) GlobalVariableSet(key,net);
      peak=MathMax(peak,net);
   }
   if(peak<InpTrendRunnerTriggerNetUSD) return(false);
   double lockNet=MathMax(InpNetLockMinUSD,peak*(1.0-InpNetLockGivebackPct/100.0));
   if(lockNet>=net) lockNet=MathMax(0.0,net-MathMax(0.05,InpNetLockMinUSD*0.10));
   if(lockNet<=0.0) return(false);
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   if(tv<=0.0 || ts<=0.0 || lots<=0.0 || point<=0.0) return(false);
   double moneyPerPrice=(tv/ts)*lots;
   if(moneyPerPrice<=0.0) return(false);
   // Floating OrderProfit is marked at Bid for BUY / Ask for SELL: spread is included.
   // Reserve estimated closing commission and adverse stop-fill slippage.
   double closeCommission=MathMax(0.0,InpEstimatedCloseCommissionPerLot)*lots;
   double slipReserve=0.0;
   if(InpNetLockSlippagePoints>0) slipReserve=EstimateRisk(sym,lots,InpNetLockSlippagePoints*point);
   if(slipReserve>=1.0e11) return(false);
   double requiredGross=lockNet-OrderSwap()-OrderCommission()+closeCommission+slipReserve;
   double move=requiredGross/moneyPerPrice;
   double candidate=NormalizeDouble(type==OP_BUY?entry+move:entry-move,digits);
   if(type==OP_BUY)
   {
      if(candidate<=entry || candidate>=marketPrice-minDist) return(false);
      if(OrderStopLoss()>0.0 && candidate<=OrderStopLoss()+point*0.5) return(false);
   }
   else
   {
      if(candidate>=entry || candidate<=marketPrice+minDist) return(false);
      if(OrderStopLoss()>0.0 && candidate>=OrderStopLoss()-point*0.5) return(false);
   }
   stopOut=candidate;
   return(true);
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

// Adverse entry-to-stop risk only; a stop at/after break-even counts as zero risk.
bool CurrencyRiskAllowed(string sym,double lots,double stopDist,double candidateRisk)
{
   if(InpMaxCurrencyRiskPct<=0.0 || IsCrypto(sym)) return(true);
   string key=AssetKey(sym);
   if(StringLen(key)<6) return(true); // Unknown/non-FX contract: retain aggregate-risk control
   string base=StringSubstr(key,0,3), quote=StringSubstr(key,3,3);
   double cap=InpReferenceCapitalUSD*InpMaxCurrencyRiskPct/100.0;
   double baseRisk=candidateRisk, quoteRisk=candidateRisk;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(IsCrypto(OrderSymbol())) continue;
      string k=AssetKey(OrderSymbol());
      if(StringLen(k)<6) continue;
      string b=StringSubstr(k,0,3), q=StringSubstr(k,3,3);
      double d=(OrderType()==OP_BUY?OrderOpenPrice()-OrderStopLoss():OrderStopLoss()-OrderOpenPrice());
      if(OrderStopLoss()<=0.0) return(false); // fail closed when an existing stop-risk is unknown
      double existing=0.0;
      if(d>0.0)
      {
         double op=MarketInfo(OrderSymbol(),MODE_POINT);
         double conservativeDist=d+MathMax(0,InpSlippagePoints)*MathMax(0.0,op);
         existing=EstimateRisk(OrderSymbol(),OrderLots(),conservativeDist);
      }
      if(b==base || q==base) baseRisk+=existing;
      if(b==quote || q==quote) quoteRisk+=existing;
   }
   if(baseRisk>cap+0.02 || quoteRisk>cap+0.02)
   {
      Print("CURRENCY_RISK_REJECT | symbol=",sym," base=",base," risk=",DoubleToString(baseRisk,2),
            " quote=",quote," risk2=",DoubleToString(quoteRisk,2)," cap=",DoubleToString(cap,2));
      return(false);
   }
   return(true);
}

double CurrentOpenRisk()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(OrderStopLoss()<=0) return(InpReferenceCapitalUSD);      // unknown risk fails closed
      double d=(OrderType()==OP_BUY?OrderOpenPrice()-OrderStopLoss():OrderStopLoss()-OrderOpenPrice());
      if(d>0)
      {
         double pt=MarketInfo(OrderSymbol(),MODE_POINT);
         double conservativeDist=d+MathMax(0,InpSlippagePoints)*MathMax(0.0,pt);
         total+=EstimateRisk(OrderSymbol(),OrderLots(),conservativeDist);
      }
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

bool InCooldown(string sym)
{
   if(InpCooldownBars<=0) return(false);
   datetime latest=0; double latestNet=0.0;
   int seen=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<80;i--)
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
   if(latest<=0 || latestNet>=0.0) return(false);
   return((TimeCurrent()-latest)<InpCooldownBars*PeriodSeconds(InpSignalTF));
}

//+------------------------------------------------------------------+
//| Sizing                                                            |
//+------------------------------------------------------------------+
double EstimateRisk(string sym,double lots,double stopDist)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
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

double LotsForRisk(string sym,double stopDist,double riskMoney)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   double minLot=MarketInfo(sym,MODE_MINLOT), maxLot=MarketInfo(sym,MODE_MAXLOT), step=MarketInfo(sym,MODE_LOTSTEP);
   if(riskMoney<=0 || tv<=0 || ts<=0 || stopDist<=0 || minLot<=0 || maxLot<minLot || step<=0) return(0.0);
   double lossPerLot=(stopDist/ts)*tv;
   if(lossPerLot<=0) return(0.0);
   double lots=MathFloor(riskMoney/lossPerLot/step+1e-9)*step;
   lots=MathMin(lots,maxLot);
   lots=NormalizeDouble(lots,LotDigits(step));
   if(lots<minLot) return(0.0);
   if(EstimateRisk(sym,lots,stopDist)>riskMoney+0.02) return(0.0);
   return(lots);
}

//+------------------------------------------------------------------+