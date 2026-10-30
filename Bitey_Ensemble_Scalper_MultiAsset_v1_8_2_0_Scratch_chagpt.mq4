//+------------------------------------------------------------------+
//| Bitey_Ensemble_Scalper_MultiAsset_v1_8_2_0_Scratch_chagpt.mq4    |
//| TPI Ensemble implementation - EXPERIMENTAL / compile & test first|
//+------------------------------------------------------------------+
#property strict
#property version "1.821"
#property description "TPI 7-evaluator EA; experimental; validate in Strategy Tester and demo"

// SAFETY: EnableTrading defaults TRUE as explicitly requested. Set FALSE
// before attaching to any chart until compile + tester + demo acceptance pass.
// No martingale, no averaging, no SL widening. EA manages only its MagicNumber.
input bool   EnableTrading=true;
input bool   EnableMultiAsset=true;
input string SymbolsCSV="EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,NZDUSD,EURJPY,GBPJPY";
input int    MagicNumber=30102620;
input double TargetNetProfitUSD=0.10;
input int    MaxTradeDurationMinutes=20;
input double RiskPercent=0.25;
input double DailyLossLimitPct=2.0;
input int    MaxTradesPerDay=3;
input int    MaxOpenPositions=3;
input int    MinimumVotes=5;
input int    StrictReentryVotes=6;
input int    MaxSpreadPoints=30;
input int    SlippagePoints=3;
input int    ATRPeriod=14;
input int    SignalTF=15; // PERIOD_M15
input int    RangeLookback=24;
input double StopATR=1.20;
input double TakeProfitATR=1.50;
input double MinATRPoints=8;
input double MaxATRPoints=2000;
input double EstimatedRoundTurnCommissionUSDPerLot=0.0; // configure from broker schedule
input int    CooldownTimeLossMinutes=20;
input int    CooldownStopMinutes=30;
input int    CooldownTwoLossesMinutes=60;
input bool   RequireStopLoss=true;
input bool   RequireTakeProfit=true;
input bool   EnableCSV=true;
input bool   EnablePersistentRecovery=true;
input bool   EnableBuy=true;
input bool   EnableSell=true;
input bool   EnableMartingale=false; // prohibited
input bool   EnableAveraging=false;  // prohibited
input bool   AllowStopLossWidening=false; // prohibited

#define V_NEUTRAL 0
#define V_BUY 1
#define V_SELL -1
#define V_ABSTAIN 9

string g_symbols[];
datetime g_lastBar[];
int g_csv=-1;
datetime g_day=0;
bool g_dailyLocked=false;

// Convert account-currency amount to USD. Returns false if no reliable quote.
bool AccountToUSD(double amount,double &usd)
{
   string cur=AccountCurrency();
   if(cur=="USD"){usd=amount; return true;}
   string direct=cur+"USD", inverse="USD"+cur;
   double bid=MarketInfo(direct,MODE_BID), ask=MarketInfo(inverse,MODE_ASK);
   if(bid>0){usd=amount*bid; return true;}
   if(ask>0){usd=amount/ask; return true;}
   return false;
}
double PipPoint(string s){return MarketInfo(s,MODE_POINT);}
double ATR(string s,int tf){return iATR(s,tf,ATRPeriod,1);}
bool IsNewBar(string s,int idx)
{
   datetime t=iTime(s,SignalTF,0);
   if(t<=0 || t==g_lastBar[idx]) return false;
   g_lastBar[idx]=t; return true;
}
int CountOpen()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==MagicNumber) n++;
   return n;
}
int CountOpenedToday()
{
   int n=0; datetime d=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==MagicNumber && OrderOpenTime()>=d) n++;
   for(int j=OrdersHistoryTotal()-1;j>=0;j--)
      if(OrderSelect(j,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==MagicNumber && OrderOpenTime()>=d) n++;
   return n;
}
double ClosedNetTodayUSD()
{
   double total=0, u=0; datetime d=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==MagicNumber && OrderCloseTime()>=d)
      {
         double a=OrderProfit()+OrderCommission()+OrderSwap();
         if(AccountToUSD(a,u)) total+=u;
      }
   return total;
}
bool DailyRiskOK()
{
   datetime d=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(d!=g_day){g_day=d; g_dailyLocked=false;}
   double lossLimit=AccountBalance()*DailyLossLimitPct/100.0;
   double net=ClosedNetTodayUSD();
   double netAccount=0;
   if(!AccountToUSD(AccountBalance(),netAccount) || netAccount<=0) return false;
   if(net<=-(lossLimit*netAccount/AccountBalance())) g_dailyLocked=true;
   return (!g_dailyLocked);
}
string GVName(string symbol,string suffix){return "BTP_"+IntegerToString(MagicNumber)+"_"+symbol+"_"+suffix;}
datetime CooldownUntil(string s)
{
   string k=GVName(s,"CD");
   if(GlobalVariableCheck(k)) return (datetime)GlobalVariableGet(k);
   return 0;
}
void SetCooldown(string s,int mins)
{
   if(!EnablePersistentRecovery) return;
   GlobalVariableSet(GVName(s,"CD"),(double)(TimeCurrent()+mins*60));
}
bool CostsOK(string s,double atr)
{
   double point=PipPoint(s), spread=MarketInfo(s,MODE_SPREAD);
   if(point<=0 || spread<=0 || spread>MaxSpreadPoints) return false;
   double atrPts=atr/point;
   if(atrPts<MinATRPoints || atrPts>MaxATRPoints) return false;
   // Do not double-subtract spread: it is already embedded in execution prices.
   // If configured commission is unknown (0), net-target estimator is conservative
   // only for already booked commission; user must set broker's round-turn estimate.
   return true;
}

// Seven deterministic evaluators; return BUY/SELL/NEUTRAL/ABSTAIN.
// Trend: EMA alignment + slope
int EvalTrend(string s)
{
   double f=iMA(s,SignalTF,9,0,MODE_EMA,PRICE_CLOSE,1);
   double m=iMA(s,SignalTF,21,0,MODE_EMA,PRICE_CLOSE,1);
   double slow=iMA(s,SignalTF,50,0,MODE_EMA,PRICE_CLOSE,1);
   if(f>m && m>slow) return V_BUY;
   if(f<m && m<slow) return V_SELL;
   return V_NEUTRAL;
}
// Range: fade outer Bollinger band only in low ADX regime
int EvalRange(string s)
{
   double adx=iADX(s,SignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
   double upper=iBands(s,SignalTF,20,2,0,PRICE_CLOSE,MODE_UPPER,1);
   double lower=iBands(s,SignalTF,20,2,0,PRICE_CLOSE,MODE_LOWER,1);
   double c=iClose(s,SignalTF,1);
   if(adx>22) return V_NEUTRAL;
   if(c<lower) return V_BUY;
   if(c>upper) return V_SELL;
   return V_NEUTRAL;
}
// Momentum: RSI and MACD histogram
int EvalMomentum(string s)
{
   double r=iRSI(s,SignalTF,14,PRICE_CLOSE,1);
   double mac=iMACD(s,SignalTF,12,26,9,PRICE_CLOSE,MODE_MAIN,1);
   double sig=iMACD(s,SignalTF,12,26,9,PRICE_CLOSE,MODE_SIGNAL,1);
   if(r>55 && mac>sig) return V_BUY;
   if(r<45 && mac<sig) return V_SELL;
   return V_NEUTRAL;
}
// Volatility: reject abnormal volatility; directional candle vote otherwise
int EvalVolatility(string s)
{
   double a=ATR(s,SignalTF), p=PipPoint(s);
   if(a<=0 || p<=0) return V_ABSTAIN;
   double pts=a/p;
   if(pts<MinATRPoints || pts>MaxATRPoints) return V_ABSTAIN;
   double o=iOpen(s,SignalTF,1), c=iClose(s,SignalTF,1);
   if(c>o) return V_BUY;
   if(c<o) return V_SELL;
   return V_NEUTRAL;
}
// Cost: veto via ABSTAIN; direction neutral when costs acceptable
int EvalCost(string s)
{
   double a=ATR(s,SignalTF);
   if(!CostsOK(s,a)) return V_ABSTAIN;
   return V_NEUTRAL;
}
// Session: avoid rollover / illiquid weekend hours
int EvalSession(string s)
{
   int h=TimeHour(TimeCurrent()), dow=TimeDayOfWeek(TimeCurrent());
   if(dow==0 || dow==6 || h==23 || h==0) return V_ABSTAIN;
   return V_NEUTRAL;
}
// Historical edge: recent closed-bar directional follow-through proxy
int EvalHistorical(string s)
{
   double c1=iClose(s,SignalTF,1), c4=iClose(s,SignalTF,4);
   double a=ATR(s,SignalTF);
   if(c1<=0 || c4<=0 || a<=0) return V_ABSTAIN;
   double move=c1-c4;
   if(move>a*0.35) return V_BUY;
   if(move< -a*0.35) return V_SELL;
   return V_NEUTRAL;
}
int Ensemble(string s,int &buyVotes,int &sellVotes,bool &veto)
{
   int v[7];
   v[0]=EvalTrend(s); v[1]=EvalRange(s); v[2]=EvalMomentum(s);
   v[3]=EvalVolatility(s); v[4]=EvalCost(s); v[5]=EvalSession(s); v[6]=EvalHistorical(s);
   buyVotes=0; sellVotes=0; veto=false;
   for(int i=0;i<7;i++)
   {
      if(v[i]==V_ABSTAIN && (i==4 || i==5 || i==3)) veto=true;
      if(v[i]==V_BUY) buyVotes++;
      if(v[i]==V_SELL) sellVotes++;
   }
   if(veto || buyVotes==sellVotes) return V_NEUTRAL;
   if(buyVotes>=MinimumVotes && buyVotes>sellVotes) return V_BUY;
   if(sellVotes>=MinimumVotes && sellVotes>buyVotes) return V_SELL;
   return V_NEUTRAL;
}
double LotsForRisk(string s,double stopDistance)
{
   double tickVal=MarketInfo(s,MODE_TICKVALUE), tickSize=MarketInfo(s,MODE_TICKSIZE);
   double minLot=MarketInfo(s,MODE_MINLOT), maxLot=MarketInfo(s,MODE_MAXLOT), step=MarketInfo(s,MODE_LOTSTEP);
   if(tickVal<=0 || tickSize<=0 || stopDistance<=0 || step<=0) return 0;
   double riskMoney=AccountBalance()*RiskPercent/100.0;
   double perLot=(stopDistance/tickSize)*tickVal;
   if(perLot<=0) return 0;
   double lots=MathFloor((riskMoney/perLot)/step)*step;
   lots=MathMax(minLot,MathMin(maxLot,lots));
   if(AccountFreeMarginCheck(s,OP_BUY,lots)<=0) return 0;
   return NormalizeDouble(lots,2);
}
bool HasSymbolPosition(string s)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==MagicNumber && OrderSymbol()==s) return true;
   return false;
}
bool HasRecentLoss(string s)
{
   datetime latest=0; double lastNet=0; int consecutive=0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==MagicNumber && OrderSymbol()==s)
      {
         if(OrderCloseTime()>latest){latest=OrderCloseTime(); lastNet=OrderProfit()+OrderCommission()+OrderSwap();}
      }
   return (lastNet<0);
}
void Audit(string event,string sym,int ticket,double net,string reason)
{
   if(!EnableCSV) return;
   if(g_csv<0) g_csv=FileOpen("Bitey_TPI_"+IntegerToString(MagicNumber)+".csv",FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_WRITE,';');
   if(g_csv<0) return;
   FileSeek(g_csv,0,SEEK_END);
   FileWrite(g_csv,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),event,sym,ticket,DoubleToString(net,4),reason);
   FileFlush(g_csv);
}
double EstimatedNetUSD()
{
   double acc=OrderProfit()+OrderCommission()+OrderSwap();
   // Estimate not-yet-booked closing commission, without subtracting spread again.
   if(EstimatedRoundTurnCommissionUSDPerLot>0)
   {
      double bookedUSD=0, est=EstimatedRoundTurnCommissionUSDPerLot*OrderLots();
      if(AccountToUSD(acc,bookedUSD)) return bookedUSD-est*0.5;
   }
   double usd=0;
   if(!AccountToUSD(acc,usd)) return -1.0e10;
   return usd;
}
void ManageOpenTrades()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      string s=OrderSymbol(); int ticket=OrderTicket();
      int age=(int)((TimeCurrent()-OrderOpenTime())/60);
      double net=EstimatedNetUSD();
      bool closeNow=false; string why="";
      if(net>=TargetNetProfitUSD){closeNow=true; why="NET_TARGET";}
      if(!closeNow && age>=MaxTradeDurationMinutes){closeNow=true; why="TIME_EXIT";}
      if(closeNow)
      {
         RefreshRates();
         double px=(OrderType()==OP_BUY)?MarketInfo(s,MODE_BID):MarketInfo(s,MODE_ASK);
         if(px>0 && OrderClose(ticket,OrderLots(),px,SlippagePoints,clrNONE))
         {
            Audit("CLOSE",s,ticket,net,why);
            if(net<0) SetCooldown(s,(why=="TIME_EXIT"?CooldownTimeLossMinutes:CooldownStopMinutes));
         }
         else Print("TPI_CLOSE_FAIL ticket=",ticket," err=",GetLastError());
      }
   }
}
void ScanSymbol(string s)
{
   if(!EnableTrading || !DailyRiskOK()) return;
   if(CountOpen()>=MaxOpenPositions || CountOpenedToday()>=MaxTradesPerDay) return;
   if(!IsConnected() || !IsTradeAllowed() || !MarketInfo(s,MODE_TRADEALLOWED)) return;
   if(HasSymbolPosition(s) || TimeCurrent()<CooldownUntil(s)) return;
   if(HasRecentLoss(s) && StrictReentryVotes>MinimumVotes) { /* strict votes applied below */ }
   double atr=ATR(s,SignalTF);
   if(atr<=0 || !CostsOK(s,atr)) return;
   int bv=0,sv=0; bool veto=false;
   int dir=Ensemble(s,bv,sv,veto);
   int needed=(HasRecentLoss(s)?StrictReentryVotes:MinimumVotes);
   if(veto || MathMax(bv,sv)<needed) return;
   if(dir==V_BUY && !EnableBuy) return;
   if(dir==V_SELL && !EnableSell) return;
   if(dir!=V_BUY && dir!=V_SELL) return;
   double point=MarketInfo(s,MODE_POINT), bid=MarketInfo(s,MODE_BID), ask=MarketInfo(s,MODE_ASK);
   int digits=(int)MarketInfo(s,MODE_DIGITS);
   if(point<=0 || bid<=0 || ask<=0) return;
   double entry=(dir==V_BUY?ask:bid);
   double slDist=atr*StopATR, tpDist=atr*TakeProfitATR;
   double sl=(dir==V_BUY?entry-slDist:entry+slDist);
   double tp=(dir==V_BUY?entry+tpDist:entry-tpDist);
   sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);
   if(RequireStopLoss && (sl<=0 || MathAbs(entry-sl)<MarketInfo(s,MODE_STOPLEVEL)*point)) return;
   if(RequireTakeProfit && tp<=0) return;
   double lots=LotsForRisk(s,slDist);
   if(lots<=0) return;
   int type=(dir==V_BUY?OP_BUY:OP_SELL);
   ResetLastError();
   int ticket=OrderSend(s,type,lots,entry,SlippagePoints,sl,tp,"Bitey TPI 7-vote",MagicNumber,0,clrNONE);
   if(ticket>0) Audit("OPEN",s,ticket,0.0,StringFormat("votes=%d/%d",bv,sv));
   else Print("TPI_ORDER_SEND_FAIL symbol=",s," err=",GetLastError());
}
int OnInit()
{
   if(EnableMartingale || EnableAveraging || AllowStopLossWidening ||
      TargetNetProfitUSD<=0 || MaxTradeDurationMinutes<=0 || MinimumVotes<1 ||
      MinimumVotes>7 || StrictReentryVotes<MinimumVotes || RiskPercent<=0 ||
      DailyLossLimitPct<=0 || MaxTradesPerDay<1 || MaxOpenPositions<1 ||
      StopATR<=0 || TakeProfitATR<=0)
      return INIT_PARAMETERS_INCORRECT;
   int n=StringSplit(SymbolsCSV,',',g_symbols);
   if(n<1) return INIT_PARAMETERS_INCORRECT;
   ArrayResize(g_lastBar,n);
   for(int i=0;i<n;i++){StringTrimLeft(g_symbols[i]);StringTrimRight(g_symbols[i]);g_lastBar[i]=0;SymbolSelect(g_symbols[i],true);}
   g_day=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   EventSetTimer(1);
   Print("BITEY_TPI_1.821 initialized. EnableTrading=",EnableTrading,
         ". Experimental; run Strategy Tester and demo before live use.");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){EventKillTimer(); if(g_csv>=0) FileClose(g_csv);}
void OnTimer(){ManageOpenTrades();}
void OnTick()
{
   ManageOpenTrades();
   if(!EnableTrading) return;
   if(EnableMultiAsset)
   {
      for(int i=0;i<ArraySize(g_symbols);i++)
         if(IsNewBar(g_symbols[i],i)) ScanSymbol(g_symbols[i]);
   }
   else
   {
      string s=Symbol();
      if(IsNewBar(s,0)) ScanSymbol(s);
   }
}
