//+------------------------------------------------------------------+
//| MASTER1011_AdaptiveSLTP_MultiCrypto_Weekend_v1_20.mq4             |
//| Derived as a separate safety-focused variant of MASTER1011.       |
//| Crypto symbols can trade 24/7, subject to broker symbol/session.  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"
#property description "MASTER1011 Envelopes reversal, bidirectional multi-crypto, ATR SL/TP, break-even and net-profit lock."
#property description "Test on demo first. Broker symbol names and account-currency tick values must be verified."

input string InpSymbols = "BTCUSD,ETHUSD,NEARUSDT,ZECUSDT,LRCUSDT,UNIUSDT,SOLUSDT,XRPUSDT,DOGEUSDT,ADAUSDT,LTCUSDT,AVAXUSDT,LINKUSDT,DOTUSDT,BNBUSDT,TRXUSDT";
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;
input int    InpEnvelopePeriod = 20;
input double InpEnvelopeDeviationPct = 0.50;
input int    InpATRPeriod = 14;
input double InpSL_ATR = 1.8;
input double InpTP_ATR = 2.4;
input double InpTrail_ATR = 1.25;
input double InpBreakEvenAtR = 0.80;
input double InpProfitLockTriggerUSD = 1.00;
input double InpProfitLockAmountUSD = 0.50;
input double InpRiskPctReferenceCapital = 0.50; // 0.5% of reference capital per position
input double InpReferenceCapitalUSD = 500.0;
input double InpMaxAggregateRiskPct = 2.0;      // aggregate risk cap = USD 10 at USD 500
input int    InpMaxOpenPositions = 3;
input double InpMaxSpreadATRRatio = 0.12;
input int    InpSlippagePoints = 30;
input int    InpMagicNumber = 20101120;
input int    InpTimerSeconds = 5;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;
input bool   InpUseWeekendCryptoMode = true; // no weekday filter: crypto may trade on weekends
input bool   InpPrintDiagnostics = true;

string gSymbols[];
datetime gLastBarTime[];
bool gStopped = false;

//------------------------- helpers ----------------------------------
string UpperCopy(string s) { StringToUpper(s); return s; }

string TrimCopy(string s)
{
   while(StringLen(s)>0 && (StringGetCharacter(s,0)==' ' || StringGetCharacter(s,0)=='\t'))
      s=StringSubstr(s,1);
   while(StringLen(s)>0)
   {
      int n=StringLen(s)-1;
      int c=StringGetCharacter(s,n);
      if(c==' ' || c=='\t') s=StringSubstr(s,0,n); else break;
   }
   return s;
}

bool IsCryptoLike(string s)
{
   string u=UpperCopy(s);
   return (StringFind(u,"BTC")>=0 || StringFind(u,"ETH")>=0 ||
           StringFind(u,"USDT")>=0 || StringFind(u,"XRP")>=0 ||
           StringFind(u,"DOGE")>=0 || StringFind(u,"LTC")>=0 ||
           StringFind(u,"ADA")>=0 || StringFind(u,"SOL")>=0 ||
           StringFind(u,"AVAX")>=0 || StringFind(u,"BNB")>=0 ||
           StringFind(u,"DOT")>=0 || StringFind(u,"LINK")>=0 ||
           StringFind(u,"TRX")>=0);
}

// Resolve common broker suffixes/prefixes. If ambiguous, prefer exact then first containing match.
string ResolveSymbol(string requested)
{
   requested=TrimCopy(requested);
   if(StringLen(requested)==0) return "";
   if(SymbolSelect(requested,true)) return requested;
   string wanted=UpperCopy(requested);
   int total=SymbolsTotal(false);
   string match="";
   for(int i=0;i<total;i++)
   {
      string candidate=SymbolName(i,false);
      string u=UpperCopy(candidate);
      if(u==wanted) { SymbolSelect(candidate,true); return candidate; }
      if(StringFind(u,wanted)>=0)
      {
         if(match=="") match=candidate;
         else
         {
            // More than one fuzzy match is ambiguous; fail closed.
            Print("Ambiguous broker symbol for ",requested,": ",match," and ",candidate,
                  ". Add the exact broker symbol to InpSymbols.");
            return "";
         }
      }
   }
   if(match!="") { SymbolSelect(match,true); return match; }
   Print("Symbol not found in broker Market Watch: ",requested);
   return "";
}

int SymIndex(string sym)
{
   for(int i=0;i<ArraySize(gSymbols);i++) if(gSymbols[i]==sym) return i;
   return -1;
}

double SymPoint(string s) { return MarketInfo(s,MODE_POINT); }
int SymDigits(string s) { return (int)MarketInfo(s,MODE_DIGITS); }
double NormalizePrice(string s,double p) { return NormalizeDouble(p,SymDigits(s)); }

double ATRValue(string s,int shift)
{
   return iATR(s,InpTimeframe,InpATRPeriod,shift);
}

bool GetEnvelope(string s,double &upper,double &lower,double &atr)
{
   if(iBars(s,InpTimeframe)<InpEnvelopePeriod+InpATRPeriod+5) return false;
   // Closed candles only: avoid using a moving current-bar average as a signal.
   double ma=iMA(s,InpTimeframe,InpEnvelopePeriod,0,MODE_SMA,PRICE_CLOSE,1);
   atr=ATRValue(s,1);
   if(ma<=0 || atr<=0) return false;
   upper=ma*(1.0+InpEnvelopeDeviationPct/100.0);
   lower=ma*(1.0-InpEnvelopeDeviationPct/100.0);
   return (upper>lower);
}

double MoneyRiskAtStop(string s,double lots,double openPrice,double stopPrice)
{
   double tickSize=MarketInfo(s,MODE_TICKSIZE);
   double tickValue=MarketInfo(s,MODE_TICKVALUE);
   if(tickSize<=0 || tickValue<=0 || lots<=0) return -1;
   return MathAbs(openPrice-stopPrice)/tickSize*tickValue*lots;
}

double LotsForRisk(string s,double stopDistance)
{
   double tickSize=MarketInfo(s,MODE_TICKSIZE);
   double tickValue=MarketInfo(s,MODE_TICKVALUE);
   double minLot=MarketInfo(s,MODE_MINLOT);
   double maxLot=MarketInfo(s,MODE_MAXLOT);
   double step=MarketInfo(s,MODE_LOTSTEP);
   if(tickSize<=0 || tickValue<=0 || minLot<=0 || maxLot<minLot || step<=0 || stopDistance<=0)
      return 0;
   double riskCash=InpReferenceCapitalUSD*InpRiskPctReferenceCapital/100.0;
   double riskPerLot=stopDistance/tickSize*tickValue;
   if(riskCash<=0 || riskPerLot<=0) return 0;
   double lots=MathFloor((riskCash/riskPerLot)/step+1e-9)*step;
   lots=NormalizeDouble(lots,2);
   // Fail closed: never force broker minimum lot if it breaches the budget.
   if(lots<minLot) return 0;
   if(lots>maxLot) lots=MathFloor(maxLot/step)*step;
   if(MoneyRiskAtStop(s,lots,MarketInfo(s,MODE_ASK),MarketInfo(s,MODE_ASK)-stopDistance)>riskCash*1.02)
      return 0;
   return lots;
}

bool IsMarketOrderType(int t) { return (t==OP_BUY || t==OP_SELL); }

int CountOurPositions()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==InpMagicNumber && IsMarketOrderType(OrderType()))
         count++;
   return count;
}

bool HasOurOrderOnSymbol(string s)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==InpMagicNumber && OrderSymbol()==s)
         return true; // includes pending orders: no duplicate entry while any order exists
   return false;
}

double AggregateOpenRisk()
{
   double total=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || OrderMagicNumber()!=InpMagicNumber) continue;
      if(!IsMarketOrderType(OrderType())) continue;
      string s=OrderSymbol();
      if(OrderStopLoss()<=0)
      {
         // Unknown protection consumes the whole budget and blocks additional entries.
         return InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0;
      }
      double risk=MoneyRiskAtStop(s,OrderLots(),OrderOpenPrice(),OrderStopLoss());
      if(risk<0) return InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0;
      total+=risk;
   }
   return total;
}

bool EnsureProtection(int ticket,string s)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET)) return false;
   if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) return false;
   if(OrderStopLoss()>0 && OrderTakeProfit()>0) return true;
   double atr=ATRValue(s,1);
   if(atr<=0) return false;
   double minDist=(MarketInfo(s,MODE_STOPLEVEL)+2)*SymPoint(s);
   double slDist=MathMax(atr*InpSL_ATR,minDist);
   double tpDist=MathMax(atr*InpTP_ATR,minDist);
   bool buy=(OrderType()==OP_BUY);
   // Preserve any protection already installed; never widen an existing stop.
   double sl=OrderStopLoss();
   double tp=OrderTakeProfit();
   if(sl<=0) sl=NormalizePrice(s,buy?OrderOpenPrice()-slDist:OrderOpenPrice()+slDist);
   if(tp<=0) tp=NormalizePrice(s,buy?OrderOpenPrice()+tpDist:OrderOpenPrice()-tpDist);
   RefreshRates();
   ResetLastError();
   bool ok=OrderModify(ticket,OrderOpenPrice(),sl,tp,0,clrNONE);
   if(!ok) Print("PROTECTION ERROR ticket=",ticket," symbol=",s," err=",GetLastError());
   if(!OrderSelect(ticket,SELECT_BY_TICKET)) return false;
   if(OrderStopLoss()<=0 || OrderTakeProfit()<=0)
   {
      Print("CRITICAL: SL/TP not confirmed ticket=",ticket," symbol=",s,
            ". Attempting emergency close; inspect MT4 if close fails.");
      RefreshRates();
      double closePrice=(OrderType()==OP_BUY)?MarketInfo(s,MODE_BID):MarketInfo(s,MODE_ASK);
      ResetLastError();
      if(closePrice>0 && !OrderClose(ticket,OrderLots(),NormalizePrice(s,closePrice),InpSlippagePoints,clrOrangeRed))
         Print("EMERGENCY CLOSE FAILED ticket=",ticket," symbol=",s," err=",GetLastError());
      return false;
   }
   return true;
}

void ManageOpenPositions()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || OrderMagicNumber()!=InpMagicNumber) continue;
      if(!IsMarketOrderType(OrderType())) continue;
      string s=OrderSymbol();
      int type=OrderType();
      if(!EnsureProtection(OrderTicket(),s)) continue;
      if(!OrderSelect(OrderTicket(),SELECT_BY_TICKET)) continue;

      double atr=ATRValue(s,1);
      double point=SymPoint(s);
      if(atr<=0 || point<=0) continue;
      double tickSize=MarketInfo(s,MODE_TICKSIZE);
      double tickValue=MarketInfo(s,MODE_TICKVALUE);
      if(tickSize<=0 || tickValue<=0) continue;
      double bid=MarketInfo(s,MODE_BID), ask=MarketInfo(s,MODE_ASK);
      if(bid<=0 || ask<=0) continue;

      double riskDist=MathAbs(OrderOpenPrice()-OrderStopLoss());
      double favorable=(type==OP_BUY)?bid-OrderOpenPrice():OrderOpenPrice()-ask;
      double r=(riskDist>0)?favorable/riskDist:0;
      double newSL=OrderStopLoss();
      bool change=false;

      // Break-even and net-profit lock. Money conversion is approximate if account currency is not USD.
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      if(net>=InpProfitLockTriggerUSD)
      {
         double moneyNeeded=MathMax(0.0,InpProfitLockAmountUSD-OrderSwap()-OrderCommission());
         double priceDelta=moneyNeeded/(tickValue*OrderLots())*tickSize;
         double lockSL=(type==OP_BUY)?OrderOpenPrice()+priceDelta:OrderOpenPrice()-priceDelta;
         if(type==OP_BUY && lockSL<bid-(MarketInfo(s,MODE_STOPLEVEL)+2)*point && lockSL>newSL)
            { newSL=lockSL; change=true; }
         if(type==OP_SELL && lockSL>ask+(MarketInfo(s,MODE_STOPLEVEL)+2)*point && (newSL<=0 || lockSL<newSL))
            { newSL=lockSL; change=true; }
      }
      else if(r>=InpBreakEvenAtR)
      {
         double be=OrderOpenPrice();
         if(type==OP_BUY && be<bid-(MarketInfo(s,MODE_STOPLEVEL)+2)*point && be>newSL)
            { newSL=be; change=true; }
         if(type==OP_SELL && be>ask+(MarketInfo(s,MODE_STOPLEVEL)+2)*point && (newSL<=0 || be<newSL))
            { newSL=be; change=true; }
      }

      // ATR trailing only tightens the stop; never widens risk.
      double trail=(type==OP_BUY)?bid-atr*InpTrail_ATR:ask+atr*InpTrail_ATR;
      double minGap=(MarketInfo(s,MODE_STOPLEVEL)+2)*point;
      if(type==OP_BUY)
      {
         trail=MathMin(trail,bid-minGap);
         if(trail>newSL+point && trail>OrderOpenPrice()) { newSL=trail; change=true; }
      }
      else
      {
         trail=MathMax(trail,ask+minGap);
         if((newSL<=0 || trail<newSL-point) && trail<OrderOpenPrice()) { newSL=trail; change=true; }
      }
      if(change)
      {
         newSL=NormalizePrice(s,newSL);
         ResetLastError();
         if(!OrderModify(OrderTicket(),OrderOpenPrice(),newSL,OrderTakeProfit(),0,clrNONE))
            Print("Trailing/lock modify failed ticket=",OrderTicket()," symbol=",s," err=",GetLastError());
      }
   }
}

bool OpenPosition(string s,int type,double atr)
{
   if(!IsTradeAllowed() || IsTradeContextBusy()) return false;
   if(CountOurPositions()>=InpMaxOpenPositions) return false;
   double maxRisk=InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0;
   double currentRisk=AggregateOpenRisk();
   if(currentRisk>=maxRisk) return false;

   double point=SymPoint(s);
   double bid=MarketInfo(s,MODE_BID), ask=MarketInfo(s,MODE_ASK);
   double tickSize=MarketInfo(s,MODE_TICKSIZE), tickValue=MarketInfo(s,MODE_TICKVALUE);
   if(point<=0 || bid<=0 || ask<=0 || tickSize<=0 || tickValue<=0 || atr<=0) return false;
   if(ask-bid > atr*InpMaxSpreadATRRatio)
   {
      if(InpPrintDiagnostics) Print("ENTRY BLOCKED: spread/ATR too high ",s);
      return false;
   }
   double minDist=(MarketInfo(s,MODE_STOPLEVEL)+2)*point;
   double slDist=MathMax(atr*InpSL_ATR,minDist);
   double tpDist=MathMax(atr*InpTP_ATR,minDist);
   double entry=(type==OP_BUY)?ask:bid;
   double sl=NormalizePrice(s,(type==OP_BUY)?entry-slDist:entry+slDist);
   double tp=NormalizePrice(s,(type==OP_BUY)?entry+tpDist:entry-tpDist);
   double lots=LotsForRisk(s,slDist);
   if(lots<=0)
   {
      if(InpPrintDiagnostics) Print("ENTRY BLOCKED: minimum lot exceeds risk budget or tick metadata invalid: ",s);
      return false;
   }
   double risk=MoneyRiskAtStop(s,lots,entry,sl);
   if(risk<=0 || currentRisk+risk>maxRisk+0.01) return false;
   if(AccountFreeMarginCheck(s,type,lots)<=0) { ResetLastError(); return false; }

   ResetLastError();
   int ticket=OrderSend(s,type,lots,NormalizePrice(s,entry),InpSlippagePoints,sl,tp,
                        "MASTER1011 adaptive multi-crypto",InpMagicNumber,0,(type==OP_BUY)?clrDodgerBlue:clrTomato);
   if(ticket<0)
   {
      Print("OrderSend failed symbol=",s," type=",type," err=",GetLastError());
      return false;
   }
   // Verify actual server-side protection immediately.
   if(!EnsureProtection(ticket,s))
   {
      Print("WARNING: ticket ",ticket," opened without confirmed SL/TP. Inspect MT4 immediately.");
      return false;
   }
   Print("OPEN ",(type==OP_BUY?"BUY":"SELL")," ",s," lots=",DoubleToString(lots,2),
         " risk_est=",DoubleToString(risk,2)," SL=",DoubleToString(sl,SymDigits(s)),
         " TP=",DoubleToString(tp,SymDigits(s)));
   return true;
}

void ScanSymbol(int idx)
{
   string s=gSymbols[idx];
   if(s=="") return;
   if(!MarketInfo(s,MODE_TRADEALLOWED)) return;
   if(HasOurOrderOnSymbol(s)) return;
   datetime bar=iTime(s,InpTimeframe,0);
   if(bar<=0) return;
   // Re-check during the whole bar so a band touch is not missed between bar opens.
   gLastBarTime[idx]=bar;
   if(InpUseWeekendCryptoMode && !IsCryptoLike(s)) return;
   double upper,lower,atr;
   if(!GetEnvelope(s,upper,lower,atr)) return;
   double bid=MarketInfo(s,MODE_BID), ask=MarketInfo(s,MODE_ASK);
   if(bid<=0 || ask<=0) return;

   // Mean-reversion entry, preserving MASTER1011's two-way concept.
   // Only trade when current market price reaches a band; no simultaneous hedge on the same symbol.
   if(InpAllowBuy && ask<=lower)
      OpenPosition(s,OP_BUY,atr);
   else if(InpAllowSell && bid>=upper)
      OpenPosition(s,OP_SELL,atr);
}

int OnInit()
{
   if(InpEnvelopePeriod<2 || InpATRPeriod<2 || InpSL_ATR<=0 || InpTP_ATR<=0 ||
      InpRiskPctReferenceCapital<=0 || InpReferenceCapitalUSD<=0 ||
      InpMaxAggregateRiskPct<=0 || InpMaxOpenPositions<1 || InpTimerSeconds<1)
      return INIT_PARAMETERS_INCORRECT;
   int n=StringSplit(InpSymbols,',',gSymbols);
   if(n<=0) { Print("InpSymbols is empty."); return INIT_PARAMETERS_INCORRECT; }
   ArrayResize(gLastBarTime,n);
   for(int i=0;i<n;i++)
   {
      string requested=TrimCopy(gSymbols[i]);
      gSymbols[i]=ResolveSymbol(requested);
      gLastBarTime[i]=0;
      if(gSymbols[i]=="") Print("Configured symbol unresolved: ",requested);
   }
   EventSetTimer(InpTimerSeconds);
   Print("MASTER1011 adaptive multi-crypto v1.20 initialized. Reference capital USD ",
         DoubleToString(InpReferenceCapitalUSD,2),"; max aggregate estimated risk USD ",
         DoubleToString(InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0,2),
         ". Weekend trading is broker/symbol dependent.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTimer()
{
   if(gStopped) return;
   ManageOpenPositions();
   for(int i=0;i<ArraySize(gSymbols);i++) ScanSymbol(i);
}

void OnTick()
{
   // Also manage risk when the timer is delayed; OnTimer performs multi-symbol scanning.
   if(!gStopped) ManageOpenPositions();
}
//+------------------------------------------------------------------+
