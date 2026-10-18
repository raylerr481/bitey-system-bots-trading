#property strict
#property version   "1.33"
#property description "AI Trading Bot v1.33 - Entry Diagnostics"

// v1.33 keeps v1.32 risk/management and instruments the entry engine.
// It is a diagnostic build: it does not optimize parameters automatically.

input bool   InpAllowBuy=true;
input bool   InpAllowSell=true;
input double InpRiskPct=0.25;
input int    InpMaxTrades=1;
input int    InpMaxSpreadPoints=30;
input double InpMaxSpreadATRRatio=0.20;
input int    InpATRPeriod=14;
input double InpMinATRPoints=20.0;
input int    InpADXPeriod=14;
input double InpADXMin=20.0;
input int    InpRSIPeriod=14;
input double InpRSIBuyMin=50.0;
input double InpRSIBuyMax=68.0;
input double InpRSISellMin=32.0;
input double InpRSISellMax=50.0;
input int    InpFastEMA=8;
input int    InpSlowEMA=21;
input int    InpMacroEMA=200;
input bool   InpUseMacroSlope=true;
input bool   InpUseHTFTrend=false;
input ENUM_TIMEFRAMES InpHTF=PERIOD_H4;
input int    InpBuyMinScore=5;
input int    InpSellMinScore=5;
input double InpSLMult=1.30;
input double InpTPMult=2.60;
input bool   InpUseBreakEven=true;
input double InpBEStartMult=1.25;
input double InpBELockMult=0.05;
input bool   InpUseTrailing=true;
input double InpTrailStartMult=1.80;
input double InpTrailDistMult=1.00;
input int    InpStartHour=7;
input int    InpEndHour=20;
input int    InpFridayCloseHour=21;
input int    InpCooldownBars=3;
input int    InpMagicNumber=8883200;
input bool   InpVerboseLog=true;

// Entry diagnostics. These do not change execution unless explicitly enabled.
input bool   InpHardRSIFilter=false;
input bool   InpAvoidExtremeRSI=false;
input double InpExtremeBuyRSI=78.0;
input double InpExtremeSellRSI=22.0;
input bool   InpUseADXRegime=false;
input double InpMaxADXForEntry=70.0;
input bool   InpUseMinScoreOverride=false;
input int    InpBuyScoreOverride=5;
input int    InpSellScoreOverride=5;
input bool   InpWriteCSV=true;
input string InpCSVFile="AI_Trading_Bot_v1.33_EntryDiagnostics.csv";

// Management remains equivalent to v1.32 Mode 3: fixed SL/TP only by default.
input int    InpManagementMode=3; // 0=BE+Trailing, 1=BE only, 2=Trailing only, 3=Fixed SL/TP

struct PositionDiag
{
   int ticket;
   datetime openTime;
   int type;
   double entry;
   double initialSL;
   double initialTP;
   double atr;
   double adx;
   double rsi;
   double fast;
   double slow;
   double macro;
   double macroPrev;
   double buyScore;
   double sellScore;
   double maePts;
   double mfePts;
};

PositionDiag g_pos;
bool g_hasPos=false;
datetime g_lastBar=0;
datetime g_lastEntryBar=0;
int g_wins=0, g_losses=0, g_winStreak=0, g_lossStreak=0, g_maxWinStreak=0, g_maxLossStreak=0;
int g_buySignals=0, g_sellSignals=0, g_buyOrders=0, g_sellOrders=0;
int g_blockSpread=0, g_blockATR=0, g_blockSession=0, g_blockCooldown=0, g_blockScore=0, g_blockRSI=0, g_blockADX=0, g_orderErrors=0;

string DirName(int type){ return(type==OP_BUY ? "BUY" : "SELL"); }

bool NewBar()
{
   datetime t=iTime(_Symbol,_Period,0);
   if(t==0) return(false);
   if(t!=g_lastBar){ g_lastBar=t; return(true); }
   return(false);
}

int OpenTrades()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderSymbol()==_Symbol && OrderMagicNumber()==InpMagicNumber)
         n++;
   return(n);
}

bool InSession()
{
   int h=TimeHour(TimeCurrent());
   int dow=TimeDayOfWeek(TimeCurrent());
   if(dow==0 || dow==6) return(false);
   if(dow==5 && h>=InpFridayCloseHour) return(false);
   if(InpStartHour<=InpEndHour) return(h>=InpStartHour && h<InpEndHour);
   return(h>=InpStartHour || h<InpEndHour);
}

bool CooldownOK()
{
   if(g_lastEntryBar==0) return(true);
   int shift=iBarShift(_Symbol,_Period,g_lastEntryBar,false);
   return(shift>=InpCooldownBars || shift<0);
}

double ATR(int shift=1){ return(iATR(_Symbol,_Period,InpATRPeriod,shift)); }
double ADX(int shift=1){ return(iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,shift)); }
double RSI(int shift=1){ return(iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,shift)); }
double EMA(int period,int shift=1){ return(iMA(_Symbol,_Period,period,0,MODE_EMA,PRICE_CLOSE,shift)); }

double SpreadPoints(){ return((Ask-Bid)/_Point); }

double NormalizeLots(double lots)
{
   double minLot=MarketInfo(_Symbol,MODE_MINLOT);
   double maxLot=MarketInfo(_Symbol,MODE_MAXLOT);
   double step=MarketInfo(_Symbol,MODE_LOTSTEP);
   if(step<=0) step=0.01;
   lots=MathMin(lots,maxLot);
   lots=MathMax(lots,minLot);
   lots=MathFloor(lots/step+1e-8)*step;
   return(NormalizeDouble(lots,2));
}

double LotsForRisk(double stopDistancePrice)
{
   double riskMoney=AccountBalance()*InpRiskPct/100.0;
   double tickValue=MarketInfo(_Symbol,MODE_TICKVALUE);
   double tickSize=MarketInfo(_Symbol,MODE_TICKSIZE);
   if(riskMoney<=0 || tickValue<=0 || tickSize<=0 || stopDistancePrice<=0) return(0);
   double lossPerLot=(stopDistancePrice/tickSize)*tickValue;
   if(lossPerLot<=0) return(0);
   return(NormalizeLots(riskMoney/lossPerLot));
}

int BuyScore(double atr,double adx,double rsi,double fast,double slow,double macro,double macroPrev,double close1)
{
   int s=0;
   if(close1>macro) s++;
   if(fast>slow) s++;
   if(adx>=InpADXMin) s++;
   if(rsi>=InpRSIBuyMin && rsi<=InpRSIBuyMax) s++;
   if(atr/_Point>=InpMinATRPoints) s++;
   if(iClose(_Symbol,_Period,2)<=EMA(InpFastEMA,2) && fast>slow) s++;
   if(close1>fast && close1>iClose(_Symbol,_Period,2)) s++;
   return(s);
}

int SellScore(double atr,double adx,double rsi,double fast,double slow,double macro,double macroPrev,double close1)
{
   int s=0;
   if(close1<macro) s++;
   if(fast<slow) s++;
   if(adx>=InpADXMin) s++;
   if(rsi>=InpRSISellMin && rsi<=InpRSISellMax) s++;
   if(atr/_Point>=InpMinATRPoints) s++;
   if(iClose(_Symbol,_Period,2)>=EMA(InpFastEMA,2) && fast<slow) s++;
   if(close1<fast && close1<iClose(_Symbol,_Period,2)) s++;
   return(s);
}

bool HTFBuyOK(){ if(!InpUseHTFTrend) return(true); return(iClose(_Symbol,InpHTF,1)>iMA(_Symbol,InpHTF,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1)); }
bool HTFSellOK(){ if(!InpUseHTFTrend) return(true); return(iClose(_Symbol,InpHTF,1)<iMA(_Symbol,InpHTF,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1)); }

void WriteHeader()
{
   if(!InpWriteCSV) return;
   int h=FileOpen(InpCSVFile,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
   {
      FileWrite(h,"event","ticket","time","direction","entry","sl","tp","result","score_buy","score_sell","atr_points","adx","rsi","ema_fast","ema_slow","ema200","ema200_prev","ema200_slope_points","mae_points","mfe_points","mae_R","mfe_R","duration_min","exit_reason");
   }
   FileClose(h);
}

void CSVEntry(int ticket,int type,double entry,double sl,double tp,double atr,double adx,double rsi,double fast,double slow,double macro,double macroPrev,int bs,int ss)
{
   if(!InpWriteCSV) return;
   int h=FileOpen(InpCSVFile,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,"ENTRY",ticket,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),DirName(type),DoubleToString(entry,_Digits),DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),"0",bs,ss,DoubleToString(atr/_Point,1),DoubleToString(adx,1),DoubleToString(rsi,1),DoubleToString(fast,_Digits),DoubleToString(slow,_Digits),DoubleToString(macro,_Digits),DoubleToString(macroPrev,_Digits),DoubleToString((macro-macroPrev)/_Point,1),"","","","","","");
   FileClose(h);
}

void UpdateMAEMFE()
{
   if(!g_hasPos) return;
   if(!OrderSelect(g_pos.ticket,SELECT_BY_TICKET,MODE_TRADES)) return;
   double px=(g_pos.type==OP_BUY ? Bid : Ask);
   double adverse=(g_pos.type==OP_BUY ? g_pos.entry-Low[0] : High[0]-g_pos.entry)/_Point;
   double favorable=(g_pos.type==OP_BUY ? High[0]-g_pos.entry : g_pos.entry-Low[0])/_Point;
   if(adverse<0) adverse=0;
   if(favorable<0) favorable=0;
   if(adverse>g_pos.maePts) g_pos.maePts=adverse;
   if(favorable>g_pos.mfePts) g_pos.mfePts=favorable;
}

string ExitReason(double closePrice,double tp,double sl)
{
   double tol=2*_Point;
   if(MathAbs(closePrice-tp)<=tol) return("TP");
   if(MathAbs(closePrice-sl)<=tol) return("SL");
   return("OTHER");
}

void RecordClosed(int ticket)
{
   if(!g_hasPos || g_pos.ticket!=ticket) return;
   double result=0;
   if(OrderSelect(ticket,SELECT_BY_TICKET,MODE_HISTORY)) result=OrderProfit()+OrderSwap()+OrderCommission();
   string reason=ExitReason(OrderClosePrice(),g_pos.initialTP,g_pos.initialSL);
   double riskPts=MathAbs(g_pos.entry-g_pos.initialSL)/_Point;
   double maeR=(riskPts>0 ? g_pos.maePts/riskPts : 0);
   double mfeR=(riskPts>0 ? g_pos.mfePts/riskPts : 0);
   int duration=(int)((OrderCloseTime()-g_pos.openTime)/60);
   if(result>=0){g_wins++;g_winStreak++;g_lossStreak=0;if(g_winStreak>g_maxWinStreak)g_maxWinStreak=g_winStreak;}
   else {g_losses++;g_lossStreak++;g_winStreak=0;if(g_lossStreak>g_maxLossStreak)g_maxLossStreak=g_lossStreak;}
   if(InpWriteCSV)
   {
      int h=FileOpen(InpCSVFile,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
      if(h!=INVALID_HANDLE){
         FileSeek(h,0,SEEK_END);
         FileWrite(h,"EXIT",ticket,TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),DirName(g_pos.type),DoubleToString(g_pos.entry,_Digits),DoubleToString(g_pos.initialSL,_Digits),DoubleToString(g_pos.initialTP,_Digits),DoubleToString(result,2),g_pos.buyScore,g_pos.sellScore,DoubleToString(g_pos.atr/_Point,1),DoubleToString(g_pos.adx,1),DoubleToString(g_pos.rsi,1),DoubleToString(g_pos.fast,_Digits),DoubleToString(g_pos.slow,_Digits),DoubleToString(g_pos.macro,_Digits),DoubleToString(g_pos.macroPrev,_Digits),DoubleToString((g_pos.macro-g_pos.macroPrev)/_Point,1),DoubleToString(g_pos.maePts,1),DoubleToString(g_pos.mfePts,1),DoubleToString(maeR,2),DoubleToString(mfeR,2),duration,reason);
         FileClose(h);
      }
   }
   if(InpVerboseLog) Print("EXIT #",ticket," ",DirName(g_pos.type)," result=",DoubleToString(result,2)," reason=",reason," MAE_R=",DoubleToString(maeR,2)," MFE_R=",DoubleToString(mfeR,2)," duration=",duration,"min");
   g_hasPos=false;
}

void SyncClosed()
{
   if(!g_hasPos) return;
   if(!OrderSelect(g_pos.ticket,SELECT_BY_TICKET,MODE_TRADES)) RecordClosed(g_pos.ticket);
}

void CaptureOpen(int ticket,int type,double entry,double sl,double tp,double atr,double adx,double rsi,double fast,double slow,double macro,double macroPrev,int bs,int ss)
{
   g_hasPos=true;
   g_pos.ticket=ticket;g_pos.openTime=TimeCurrent();g_pos.type=type;g_pos.entry=entry;g_pos.initialSL=sl;g_pos.initialTP=tp;g_pos.atr=atr;g_pos.adx=adx;g_pos.rsi=rsi;g_pos.fast=fast;g_pos.slow=slow;g_pos.macro=macro;g_pos.macroPrev=macroPrev;g_pos.buyScore=bs;g_pos.sellScore=ss;g_pos.maePts=0;g_pos.mfePts=0;
   CSVEntry(ticket,type,entry,sl,tp,atr,adx,rsi,fast,slow,macro,macroPrev,bs,ss);
}

void ManagePositions()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=_Symbol || OrderMagicNumber()!=InpMagicNumber) continue;
      double atr=ATR(0); if(atr<=0) continue;
      if(InpManagementMode==3) continue;
      if(OrderType()==OP_BUY)
      {
         double profitDist=Bid-OrderOpenPrice();
         if(InpManagementMode==0 || InpManagementMode==1)
         {
            if(InpUseBreakEven && profitDist>=InpBEStartMult*atr)
            {
               double newSL=NormalizeDouble(OrderOpenPrice()+InpBELockMult*atr,_Digits);
               if(OrderStopLoss()<newSL && newSL<Bid) OrderModify(OrderTicket(),OrderOpenPrice(),newSL,OrderTakeProfit(),0,clrNONE);
            }
         }
         if(InpManagementMode==0 || InpManagementMode==2)
         {
            if(InpUseTrailing && profitDist>=InpTrailStartMult*atr)
            {
               double newSL=NormalizeDouble(Bid-InpTrailDistMult*atr,_Digits);
               if(newSL>OrderStopLoss() && newSL<Bid) OrderModify(OrderTicket(),OrderOpenPrice(),newSL,OrderTakeProfit(),0,clrNONE);
            }
         }
      }
      else if(OrderType()==OP_SELL)
      {
         double profitDist=OrderOpenPrice()-Ask;
         if(InpManagementMode==0 || InpManagementMode==1)
         {
            if(InpUseBreakEven && profitDist>=InpBEStartMult*atr)
            {
               double newSL=NormalizeDouble(OrderOpenPrice()-InpBELockMult*atr,_Digits);
               if((OrderStopLoss()==0 || OrderStopLoss()>newSL) && newSL>Ask) OrderModify(OrderTicket(),OrderOpenPrice(),newSL,OrderTakeProfit(),0,clrNONE);
            }
         }
         if(InpManagementMode==0 || InpManagementMode==2)
         {
            if(InpUseTrailing && profitDist>=InpTrailStartMult*atr)
            {
               double newSL=NormalizeDouble(Ask+InpTrailDistMult*atr,_Digits);
               if((OrderStopLoss()==0 || newSL<OrderStopLoss()) && newSL>Ask) OrderModify(OrderTicket(),OrderOpenPrice(),newSL,OrderTakeProfit(),0,clrNONE);
            }
         }
      }
   }
}

bool EntryFilters(double atr)
{
   double spread=SpreadPoints();
   if(spread>InpMaxSpreadPoints){g_blockSpread++;return(false);}
   if(atr<=0 || atr/_Point<InpMinATRPoints){g_blockATR++;return(false);}
   if(atr>0 && spread/(atr/_Point)>InpMaxSpreadATRRatio){g_blockSpread++;return(false);}
   if(!InSession()){g_blockSession++;return(false);}
   if(!CooldownOK()){g_blockCooldown++;return(false);}
   return(true);
}

void Analyze()
{
   if(OpenTrades()>=InpMaxTrades) return;
   double atr=ATR(1), adx=ADX(1), rsi=RSI(1);
   double fast=EMA(InpFastEMA,1), slow=EMA(InpSlowEMA,1), macro=EMA(InpMacroEMA,1), macroPrev=EMA(InpMacroEMA,2);
   double close1=iClose(_Symbol,_Period,1);
   if(!EntryFilters(atr)) return;
   if(InpUseADXRegime && adx>InpMaxADXForEntry){g_blockADX++;return;}
   int bs=BuyScore(atr,adx,rsi,fast,slow,macro,macroPrev,close1);
   int ss=SellScore(atr,adx,rsi,fast,slow,macro,macroPrev,close1);
   if(InpUseMinScoreOverride){bs=MathMin(bs,7);ss=MathMin(ss,7);}
   bool buyCandidate=InpAllowBuy && bs>=(InpUseMinScoreOverride?InpBuyScoreOverride:InpBuyMinScore) && HTFBuyOK();
   bool sellCandidate=InpAllowSell && ss>=(InpUseMinScoreOverride?InpSellScoreOverride:InpSellMinScore) && HTFSellOK();
   if(InpHardRSIFilter)
   {
      if(buyCandidate && (rsi<InpRSIBuyMin || rsi>InpRSIBuyMax)) {buyCandidate=false;g_blockRSI++;}
      if(sellCandidate && (rsi<InpRSISellMin || rsi>InpRSISellMax)) {sellCandidate=false;g_blockRSI++;}
   }
   if(InpAvoidExtremeRSI)
   {
      if(buyCandidate && rsi>=InpExtremeBuyRSI){buyCandidate=false;g_blockRSI++;}
      if(sellCandidate && rsi<=InpExtremeSellRSI){sellCandidate=false;g_blockRSI++;}
   }
   if(buyCandidate) g_buySignals++;
   if(sellCandidate) g_sellSignals++;
   if(!buyCandidate && !sellCandidate){g_blockScore++;return;}
   int type=-1;
   if(buyCandidate && sellCandidate) type=(bs>ss?OP_BUY:(ss>bs?OP_SELL:-1));
   else if(buyCandidate) type=OP_BUY;
   else if(sellCandidate) type=OP_SELL;
   if(type<0) return;
   double stopDist=atr*InpSLMult, tpDist=atr*InpTPMult;
   double lots=LotsForRisk(stopDist);
   if(lots<=0) return;
   RefreshRates();
   double price=(type==OP_BUY?Ask:Bid);
   double sl=(type==OP_BUY?price-stopDist:price+stopDist);
   double tp=(type==OP_BUY?price+tpDist:price-tpDist);
   sl=NormalizeDouble(sl,_Digits);tp=NormalizeDouble(tp,_Digits);price=NormalizeDouble(price,_Digits);
   int ticket=OrderSend(_Symbol,type,lots,price,5,sl,tp,"v1.33 EntryDiag",InpMagicNumber,0,clrNONE);
   if(ticket<0){g_orderErrors++;if(InpVerboseLog)Print("OrderSend error=",GetLastError());return;}
   g_lastEntryBar=iTime(_Symbol,_Period,0);
   if(type==OP_BUY) g_buyOrders++; else g_sellOrders++;
   CaptureOpen(ticket,type,price,sl,tp,atr,adx,rsi,fast,slow,macro,macroPrev,bs,ss);
   if(InpVerboseLog) Print("v1.33 bar=",TimeToString(iTime(_Symbol,_Period,1),TIME_DATE|TIME_MINUTES)," BUYscore=",bs," SELLscore=",ss," ATRpts=",DoubleToString(atr/_Point,1)," ADX=",DoubleToString(adx,1)," RSI=",DoubleToString(rsi,1)," EMA8=",DoubleToString(fast,_Digits)," EMA21=",DoubleToString(slow,_Digits)," EMA200=",DoubleToString(macro,_Digits)," slopePts=",DoubleToString((macro-macroPrev)/_Point,1));
}

void OnInitStats(){g_lastBar=0;g_lastEntryBar=0;g_hasPos=false;WriteHeader();}

int OnInit()
{
   OnInitStats();
   Print("===== AI TRADING BOT v1.33 ENTRY DIAGNOSTICS =====");
   Print("Risk=",DoubleToString(InpRiskPct,2),"% MaxTrades=",InpMaxTrades," ManagementMode=",InpManagementMode);
   Print("HardRSI=",InpHardRSIFilter," AvoidExtremeRSI=",InpAvoidExtremeRSI," ADXRegime=",InpUseADXRegime);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   SyncClosed();
   Print("===== v1.33 SUMMARY =====");
   Print("Wins=",g_wins," Losses=",g_losses," maxWinStreak=",g_maxWinStreak," maxLossStreak=",g_maxLossStreak);
   Print("BUY signals=",g_buySignals," orders=",g_buyOrders," | SELL signals=",g_sellSignals," orders=",g_sellOrders);
   Print("Blocks spread=",g_blockSpread," ATR=",g_blockATR," session=",g_blockSession," cooldown=",g_blockCooldown," score=",g_blockScore," RSI=",g_blockRSI," ADX=",g_blockADX," orderErrors=",g_orderErrors);
}

void OnTick()
{
   SyncClosed();
   ManagePositions();
   UpdateMAEMFE();
   if(NewBar()) Analyze();
}
