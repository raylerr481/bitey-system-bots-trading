#property strict
#property version   "1.995"
#property description "Bitey SBT Multi-Asset v1.99.5 - evidence diagnostics and HTF lookahead fix; research candidate"

enum EngineMode { OBSERVE_ONLY=0, AUTO_EXECUTION=1 };
input EngineMode InpMode = AUTO_EXECUTION; // Auto-entry enabled; MT4 terminal and broker permissions plus every code risk/evidence gate still apply.
input int InpMagic = 10102027;
input double InpOperatingCapitalUSD = 500.0;
input double InpRiskPerTradeUSD = 1.25;
input double InpHardRiskCapUSD = 1.25;
input double InpPortfolioRiskCapUSD = 8.75;
input double InpDailyLossLimitUSD = 10.0;
input int InpMaxOpenTrades = 7;
input int InpMaxPositionsPerAsset = 1;
input int InpMaxQuoteAgeSeconds = 120;
input int InpScanIntervalSeconds = 30;
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1;
input int InpATRPeriod = 14;
input double InpStopATR = 1.5;
input double InpTargetATR = 2.0;
input bool InpEnableAdaptiveManagement = true;
input double InpBreakEvenTriggerATR = 1.0;
input double InpTrailStartATR = 1.5;
input double InpTrailDistanceATR = 1.2;
input double InpExtendTargetTriggerFraction = 0.80;
input double InpMaxTargetDistanceATR = 4.0;
input double InpStrongTrendADX = 22.0;
input int InpTrainBars = 120;
input int InpHoldoutBars = 30;
input int InpHorizonBars = 3;
input int InpMinTrainN = 12;
input double InpMinTrainWR = 0.42;
input double InpMinTrainAvgR = 0.02;
input int InpMinHoldoutN = 6;
input double InpMinHoldoutWR = 0.40;
input double InpMinHoldoutAvgR = 0.00;
input int InpMinModelVotes = 5;
input int InpMaxSpreadPoints = 100;
input int InpSlippagePoints = 10;
input bool InpRequireUSDAccount = true;
input bool InpPrintDiagnostics = true;

datetime g_lastScan = 0;
datetime g_lastBar = 0;
string g_lastReason = "INITIALIZING";

double EffectiveCapital()
{
   if(InpRequireUSDAccount && AccountCurrency()!="USD") return 0.0;
   return MathMin(500.0, MathMax(0.0, InpOperatingCapitalUSD));
}

double DailyNetUSD()
{
   datetime now=TimeCurrent();
   string day=TimeToString(now,TIME_DATE);
   double total=0.0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()<=0 || TimeToString(OrderCloseTime(),TIME_DATE)!=day) continue;
      total+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      total+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return total;
}

double PositionRiskUSD()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || OrderMagicNumber()!=InpMagic) continue;
      if(OrderStopLoss()<=0) return 1.0e9;
      double tickValue=MarketInfo(OrderSymbol(),MODE_TICKVALUE);
      double tickSize=MarketInfo(OrderSymbol(),MODE_TICKSIZE);
      if(tickValue<=0 || tickSize<=0) return 1.0e9;
      total+=MathAbs(OrderOpenPrice()-OrderStopLoss())/tickSize*tickValue*OrderLots();
   }
   return total;
}

int CountOpen()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==InpMagic) n++;
   return n;
}

bool HasAssetPosition(string symbol)
{
   string key=Canonical(symbol);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || OrderMagicNumber()!=InpMagic) continue;
      if(Canonical(OrderSymbol())==key) return true;
   }
   return false;
}

string Canonical(string s)
{
   // Remove recognized broker suffixes BEFORE deleting punctuation.
   // This preserves equivalence for symbols such as SOLUSDT and SOLUSDT.m.
   StringToUpper(s);
   string suffixes[]={".PRO",".RAW",".ECN",".HB",".M","_M",".P","_P"};
   int n=StringLen(s);
   for(int j=0;j<ArraySize(suffixes);j++)
   {
      int suffixLen=StringLen(suffixes[j]);
      if(n>suffixLen && StringSubstr(s,n-suffixLen)==suffixes[j])
      {
         s=StringSubstr(s,0,n-suffixLen);
         break;
      }
   }
   string out="";
   for(int i=0;i<StringLen(s);i++)
   {
      int c=StringGetCharacter(s,i);
      if((c>=65&&c<=90)||(c>=48&&c<=57))
         out+=StringFormat("%c",c);
   }
   return out;
}

int ModelVotes(string symbol,int shift,int &direction)
{
   double c=iClose(symbol,InpTimeframe,shift);
   double o=iOpen(symbol,InpTimeframe,shift);
   double emaFast=iMA(symbol,InpTimeframe,9,0,MODE_EMA,PRICE_CLOSE,shift);
   double emaSlow=iMA(symbol,InpTimeframe,21,0,MODE_EMA,PRICE_CLOSE,shift);
   double emaTrend=iMA(symbol,InpTimeframe,50,0,MODE_EMA,PRICE_CLOSE,shift);
   double rsi=iRSI(symbol,InpTimeframe,14,PRICE_CLOSE,shift);
   double adx=iADX(symbol,InpTimeframe,14,PRICE_CLOSE,MODE_MAIN,shift);
   double plus=iADX(symbol,InpTimeframe,14,PRICE_CLOSE,MODE_PLUSDI,shift);
   double minus=iADX(symbol,InpTimeframe,14,PRICE_CLOSE,MODE_MINUSDI,shift);
   double upper=iBands(symbol,InpTimeframe,20,2.0,0,PRICE_CLOSE,MODE_UPPER,shift);
   double lower=iBands(symbol,InpTimeframe,20,2.0,0,PRICE_CLOSE,MODE_LOWER,shift);
   double macd=iMACD(symbol,InpTimeframe,12,26,9,PRICE_CLOSE,MODE_MAIN,shift);
   double signal=iMACD(symbol,InpTimeframe,12,26,9,PRICE_CLOSE,MODE_SIGNAL,shift);
   double atr=iATR(symbol,InpTimeframe,InpATRPeriod,shift);
   double priorHigh=iHigh(symbol,InpTimeframe,iHighest(symbol,InpTimeframe,MODE_HIGH,20,shift+1));
   double priorLow=iLow(symbol,InpTimeframe,iLowest(symbol,InpTimeframe,MODE_LOW,20,shift+1));
   int buy=0,sell=0;
   // 16 distinct rule families; all read closed candles only.
   if(emaFast>emaSlow&&emaSlow>emaTrend)buy++; else if(emaFast<emaSlow&&emaSlow<emaTrend)sell++; // trend
   if(c>o&&c>emaFast)buy++; else if(c<o&&c<emaFast)sell++; // momentum
   if(c>priorHigh)buy++; else if(c<priorLow)sell++; // Donchian
   if(rsi<30)buy++; else if(rsi>70)sell++; // mean reversion
   if(adx<18&&rsi<35)buy++; else if(adx<18&&rsi>65)sell++; // strict range
   if(atr>iATR(symbol,InpTimeframe,InpATRPeriod,shift+1)&&c>priorHigh)buy++; else if(atr>iATR(symbol,InpTimeframe,InpATRPeriod,shift+1)&&c<priorLow)sell++; // ATR breakout
   if(TimeHour(iTime(symbol,InpTimeframe,shift))>=7&&TimeHour(iTime(symbol,InpTimeframe,shift))<=16){if(c>o)buy++;else if(c<o)sell++;} // session
   if(rsi>50&&rsi<68&&c>emaFast)buy++; else if(rsi<50&&rsi>32&&c<emaFast)sell++; // RSI divergence proxy
   int h4Shift=iBarShift(symbol,PERIOD_H4,iTime(symbol,InpTimeframe,shift),false);
   double h4Closed=(h4Shift>=0?iClose(symbol,PERIOD_H4,h4Shift+1):0);
   if(h4Closed>0 && c>h4Closed && emaFast>emaSlow)buy++;
   else if(h4Closed>0 && c<h4Closed && emaFast<emaSlow)sell++; // HTF aligned to last H4 candle closed before this historical H1 bar
   double mid=(upper+lower)/2.0;
   if(c<lower)buy++; else if(c>upper)sell++; // VWAP/deviation proxy
   if(c>priorHigh&&iClose(symbol,InpTimeframe,shift+1)<=priorHigh)buy++; else if(c<priorLow&&iClose(symbol,InpTimeframe,shift+1)>=priorLow)sell++; // break/retest proxy
   double fibMid=iLow(symbol,InpTimeframe,shift)+0.618*(iHigh(symbol,InpTimeframe,shift)-iLow(symbol,InpTimeframe,shift));
   if(c>fibMid&&emaFast>emaSlow)buy++; else if(c<fibMid&&emaFast<emaSlow)sell++; // fib pullback proxy
   if((upper-lower)>2.0*atr&&c>mid)buy++; else if((upper-lower)>2.0*atr&&c<mid)sell++; // volatility expansion
   double lr0=iClose(symbol,InpTimeframe,shift+5),lr1=iClose(symbol,InpTimeframe,shift);
   if(lr1>lr0)buy++; else if(lr1<lr0)sell++; // linear regression direction proxy
   if(macd>signal)buy++; else if(macd<signal)sell++; // MACD
   if(c>upper)buy++; else if(c<lower)sell++; // Bollinger expansion
   direction=(buy>=sell?1:-1);
   return MathMax(buy,sell);
}

bool EvaluateEvidence(string symbol,int direction,double &trainWR,double &trainAvgR,int &trainN,double &holdWR,double &holdAvgR,int &holdN)
{
   trainWR=0;trainAvgR=0;trainN=0;holdWR=0;holdAvgR=0;holdN=0;
   int bars=iBars(symbol,InpTimeframe);
   int horizon=MathMax(1,InpHorizonBars);
   int maxShift=MathMin(bars-horizon-2,InpTrainBars+InpHoldoutBars);
   if(maxShift<horizon+InpMinTrainN+InpMinHoldoutN) return false;
   double trainSum=0,holdSum=0;int trainWins=0,holdWins=0;
   double spread=MarketInfo(symbol,MODE_SPREAD)*MarketInfo(symbol,MODE_POINT);
   for(int shift=maxShift;shift>horizon;shift--)
   {
      int dir=0;
      int votes=ModelVotes(symbol,shift,dir);
      if(votes<InpMinModelVotes || dir!=direction) continue;
      double entry=iClose(symbol,InpTimeframe,shift);
      double exit=iClose(symbol,InpTimeframe,shift-horizon);
      double atr=iATR(symbol,InpTimeframe,InpATRPeriod,shift);
      if(entry<=0||exit<=0||atr<=0)continue;
      double r=direction*(exit-entry)/(1.5*atr)-spread/(1.5*atr);
      if(shift<=InpHoldoutBars+horizon)
      {
         holdN++;holdSum+=r;if(r>0)holdWins++;
      }
      else if(shift<=InpHoldoutBars+InpTrainBars+horizon)
      {
         trainN++;trainSum+=r;if(r>0)trainWins++;
      }
   }
   if(trainN>0){trainWR=(double)trainWins/trainN;trainAvgR=trainSum/trainN;}
   if(holdN>0){holdWR=(double)holdWins/holdN;holdAvgR=holdSum/holdN;}
   return trainN>=InpMinTrainN && trainWR>=InpMinTrainWR && trainAvgR>InpMinTrainAvgR &&
          holdN>=InpMinHoldoutN && holdWR>=InpMinHoldoutWR && holdAvgR>InpMinHoldoutAvgR;
}


string EvidenceFailureReason(int trainN,double trainWR,double trainAvgR,int holdN,double holdWR,double holdAvgR)
{
   if(trainN<InpMinTrainN) return "TRAIN_SAMPLE_INSUFFICIENT";
   if(trainWR<InpMinTrainWR) return "TRAIN_WINRATE_BELOW_MIN";
   if(trainAvgR<=InpMinTrainAvgR) return "TRAIN_EXPECTANCY_BELOW_MIN";
   if(holdN<InpMinHoldoutN) return "HOLDOUT_SAMPLE_INSUFFICIENT";
   if(holdWR<InpMinHoldoutWR) return "HOLDOUT_WINRATE_BELOW_MIN";
   if(holdAvgR<=InpMinHoldoutAvgR) return "HOLDOUT_EXPECTANCY_NOT_POSITIVE";
   return "EVIDENCE_PASS";
}

double LotForRisk(string symbol,double stopDistance,double riskUSD)
{
   double tickValue=MarketInfo(symbol,MODE_TICKVALUE);
   double tickSize=MarketInfo(symbol,MODE_TICKSIZE);
   double minLot=MarketInfo(symbol,MODE_MINLOT),maxLot=MarketInfo(symbol,MODE_MAXLOT),step=MarketInfo(symbol,MODE_LOTSTEP);
   if(tickValue<=0||tickSize<=0||stopDistance<=0||step<=0)return 0;
   double perLot=stopDistance/tickSize*tickValue;
   if(perLot<=0)return 0;
   double lots=MathFloor((riskUSD/perLot)/step)*step;
   lots=NormalizeDouble(lots,2);
   if(lots<minLot||lots>maxLot)return 0; // Never round a too-large minimum lot up beyond the risk cap.
   return lots;
}

bool FreshQuote(string symbol)
{
   if(!SymbolSelect(symbol,true))return false;
   datetime t=(datetime)MarketInfo(symbol,MODE_TIME);
   return t>0 && TimeCurrent()-t<=InpMaxQuoteAgeSeconds &&
          MarketInfo(symbol,MODE_BID)>0 && MarketInfo(symbol,MODE_ASK)>0;
}

void LogDecision(string symbol,string decision,string reason,int direction,int votes,double trainWR,double trainR,int trainN,double holdWR,double holdR,int holdN)
{
   if(!InpPrintDiagnostics)return;
   Print("BITEY_SBT_1.99.5 | symbol=",symbol," decision=",decision," reason=",reason,
         " direction=",direction," votes=",votes,
         " trainN=",trainN," trainWR=",DoubleToString(trainWR,3)," trainAvgR=",DoubleToString(trainR,3),
         " holdoutN=",holdN," holdoutWR=",DoubleToString(holdWR,3)," holdoutAvgR=",DoubleToString(holdR,3),
         " dailyNetUSD=",DoubleToString(DailyNetUSD(),2)," openRiskUSD=",DoubleToString(PositionRiskUSD(),2),
         " mode=",(InpMode==OBSERVE_ONLY?"OBSERVE_ONLY":"AUTO_EXECUTION"));
}

void ScanSymbol(string symbol)
{
   if(!FreshQuote(symbol)){LogDecision(symbol,"REJECT","STALE_OR_INVALID_QUOTE",0,0,0,0,0,0,0,0);return;}
   if(MarketInfo(symbol,MODE_TRADEALLOWED)==0){LogDecision(symbol,"REJECT","TRADING_DISABLED",0,0,0,0,0,0,0,0);return;}
   if(MarketInfo(symbol,MODE_SPREAD)>InpMaxSpreadPoints){LogDecision(symbol,"REJECT","SPREAD_LIMIT",0,0,0,0,0,0,0,0);return;}
   if(iBars(symbol,InpTimeframe)<InpTrainBars+InpHoldoutBars+InpHorizonBars+100){LogDecision(symbol,"REJECT","INSUFFICIENT_HISTORY",0,0,0,0,0,0,0,0);return;}
   datetime bar=iTime(symbol,InpTimeframe,1);
   if(bar<=0){LogDecision(symbol,"REJECT","NO_CLOSED_BAR",0,0,0,0,0,0,0,0);return;}
   int direction=0,votes=ModelVotes(symbol,1,direction);
   double tw=0,tr=0,hw=0,hr=0;int tn=0,hn=0;
   bool pass=EvaluateEvidence(symbol,direction,tw,tr,tn,hw,hr,hn);
   if(!pass){LogDecision(symbol,"REJECT",EvidenceFailureReason(tn,tw,tr,hn,hw,hr),direction,votes,tw,tr,tn,hw,hr,hn);return;}
   if(votes<InpMinModelVotes){LogDecision(symbol,"REJECT","MODEL_CONSENSUS",direction,votes,tw,tr,tn,hw,hr,hn);return;}
   if(HasAssetPosition(symbol)){LogDecision(symbol,"SKIP","ONE_POSITION_PER_CANONICAL_ASSET",direction,votes,tw,tr,tn,hw,hr,hn);return;}
   if(CountOpen()>=MathMin(7,InpMaxOpenTrades)){LogDecision(symbol,"REJECT","MAX_OPEN_POSITIONS",direction,votes,tw,tr,tn,hw,hr,hn);return;}
   double dayNet=DailyNetUSD();
   if(dayNet<=-MathMin(10.0,MathAbs(InpDailyLossLimitUSD))){LogDecision(symbol,"REJECT","DAILY_LOSS_LIMIT",direction,votes,tw,tr,tn,hw,hr,hn);return;}
   double riskCap=MathMin(1.25,MathMin(InpHardRiskCapUSD,MathMin(InpRiskPerTradeUSD,EffectiveCapital()*0.0025)));
   double openRisk=PositionRiskUSD();
   if(riskCap<=0||openRisk+riskCap>MathMin(8.75,InpPortfolioRiskCapUSD)){LogDecision(symbol,"REJECT","PORTFOLIO_RISK_CAP",direction,votes,tw,tr,tn,hw,hr,hn);return;}
   double atr=iATR(symbol,InpTimeframe,InpATRPeriod,1);
   double point=MarketInfo(symbol,MODE_POINT);
    int digits=(int)MarketInfo(symbol,MODE_DIGITS);
   if(atr<=0||point<=0){LogDecision(symbol,"REJECT","INVALID_ATR_OR_POINT",direction,votes,tw,tr,tn,hw,hr,hn);return;}
   double stopDist=MathMax(atr*InpStopATR,MarketInfo(symbol,MODE_STOPLEVEL)*point);
   double lots=LotForRisk(symbol,stopDist,riskCap);
   if(lots<=0){LogDecision(symbol,"REJECT","LOT_CANNOT_RESPECT_RISK_CAP",direction,votes,tw,tr,tn,hw,hr,hn);return;}
   double price=(direction>0?MarketInfo(symbol,MODE_ASK):MarketInfo(symbol,MODE_BID));
   double sl=NormalizeDouble(price-direction*stopDist,digits);
   double tp=NormalizeDouble(price+direction*atr*InpTargetATR,digits);
   if(InpMode==OBSERVE_ONLY){LogDecision(symbol,"OBSERVE","QUALIFIED_NOT_SENT",direction,votes,tw,tr,tn,hw,hr,hn);return;}
   if(!IsTradeAllowed()){LogDecision(symbol,"REJECT","TERMINAL_TRADE_PERMISSION_OFF",direction,votes,tw,tr,tn,hw,hr,hn);return;}
   int type=(direction>0?OP_BUY:OP_SELL);
   ResetLastError();
   int ticket=OrderSend(symbol,type,lots,price,InpSlippagePoints,sl,tp,"BiteySBT 1.99.5",InpMagic,0,clrNONE);
   if(ticket<0){int err=GetLastError();LogDecision(symbol,"REJECT",StringFormat("ORDERSEND_ERROR_%d",err),direction,votes,tw,tr,tn,hw,hr,hn);return;}
   LogDecision(symbol,"OPENED",StringFormat("TICKET_%d",ticket),direction,votes,tw,tr,tn,hw,hr,hn);
}


bool TrendStillSupportsTrade(string symbol,int type)
{
   double adx=iADX(symbol,InpTimeframe,14,PRICE_CLOSE,MODE_MAIN,1);
   double fast=iMA(symbol,InpTimeframe,9,0,MODE_EMA,PRICE_CLOSE,1);
   double slow=iMA(symbol,InpTimeframe,21,0,MODE_EMA,PRICE_CLOSE,1);
   double close1=iClose(symbol,InpTimeframe,1);
   if(adx<InpStrongTrendADX || fast<=0 || slow<=0 || close1<=0) return false;
   if(type==OP_BUY) return (fast>slow && close1>fast);
   if(type==OP_SELL) return (fast<slow && close1<fast);
   return false;
}

void ManageAdaptiveStopsAndTargets()
{
   if(!InpEnableAdaptiveManagement) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue; // Never modify pending orders or manual trades.
      string symbol=OrderSymbol();
      double point=MarketInfo(symbol,MODE_POINT);
      int digits=(int)MarketInfo(symbol,MODE_DIGITS);
      double atr=iATR(symbol,InpTimeframe,InpATRPeriod,1);
      double tickValue=MarketInfo(symbol,MODE_TICKVALUE);
      double tickSize=MarketInfo(symbol,MODE_TICKSIZE);
      if(point<=0 || atr<=0 || tickValue<=0 || tickSize<=0) continue;
      double bid=MarketInfo(symbol,MODE_BID), ask=MarketInfo(symbol,MODE_ASK);
      if(bid<=0 || ask<=0) continue;
      double market=(type==OP_BUY?bid:ask);
      double favorable=(type==OP_BUY?market-OrderOpenPrice():OrderOpenPrice()-market);
      if(favorable<=0) continue;
      double stopLevel=MarketInfo(symbol,MODE_STOPLEVEL)*point;
      double freezeLevel=MarketInfo(symbol,MODE_FREEZELEVEL)*point;
      double minDistance=MathMax(stopLevel,freezeLevel)+point;
      double desiredSL=OrderStopLoss();
      double desiredTP=OrderTakeProfit();
      bool changeSL=false,changeTP=false;
      string reason="";

      // Break-even after favorable movement; the SL is only tightened, never loosened.
      if(favorable>=atr*InpBreakEvenTriggerATR)
      {
         double be=OrderOpenPrice();
         if(type==OP_BUY) be+=point;
         else be-=point;
         if(type==OP_BUY && (desiredSL<=0 || be>desiredSL+point) && market-be>=minDistance)
         { desiredSL=be; changeSL=true; reason="BREAK_EVEN"; }
         if(type==OP_SELL && (desiredSL<=0 || be<desiredSL-point) && be-market>=minDistance)
         { desiredSL=be; changeSL=true; reason="BREAK_EVEN"; }
      }

      // ATR trailing after a larger favorable move; do not widen the stop or violate broker distance.
      if(favorable>=atr*InpTrailStartATR)
      {
         double trail=(type==OP_BUY?market-atr*InpTrailDistanceATR:market+atr*InpTrailDistanceATR);
         if(type==OP_BUY)
         {
            trail=MathMin(trail,bid-minDistance);
            if((desiredSL<=0 || trail>desiredSL+point) && trail<OrderOpenPrice()+favorable && trail>0)
            { desiredSL=trail; changeSL=true; reason="ATR_TRAIL"; }
         }
         else
         {
            trail=MathMax(trail,ask+minDistance);
            if((desiredSL<=0 || trail<desiredSL-point) && trail>ask && trail>0)
            { desiredSL=trail; changeSL=true; reason="ATR_TRAIL"; }
         }
      }

      // Extend TP only near the current target and only while closed-bar trend remains strong.
      // The cap prevents unbounded target chasing; SL protection is independent.
      if(OrderTakeProfit()>0 && favorable>=atr*InpTargetATR*InpExtendTargetTriggerFraction &&
         TrendStillSupportsTrade(symbol,type))
      {
         double maxDist=atr*InpMaxTargetDistanceATR;
         double candidate=(type==OP_BUY?OrderOpenPrice()+maxDist:OrderOpenPrice()-maxDist);
         if(type==OP_BUY && OrderTakeProfit()<candidate-point && candidate-bid>=minDistance)
         { desiredTP=candidate; changeTP=true; reason=reason+"|TP_EXTEND_TREND"; }
         if(type==OP_SELL && OrderTakeProfit()>candidate+point && ask-candidate>=minDistance)
         { desiredTP=candidate; changeTP=true; reason=reason+"|TP_EXTEND_TREND"; }
      }

      if(!changeSL && !changeTP) continue;
      desiredSL=(desiredSL>0?NormalizeDouble(desiredSL,digits):0);
      desiredTP=(desiredTP>0?NormalizeDouble(desiredTP,digits):0);
      ResetLastError();
      bool ok=OrderModify(OrderTicket(),OrderOpenPrice(),desiredSL,desiredTP,0,clrNONE);
      if(ok)
         Print("BITEY_SBT_ADAPTIVE_MANAGEMENT | symbol=",symbol," ticket=",OrderTicket(),
               " side=",(type==OP_BUY?"BUY":"SELL")," action=",reason,
               " favorableMove=",DoubleToString(favorable,digits),
               " ATR=",DoubleToString(atr,digits),
               " SL=",DoubleToString(desiredSL,digits)," TP=",DoubleToString(desiredTP,digits));
      else
         Print("BITEY_SBT_ADAPTIVE_MANAGEMENT_REJECT | symbol=",symbol," ticket=",OrderTicket(),
               " action=",reason," error=",GetLastError(),
               " SL=",DoubleToString(desiredSL,digits)," TP=",DoubleToString(desiredTP,digits));
   }
}

int OnInit()
{
   if(EffectiveCapital()<=0){Print("BITEY_SBT_INIT_REJECT | reason=ACCOUNT_CURRENCY_OR_CAPITAL | accountCurrency=",AccountCurrency());return INIT_FAILED;}
   bool demoAccount=IsDemo();
   if(InpMode!=AUTO_EXECUTION){Print("BITEY_SBT_INIT_REJECT | reason=AUTO_EXECUTION_REQUIRED_FOR_LIVE_PARITY_TEST | mode=OBSERVE_ONLY");return INIT_FAILED;}
   EventSetTimer(MathMax(5,InpScanIntervalSeconds));
   Print("BITEY_SBT_1.99.5_INIT | mode=",(InpMode==OBSERVE_ONLY?"OBSERVE_ONLY":"AUTO_EXECUTION"),
         " strategicCapitalUSD=",DoubleToString(EffectiveCapital(),2)," perTradeRiskCapUSD=",DoubleToString(MathMin(1.25,InpHardRiskCapUSD),2),
         " portfolioRiskCapUSD=",DoubleToString(MathMin(8.75,InpPortfolioRiskCapUSD),2)," maxPositions=",MathMin(7,InpMaxOpenTrades),
         " accountType=",(demoAccount?"DEMO_USING_REAL_RULES":"REAL"),
         " demoRealRuleParity=ENFORCED",
         " fixedCapitalNotAccountBalance=true adaptiveSLTP=",(InpEnableAdaptiveManagement?"ON":"OFF"),
         " note=research_candidate_not_backtested_or_compiled");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){EventKillTimer();}

void OnTimer()
{
   if(TimeCurrent()-g_lastScan<MathMax(5,InpScanIntervalSeconds))return;
   g_lastScan=TimeCurrent();
   ManageAdaptiveStopsAndTargets();
   double dayNet=DailyNetUSD();
   if(dayNet<=-MathMin(10.0,MathAbs(InpDailyLossLimitUSD)))
      Print("BITEY_SBT_DAILY_GUARD | newEntriesBlocked=true dailyNetUSD=",DoubleToString(dayNet,2)," protectiveOrdersRemainManual");
   int total=SymbolsTotal(true);
   for(int i=0;i<total;i++)
   {
      string symbol=SymbolName(i,true);
      if(StringLen(symbol)<1)continue;
      ScanSymbol(symbol);
   }
}

void OnTick()
{
   // Chart-local closed-bar heartbeat only; cross-asset scanning is timer-driven.
   datetime b=iTime(Symbol(),InpTimeframe,1);
   if(b>0&&b!=g_lastBar){g_lastBar=b;Print("BITEY_SBT_BAR | chartSymbol=",Symbol()," closedBar=",TimeToString(b,TIME_DATE|TIME_MINUTES));}
}
