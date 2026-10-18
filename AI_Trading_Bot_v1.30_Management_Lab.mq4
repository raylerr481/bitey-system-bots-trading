#property strict
#property version   "1.30"
#property description "AI Trading Bot v1.30 - Management Lab"

input bool   InpAllowBuy=true;
input bool   InpAllowSell=true;
input double InpRiskPct=0.25;
input int    InpMaxTrades=1;
input int    InpMagicNumber=8883200;

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
input int    InpMinScore=5;

input double InpSLMult=1.30;
input double InpTPMult=2.60;
input bool   InpUseBreakEven=true;
input double InpBEStartMult=1.10;
input double InpBELockMult=0.05;
input bool   InpUseTrailing=true;
input double InpTrailStartMult=1.60;
input double InpTrailDistMult=0.90;

input int    InpStartHour=7;
input int    InpEndHour=20;
input int    InpFridayCloseHour=21;
input int    InpCooldownBars=3;
input bool   InpLogEveryBar=false;

// Management lab: disable individual management components to compare behavior.
input bool   InpLabDisableBE=false;
input bool   InpLabDisableTrailing=false;

long g_bars=0, g_buySignals=0, g_sellSignals=0, g_buyOrders=0, g_sellOrders=0;
long g_orderErrors=0, g_blockSpread=0, g_blockATR=0, g_blockSession=0, g_blockCooldown=0;
long g_beMoves=0, g_trailMoves=0, g_slExits=0, g_tpExits=0, g_manualOrOtherExits=0;
datetime g_lastBar=0, g_lastTradeBar=0;
int g_lastHistoryTotal=0;

string CsvName(){ return "AI_Trading_Bot_v1.30_ManagementLab.csv"; }

bool NewBar(){
   datetime t=iTime(_Symbol,_Period,0);
   if(t!=g_lastBar){g_lastBar=t; return true;}
   return false;
}

int OpenTrades(){
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         if(OrderSymbol()==_Symbol && OrderMagicNumber()==InpMagicNumber && (OrderType()==OP_BUY || OrderType()==OP_SELL)) n++;
   }
   return n;
}

double LotByRisk(double slDistance){
   double riskMoney=AccountBalance()*InpRiskPct/100.0;
   double tickValue=MarketInfo(_Symbol,MODE_TICKVALUE);
   double tickSize=MarketInfo(_Symbol,MODE_TICKSIZE);
   double step=MarketInfo(_Symbol,MODE_LOTSTEP);
   double minLot=MarketInfo(_Symbol,MODE_MINLOT);
   double maxLot=MarketInfo(_Symbol,MODE_MAXLOT);
   if(step<=0) step=0.01;
   if(tickValue<=0 || tickSize<=0 || slDistance<=0) return minLot;
   double lossPerLot=slDistance/tickSize*tickValue;
   if(lossPerLot<=0) return minLot;
   double lots=riskMoney/lossPerLot;
   lots=MathMin(lots,maxLot);
   lots=MathFloor(lots/step)*step;
   lots=MathMax(lots,minLot);
   return NormalizeDouble(lots,2);
}

bool MarketOK(double atr){
   int h=TimeHour(TimeCurrent());
   int dow=TimeDayOfWeek(TimeCurrent());
   double spread=(Ask-Bid)/Point;
   if(spread>InpMaxSpreadPoints){g_blockSpread++;return false;}
   if(atr/Point<InpMinATRPoints){g_blockATR++;return false;}
   if(atr>0 && spread/ (atr/Point) > InpMaxSpreadATRRatio){g_blockSpread++;return false;}
   if(h<InpStartHour || h>=InpEndHour || (dow==5 && h>=InpFridayCloseHour)){g_blockSession++;return false;}
   return true;
}

bool CooldownOK(){
   if(g_lastTradeBar==0) return true;
   int shift=iBarShift(_Symbol,_Period,g_lastTradeBar,true);
   if(shift<0) return true;
   if(shift<InpCooldownBars){g_blockCooldown++;return false;}
   return true;
}

int ScoreBuy(double c1,double fast1,double slow1,double macro1,double macro2,double adx,double rsi,double atr){
   int s=0;
   if(c1>macro1) s++;
   if(fast1>slow1) s++;
   if(adx>=InpADXMin) s++;
   if(rsi>=InpRSIBuyMin && rsi<=InpRSIBuyMax) s++;
   if(atr/Point>=InpMinATRPoints) s++;
   double fast2=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   if(fast1>fast2) s++;
   if(InpUseMacroSlope ? (macro1>macro2) : true) s++;
   return s;
}

int ScoreSell(double c1,double fast1,double slow1,double macro1,double macro2,double adx,double rsi,double atr){
   int s=0;
   if(c1<macro1) s++;
   if(fast1<slow1) s++;
   if(adx>=InpADXMin) s++;
   if(rsi>=InpRSISellMin && rsi<=InpRSISellMax) s++;
   if(atr/Point>=InpMinATRPoints) s++;
   double fast2=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   if(fast1<fast2) s++;
   if(InpUseMacroSlope ? (macro1<macro2) : true) s++;
   return s;
}

void WriteCSVHeader(){
   int h=FileOpen(CsvName(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0) FileWrite(h,"time","symbol","type","lots","open","sl","tp","close","profit","r_result","atr","adx","rsi","duration_bars","exit_reason");
   FileClose(h);
}

string ExitReason(double profit){
   double cp=OrderClosePrice(), sl=OrderStopLoss(), tp=OrderTakeProfit();
   double tol=Point*5;
   if(sl>0 && MathAbs(cp-sl)<=tol) return "SL";
   if(tp>0 && MathAbs(cp-tp)<=tol) return "TP";
   return profit>=0 ? "MANAGEMENT_PROFIT" : "MANAGEMENT_LOSS";
}

void AuditHistory(){
   int total=OrdersHistoryTotal();
   if(total<=g_lastHistoryTotal) return;
   for(int i=g_lastHistoryTotal;i<total;i++){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=_Symbol || OrderMagicNumber()!=InpMagicNumber) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      double riskPerLot=MathAbs(OrderOpenPrice()-OrderStopLoss());
      double tickValue=MarketInfo(_Symbol,MODE_TICKVALUE), tickSize=MarketInfo(_Symbol,MODE_TICKSIZE);
      double riskMoney=(tickValue>0&&tickSize>0)?OrderLots()*riskPerLot/tickSize*tickValue:0;
      double r=(riskMoney>0)?(OrderProfit()+OrderSwap()+OrderCommission())/riskMoney:0;
      int dur=iBarShift(_Symbol,_Period,OrderOpenTime(),false)-iBarShift(_Symbol,_Period,OrderCloseTime(),false);
      if(dur<0) dur=-dur;
      int h=FileOpen(CsvName(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_WRITE,',');
      if(h!=INVALID_HANDLE){FileSeek(h,0,SEEK_END);FileWrite(h,TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),_Symbol,(OrderType()==OP_BUY?"BUY":"SELL"),DoubleToString(OrderLots(),2),DoubleToString(OrderOpenPrice(),Digits),DoubleToString(OrderStopLoss(),Digits),DoubleToString(OrderTakeProfit(),Digits),DoubleToString(OrderClosePrice(),Digits),DoubleToString(OrderProfit()+OrderSwap()+OrderCommission(),2),DoubleToString(r,3),"","","","",dur,ExitReason(OrderProfit()));FileClose(h);}
      string reason=ExitReason(OrderProfit());
      if(reason=="SL") g_slExits++; else if(reason=="TP") g_tpExits++; else g_manualOrOtherExits++;
   }
   g_lastHistoryTotal=total;
}

bool SendOrder(int type,double atr,int score){
   RefreshRates();
   double minStop=MarketInfo(_Symbol,MODE_STOPLEVEL)*Point;
   double slDist=MathMax(atr*InpSLMult,minStop+2*Point);
   double tpDist=MathMax(atr*InpTPMult,minStop+2*Point);
   double price=(type==OP_BUY?Ask:Bid);
   double sl=(type==OP_BUY?price-slDist:price+slDist);
   double tp=(type==OP_BUY?price+tpDist:price-tpDist);
   sl=NormalizeDouble(sl,Digits); tp=NormalizeDouble(tp,Digits);
   double lots=LotByRisk(slDist);
   ResetLastError();
   int ticket=OrderSend(_Symbol,type,lots,price,5,sl,tp,"AI_v1.30",InpMagicNumber,0,(type==OP_BUY?clrBlue:clrRed));
   if(ticket<0){g_orderErrors++;Print("v1.30 OrderSend error=",GetLastError()," type=",type," score=",score);return false;}
   g_lastTradeBar=iTime(_Symbol,_Period,0);
   if(type==OP_BUY) g_buyOrders++; else g_sellOrders++;
   Print("v1.30 OPEN ",(type==OP_BUY?"BUY":"SELL")," ticket=",ticket," score=",score," lots=",DoubleToString(lots,2)," ATR=",DoubleToString(atr/Point,1));
   return true;
}

void Analyze(){
   g_bars++;
   double c1=iClose(_Symbol,_Period,1);
   double atr=iATR(_Symbol,_Period,InpATRPeriod,1);
   double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
   double rsi=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,1);
   double fast=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double slow=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double macro=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double macro2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,2);
   if(atr<=0 || macro<=0) return;
   if(!MarketOK(atr) || !CooldownOK() || OpenTrades()>=InpMaxTrades) return;
   int bs=ScoreBuy(c1,fast,slow,macro,macro2,adx,rsi,atr);
   int ss=ScoreSell(c1,fast,slow,macro,macro2,adx,rsi,atr);
   bool buy=(InpAllowBuy && bs>=InpMinScore);
   bool sell=(InpAllowSell && ss>=InpMinScore);
   if(buy) g_buySignals++;
   if(sell) g_sellSignals++;
   if(InpLogEveryBar || buy || sell) Print("v1.30 BAR ",TimeToString(iTime(_Symbol,_Period,1),TIME_DATE|TIME_MINUTES)," BUY=",bs," SELL=",ss," ATR=",DoubleToString(atr/Point,1)," ADX=",DoubleToString(adx,1)," RSI=",DoubleToString(rsi,1));
   if(buy && sell){
      if(bs>ss) SendOrder(OP_BUY,atr,bs);
      else if(ss>bs) SendOrder(OP_SELL,atr,ss);
   } else if(buy) SendOrder(OP_BUY,atr,bs);
   else if(sell) SendOrder(OP_SELL,atr,ss);
}

void Manage(){
   double atr=iATR(_Symbol,_Period,InpATRPeriod,0);
   if(atr<=0) return;
   RefreshRates();
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=_Symbol || OrderMagicNumber()!=InpMagicNumber) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      double open=OrderOpenPrice();
      double price=(type==OP_BUY?Bid:Ask);
      double profitDist=(type==OP_BUY?price-open:open-price);
      double newSL=OrderStopLoss();
      bool changed=false;
      if(InpUseBreakEven && !InpLabDisableBE && profitDist>=atr*InpBEStartMult){
         double be=(type==OP_BUY?open+atr*InpBELockMult:open-atr*InpBELockMult);
         if(type==OP_BUY && (newSL<be || newSL==0)){newSL=be;changed=true;g_beMoves++;}
         if(type==OP_SELL && (newSL>be || newSL==0)){newSL=be;changed=true;g_beMoves++;}
      }
      if(InpUseTrailing && !InpLabDisableTrailing && profitDist>=atr*InpTrailStartMult){
         double tr=(type==OP_BUY?price-atr*InpTrailDistMult:price+atr*InpTrailDistMult);
         if(type==OP_BUY && tr>newSL && tr<price){newSL=tr;changed=true;g_trailMoves++;}
         if(type==OP_SELL && (newSL==0 || tr<newSL) && tr>price){newSL=tr;changed=true;g_trailMoves++;}
      }
      if(changed){
         newSL=NormalizeDouble(newSL,Digits);
         ResetLastError();
         if(!OrderModify(OrderTicket(),open,newSL,OrderTakeProfit(),0,clrNONE)) Print("v1.30 OrderModify error=",GetLastError()," ticket=",OrderTicket());
      }
   }
}

void PrintFinal(){
   AuditHistory();
   Print("===== AI TRADING BOT v1.30 MANAGEMENT LAB =====");
   Print("Bars=",g_bars," BuySignals=",g_buySignals," SellSignals=",g_sellSignals);
   Print("Orders BUY=",g_buyOrders," SELL=",g_sellOrders," OrderErrors=",g_orderErrors);
   Print("Blocks spread=",g_blockSpread," ATR=",g_blockATR," session=",g_blockSession," cooldown=",g_blockCooldown);
   Print("Management BE moves=",g_beMoves," trailing moves=",g_trailMoves);
   Print("History exits SL=",g_slExits," TP=",g_tpExits," Other=",g_manualOrOtherExits);
   Print("Balance=",DoubleToString(AccountBalance(),2)," Equity=",DoubleToString(AccountEquity(),2));
}

int OnInit(){
   WriteCSVHeader();
   Print("INIT_OK AI Trading Bot v1.30 Management Lab | Magic=",InpMagicNumber);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){PrintFinal();Comment("");}

void OnTick(){
   Manage();
   AuditHistory();
   if(NewBar()) Analyze();
}
