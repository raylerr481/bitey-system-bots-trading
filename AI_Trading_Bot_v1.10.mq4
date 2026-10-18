//+------------------------------------------------------------------+
//| AI_Trading_Bot_v1.10.mq4                                        |
//| Diagnostic + AI-assisted MT4 EA                                 |
//| Demo-safe by default. Risk engine always has final authority.    |
//+------------------------------------------------------------------+
#property strict
#property version "1.10"

enum ENUM_AI_DECISION { AI_WAIT=0, AI_BUY=1, AI_SELL=2 };

input bool InpDemoSafeMode=true;
input bool InpUseExternalAI=false;
input string InpAIEndpoint="";
input int InpAITimeoutMs=3000;
input double InpRiskPct=0.25;
input double InpMaxLots=2.0;
input int InpMaxTrades=1;
input double InpDailyLossPct=2.0;
input double InpWeeklyLossPct=4.0;
input double InpMonthlyLossPct=8.0;
input int InpFastEMA=8;
input int InpSlowEMA=21;
input int InpMacroEMA=200;
input int InpADXPeriod=14;
input double InpADXMin=20.0;
input int InpRSIPeriod=14;
input double InpRSIBuyMin=50.0;
input double InpRSIBuyMax=68.0;
input double InpRSISellMin=32.0;
input double InpRSISellMax=50.0;
input int InpATRPeriod=14;
input double InpMinATRPoints=20.0;
input double InpSLMult=1.50;
input double InpTPMult=3.00;
input double InpBEStartMult=1.20;
input double InpBELockMult=0.10;
input double InpTrailStartMult=1.80;
input double InpTrailDistMult=1.00;
input int InpMaxSpreadPoints=30;
input double InpMaxSpreadATR=0.20;
input int InpSessionStartHour=7;
input int InpSessionEndHour=20;
input int InpFridayCloseHour=21;
input int InpCooldownBars=3;
input int InpMinimumScore=5;
input int InpMagic=8883100;
input int InpSlippage=5;
input bool InpVerboseDiagnostics=true;
input bool InpShowDashboard=true;
input bool InpAllowLong=true;
input bool InpAllowShort=true;

datetime g_lastBarTime=0,g_lastBuyBar=0,g_lastSellBar=0;
int g_lastScoreBuy=0,g_lastScoreSell=0;
string g_lastReason="Waiting for new bar";
ENUM_AI_DECISION g_lastAI=AI_WAIT;

string TFName(){switch(Period()){case PERIOD_M1:return "M1";case PERIOD_M5:return "M5";case PERIOD_M15:return "M15";case PERIOD_M30:return "M30";case PERIOD_H1:return "H1";case PERIOD_H4:return "H4";case PERIOD_D1:return "D1";}return IntegerToString(Period());}
bool IsNewBar(){if(Time[0]!=g_lastBarTime){g_lastBarTime=Time[0];return true;}return false;}
double EMA(int p,int sh){return iMA(Symbol(),Period(),p,0,MODE_EMA,PRICE_CLOSE,sh);}
double ADX(int sh){return iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh);}
double RSI(int sh){return iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,sh);}
double ATR(int sh){return iATR(Symbol(),Period(),InpATRPeriod,sh);}

bool SpreadOK(string &why){RefreshRates();double sp=(Ask-Bid)/Point,atr=ATR(1);if(sp>InpMaxSpreadPoints){why="Spread too high";return false;}if(atr<=0){why="ATR unavailable";return false;}if(sp*Point>atr*InpMaxSpreadATR){why="Spread/ATR too high";return false;}why="PASS";return true;}
bool SessionOK(string &why){int h=TimeHour(TimeCurrent());if(h<InpSessionStartHour||h>=InpSessionEndHour){why="Outside session";return false;}if(TimeDayOfWeek(TimeCurrent())==5&&h>=InpFridayCloseHour){why="Friday close window";return false;}why="PASS";return true;}
bool CooldownOK(bool buy,string &why){datetime last=buy?g_lastBuyBar:g_lastSellBar;if(last<=0){why="PASS";return true;}int bars=iBarShift(Symbol(),Period(),last,true);if(bars>=0&&bars<InpCooldownBars){why="Cooldown";return false;}why="PASS";return true;}

int BuyScore(string &diag){int score=0;string s="";double f1=EMA(InpFastEMA,1),f2=EMA(InpFastEMA,2),sl1=EMA(InpSlowEMA,1),sl2=EMA(InpSlowEMA,2),m1=EMA(InpMacroEMA,1),m2=EMA(InpMacroEMA,2),adx=ADX(1),rsi=RSI(1),atr=ATR(1);bool macro=Close[1]>m1&&m1>m2,ema=f1>sl1&&f1>f2&&sl1>=sl2,adxok=adx>=InpADXMin,rsiok=rsi>=InpRSIBuyMin&&rsi<=InpRSIBuyMax,atro=atr/Point>=InpMinATRPoints,cross=f1>sl1&&f2<=sl2,confirm=(Low[1]<=f1&&Close[1]>f1)||(Close[1]>Open[1]&&Close[1]>f1);if(macro){score++;s+="MACRO PASS; ";}else s+="MACRO FAIL; ";if(ema){score++;s+="EMA PASS; ";}else s+="EMA FAIL; ";if(adxok){score++;s+="ADX PASS; ";}else s+="ADX FAIL; ";if(rsiok){score++;s+="RSI PASS; ";}else s+="RSI FAIL; ";if(atro){score++;s+="ATR PASS; ";}else s+="ATR FAIL; ";if(cross){score++;s+="CROSS PASS; ";}else s+="CROSS FAIL; ";if(confirm){score++;s+="CONFIRM PASS; ";}else s+="CONFIRM FAIL; ";diag=s;return score;}
int SellScore(string &diag){int score=0;string s="";double f1=EMA(InpFastEMA,1),f2=EMA(InpFastEMA,2),sl1=EMA(InpSlowEMA,1),sl2=EMA(InpSlowEMA,2),m1=EMA(InpMacroEMA,1),m2=EMA(InpMacroEMA,2),adx=ADX(1),rsi=RSI(1),atr=ATR(1);bool macro=Close[1]<m1&&m1<m2,ema=f1<sl1&&f1<f2&&sl1<=sl2,adxok=adx>=InpADXMin,rsiok=rsi>=InpRSISellMin&&rsi<=InpRSISellMax,atro=atr/Point>=InpMinATRPoints,cross=f1<sl1&&f2>=sl2,confirm=(High[1]>=f1&&Close[1]<f1)||(Close[1]<Open[1]&&Close[1]<f1);if(macro){score++;s+="MACRO PASS; ";}else s+="MACRO FAIL; ";if(ema){score++;s+="EMA PASS; ";}else s+="EMA FAIL; ";if(adxok){score++;s+="ADX PASS; ";}else s+="ADX FAIL; ";if(rsiok){score++;s+="RSI PASS; ";}else s+="RSI FAIL; ";if(atro){score++;s+="ATR PASS; ";}else s+="ATR FAIL; ";if(cross){score++;s+="CROSS PASS; ";}else s+="CROSS FAIL; ";if(confirm){score++;s+="CONFIRM PASS; ";}else s+="CONFIRM FAIL; ";diag=s;return score;}

int CountOpenTrades(){int n=0;for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))if(OrderSymbol()==Symbol()&&OrderMagicNumber()==InpMagic&&(OrderType()==OP_BUY||OrderType()==OP_SELL))n++;return n;}

bool RiskGate(string &why){if(CountOpenTrades()>=InpMaxTrades){why="Max open trades";return false;}string d="AI_DAY_"+Symbol()+"_"+IntegerToString(InpMagic),m="AI_MON_"+Symbol()+"_"+IntegerToString(InpMagic);double ds=GlobalVariableCheck(d)?GlobalVariableGet(d):AccountBalance(),ms=GlobalVariableCheck(m)?GlobalVariableGet(m):AccountBalance();if(ds>0&&(ds-AccountEquity())/ds*100.0>=InpDailyLossPct){why="Daily loss limit";return false;}if(ms>0&&(ms-AccountEquity())/ms*100.0>=InpMonthlyLossPct){why="Monthly loss limit";return false;}why="PASS";return true;}

double LotByRisk(double stopDistance){if(stopDistance<=0)return 0;double risk=AccountBalance()*InpRiskPct/100.0,tv=MarketInfo(Symbol(),MODE_TICKVALUE),ts=MarketInfo(Symbol(),MODE_TICKSIZE);if(tv<=0||ts<=0)return 0;double lossPerLot=(stopDistance/ts)*tv;if(lossPerLot<=0)return 0;double lots=risk/lossPerLot,minLot=MarketInfo(Symbol(),MODE_MINLOT),maxLot=MathMin(MarketInfo(Symbol(),MODE_MAXLOT),InpMaxLots),step=MarketInfo(Symbol(),MODE_LOTSTEP);lots=MathMin(lots,maxLot);if(step>0)lots=MathFloor(lots/step)*step;if(lots<minLot)return 0;return NormalizeDouble(lots,2);}

bool SendTrade(bool buy){string why="";if(!RiskGate(why)){g_lastReason="BLOCK: "+why;return false;}double atr=ATR(1);if(atr<=0){g_lastReason="BLOCK: ATR unavailable";return false;}double slDist=atr*InpSLMult,tpDist=atr*InpTPMult,lots=LotByRisk(slDist);if(lots<=0){g_lastReason="BLOCK: lot calculation returned zero";return false;}RefreshRates();int type=buy?OP_BUY:OP_SELL;double price=buy?Ask:Bid,sl=buy?price-slDist:price+slDist,tp=buy?price+tpDist:price-tpDist;price=NormalizeDouble(price,Digits);sl=NormalizeDouble(sl,Digits);tp=NormalizeDouble(tp,Digits);if(InpDemoSafeMode){g_lastReason=StringFormat("SAFE DEMO: %s signal, no order sent",buy?"BUY":"SELL");return false;}ResetLastError();int ticket=OrderSend(Symbol(),type,lots,price,InpSlippage,sl,tp,"AI Trading Bot",InpMagic,0,buy?clrBlue:clrRed);if(ticket<0){g_lastReason="OrderSend failed: "+IntegerToString(GetLastError());return false;}if(buy)g_lastBuyBar=Time[1];else g_lastSellBar=Time[1];g_lastReason=StringFormat("ORDER SENT #%d %s %.2f lots",ticket,buy?"BUY":"SELL",lots);return true;}

ENUM_AI_DECISION LocalDecision(int bs,int ss){if(bs>=InpMinimumScore&&bs>ss)return AI_BUY;if(ss>=InpMinimumScore&&ss>bs)return AI_SELL;return AI_WAIT;}

void ManagePositions(){double atr=ATR(0);if(atr<=0)return;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=InpMagic)continue;if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL)continue;RefreshRates();double open=OrderOpenPrice(),cur=OrderType()==OP_BUY?Bid:Ask,dist=OrderType()==OP_BUY?cur-open:open-cur;if(dist>=atr*InpBEStartMult){double ns=OrderType()==OP_BUY?open+atr*InpBELockMult:open-atr*InpBELockMult;ns=NormalizeDouble(ns,Digits);bool improve=OrderType()==OP_BUY?(OrderStopLoss()==0||ns>OrderStopLoss()):(OrderStopLoss()==0||ns<OrderStopLoss());if(improve)OrderModify(OrderTicket(),OrderOpenPrice(),ns,OrderTakeProfit(),0,clrNONE);}if(dist>=atr*InpTrailStartMult){double tr=OrderType()==OP_BUY?cur-atr*InpTrailDistMult:cur+atr*InpTrailDistMult;tr=NormalizeDouble(tr,Digits);bool improve2=OrderType()==OP_BUY?(OrderStopLoss()==0||tr>OrderStopLoss()):(OrderStopLoss()==0||tr<OrderStopLoss());if(improve2)OrderModify(OrderTicket(),OrderOpenPrice(),tr,OrderTakeProfit(),0,clrNONE);}}}

void InitializePeriodState(){string d="AI_DAY_"+Symbol()+"_"+IntegerToString(InpMagic),m="AI_MON_"+Symbol()+"_"+IntegerToString(InpMagic);if(!GlobalVariableCheck(d))GlobalVariableSet(d,AccountBalance());if(!GlobalVariableCheck(m))GlobalVariableSet(m,AccountBalance());}

void Dashboard(){if(!InpShowDashboard)return;double sp=(Ask-Bid)/Point,atr=ATR(1),adx=ADX(1),rsi=RSI(1);string s="AI TRADING BOT v1.10\n";s+="Symbol: "+Symbol()+" TF: "+TFName()+"\n";s+=StringFormat("Spread %.1f | ATR %.1f | ADX %.1f | RSI %.1f\n",sp,atr/Point,adx,rsi);s+=StringFormat("BUY %d/7 | SELL %d/7 | Min %d\n",g_lastScoreBuy,g_lastScoreSell,InpMinimumScore);s+="Decision: "+(g_lastAI==AI_BUY?"BUY":g_lastAI==AI_SELL?"SELL":"WAIT")+"\n";s+="Status: "+g_lastReason+"\n";s+="Demo Safe Mode: "+(InpDemoSafeMode?"ON":"OFF")+"\n";s+="Open trades: "+IntegerToString(CountOpenTrades());Comment(s);}

void DiagnosticLog(){if(!InpVerboseDiagnostics)return;string bd="",sd="";int bs=BuyScore(bd),ss=SellScore(sd);Print("=== AI BOT DIAGNOSTIC ",Symbol()," ",TFName()," ",TimeToString(Time[1])," ===");Print("BUY ",bs,"/7 | ",bd);Print("SELL ",ss,"/7 | ",sd);string why="";Print("Spread/ATR: ",SpreadOK(why)?"PASS":"FAIL"," | ",why);Print("Session: ",SessionOK(why)?"PASS":"FAIL"," | ",why);Print("Risk: ",RiskGate(why)?"PASS":"FAIL"," | ",why);Print("Minimum score=",InpMinimumScore," | DemoSafeMode=",InpDemoSafeMode?"TRUE":"FALSE");}

int OnInit(){InitializePeriodState();g_lastBarTime=Time[0];Print("AI Trading Bot v1.10 initialized: ",Symbol()," ",TFName());return INIT_SUCCEEDED;}
void OnDeinit(const int reason){Comment("");}

void OnTick(){ManagePositions();if(!IsNewBar()){Dashboard();return;}DiagnosticLog();string why="";if(!SpreadOK(why)){g_lastReason="BLOCK: "+why;Dashboard();return;}if(!SessionOK(why)){g_lastReason="BLOCK: "+why;Dashboard();return;}if(!RiskGate(why)){g_lastReason="BLOCK: "+why;Dashboard();return;}string bd="",sd="";g_lastScoreBuy=BuyScore(bd);g_lastScoreSell=SellScore(sd);g_lastAI=LocalDecision(g_lastScoreBuy,g_lastScoreSell);if(InpUseExternalAI){g_lastAI=AI_WAIT;g_lastReason="External AI enabled but API contract not connected: WAIT";Dashboard();return;}if(g_lastAI==AI_WAIT){g_lastReason=StringFormat("WAIT: BUY=%d SELL=%d minimum=%d",g_lastScoreBuy,g_lastScoreSell,InpMinimumScore);Dashboard();return;}bool buy=(g_lastAI==AI_BUY);if(buy&&!InpAllowLong){g_lastReason="BLOCK: BUY disabled";Dashboard();return;}if(!buy&&!InpAllowShort){g_lastReason="BLOCK: SELL disabled";Dashboard();return;}if(!CooldownOK(buy,why)){g_lastReason="BLOCK: "+why;Dashboard();return;}SendTrade(buy);Dashboard();}
//+------------------------------------------------------------------+
