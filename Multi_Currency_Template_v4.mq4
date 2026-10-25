//+------------------------------------------------------------------+
//|                                    MultiCurrency Template EA MT4 |
//|                                                   Copyright 2023 |
//|                                               drdz9876@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2023, drdz9876@gmail.com"
#property version "4.1"
#property strict
#include <stdlib.mqh>
enum Orders
  {
   BuyandSell,     //Buy and Sell
   BuyOnly,         //Buy Only
   SellOnly        //Sell Only
  };
// Main input parameters
input Orders OrderMethod      = BuyandSell; //Orders Type
input double Lots             = 0.01;      // Basic lot size
input int    StopLoss         = 50;    //Stoploss (in Pips)
input int    TakeProfit       = 100;  //TakeProfit (in Pips)
input int    TrailingStop     = 15; // Trailing Stop (in points)
input int    TrailingStep     = 5;// Trailing Step (in points)
input int    Magic            = 1; // Magic Number
input string Commentary       = "Multicurrency EA";   //EA Comment
input int    Slippage         = 100;  // Tolerated slippage in brokers' pips
input bool   TradeMultipair   = false; // Trade Multipair
input string PairsToTrade     = "XAUUSD,XAGUSD,AUDCAD,AUDCHF,AUDJPY,AUDNZD,AUDUSD,CADCHF,CADJPY,CHFJPY,EURAUD,EURCAD,EURCHF,EURGBP,EURJPY,EURNZD,EURUSD,GBPAUD,GBPCAD,GBPCHF,GBPJPY,GBPNZD,GBPUSD,USDCAD,USDCHF,USDJPY"; //Symbols To Trade

input const string Martin="//---------------- Martingale Settings ----------------//";
input bool EnableMartingale = true;   //Enable Martingale
input double nextLot       = 1.2;    //Lot Multiplier / Increment
input int  StepPips        = 150;     //Pip Step (in Points)
input bool EnableTPAvg     = true;   //Enable TP Average
input int  TPPlus          = 20;      //TP Average (in Points)

//--------
int      NoOfPairs;           // Holds the number of pairs passed by the user via the inputs screen
string   TradePair[];         //Array to hold the pairs traded by the user
int PipValue = 1;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Expert
  {
private:
   int               Signal(string sym);
   double            lotAdjust(string sym, double lots);
   bool              NewBar(string sym);
   void              BuyOrder(string sym);
   void              SellOrder(string sym);
   void              Trail(string sym);
   void              ModifyStopLoss(string sym, double ldStopLoss);
   void              Martingale(string sym);
   bool              compareDoubles(string sym, double val1, double val2);

public:
   void              Trade(string sym);

protected:
   bool              CheckMoneyForTrade(string sym, double lots, int type);
   bool              CheckVolumeValue(string sym, double volume);
  };

Expert EA[];
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(TradeMultipair)
     {
      //Extract the pairs traded by the user
      NoOfPairs = StringFindCount(PairsToTrade,",")+1;
      ArrayResize(TradePair, NoOfPairs);
      ArrayResize(EA, NoOfPairs);
      string AddChar = StringSubstr(Symbol(),6, 4);
      StrPairToStringArray(PairsToTrade, TradePair, AddChar);
     }
   else
     {
      //Fill the array with only chart pair
      NoOfPairs = 1;
      ArrayResize(TradePair, NoOfPairs);
      ArrayResize(EA, NoOfPairs);
      TradePair[0] = Symbol();
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   return;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsDemo())
     {
      Alert("Only Demo");
      ExpertRemove();
      return;
     }
   RefreshRates();

   if(TradeMultipair)
     {
      for(int i = 0; i<NoOfPairs; i++)
        {
         EA[i].Trade(TradePair[i]);
        }
     }
   else
     {
      EA[0].Trade(TradePair[0]);
     }

   return;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Expert::Trade(string sym)
  {
   int countAll = 0, countBuy = 0, countSell = 0;
   for(int i=OrdersTotal()-1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == sym)
            if(OrderMagicNumber() == Magic)
              {
               countAll++;
               if(OrderType() == OP_BUY)
                  countBuy++;
               if(OrderType() == OP_SELL)
                  countSell++;
              }
        }

   if(NewBar(sym))
     {
      if(OrderMethod == BuyandSell)
        {
         if(Signal(sym) == 1 && CheckMoneyForTrade(sym,Lots,OP_BUY) && CheckVolumeValue(sym,Lots))
           {
            if(countBuy == 0)
               BuyOrder(sym);
           }
         else
            if(Signal(sym) == -1 && CheckMoneyForTrade(sym,Lots,OP_SELL) && CheckVolumeValue(sym,Lots))
              {
               if(countSell == 0)
                  SellOrder(sym);
              }
        }
      else
         if(OrderMethod == BuyOnly)
           {
            if(Signal(sym) == 1 && CheckMoneyForTrade(sym,Lots,OP_BUY) && CheckVolumeValue(sym,Lots))
               if(countBuy == 0)
                  BuyOrder(sym);
           }
         else
            if(OrderMethod == SellOnly)
              {
               if(Signal(sym) == -1 && CheckMoneyForTrade(sym,Lots,OP_SELL) && CheckVolumeValue(sym,Lots))
                  if(countSell == 0)
                     SellOrder(sym);
              }
     }

   if(EnableMartingale)
      Martingale(sym);

   Trail(sym);

   return;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Expert::Martingale(string sym)
  {
   double ask = SymbolInfoDouble(sym,SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym,SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   int stopLevel = (int)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);
   int spread = (int)SymbolInfoInteger(sym,SYMBOL_SPREAD);

   double
   BuyPriceMax = 0, BuyPriceMin = 0,
   SelPriceMin = 0, SelPriceMax = 0,
   BuyPriceMaxLot = 0, BuyPriceMinLot = 0,
   SelPriceMaxLot = 0, SelPriceMinLot = 0,
   BuyTP = 0, BuySL = 0, BSL = 0, SSL = 0,
   SellTP = 0, SellSL = 0;
   int
   countOpen = 0, buys = 0, sells = 0;
   double opB=0, opBE=0, opSE=0, opS=0, factb = 0, facts = 0;
   double llot=0,llots=0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == sym)
            if(OrderMagicNumber() == Magic)
              {
               countOpen++;
               double op = NormalizeDouble(OrderOpenPrice(), digits);

               if(OrderType() == OP_BUY)
                 {
                  buys++;
                  BuyTP = NormalizeDouble(OrderTakeProfit(),digits);
                  BuySL = NormalizeDouble(OrderStopLoss(),digits);
                  opB = NormalizeDouble(OrderOpenPrice(), digits);
                  opBE += OrderOpenPrice() * OrderLots();
                  llot += OrderLots();
                  factb=opBE/llot;

                  if(opB > BuyPriceMax || BuyPriceMax == 0)
                    {
                     BuyPriceMax    = opB;
                     BuyPriceMaxLot = llot;
                    }
                  if(opB < BuyPriceMin || BuyPriceMin == 0)
                    {
                     BuyPriceMin    = opB;
                     BuyPriceMinLot = llot;
                    }
                 }
               if(OrderType() == OP_SELL)
                 {
                  sells++;
                  SellTP = NormalizeDouble(OrderTakeProfit(),digits);
                  SellSL = NormalizeDouble(OrderStopLoss(),digits);
                  opS = NormalizeDouble(OrderOpenPrice(), digits);
                  opSE += OrderOpenPrice() * OrderLots();
                  llots += OrderLots();
                  facts=opSE/llots;

                  if(opS > SelPriceMax || SelPriceMax == 0)
                    {
                     SelPriceMax    = opS;
                     SelPriceMaxLot = llots;
                    }
                  if(opS < SelPriceMin || SelPriceMin == 0)
                    {
                     SelPriceMin    = opS;
                     SelPriceMinLot = llots;
                    }
                 }
              }
        }
   double PipSteps = 0;
   PipSteps = StepPips * point;

   double buyLot = 0, selLot = 0;

   buyLot = lotAdjust(sym,BuyPriceMinLot * MathPow(nextLot,buys));
   selLot = lotAdjust(sym,SelPriceMaxLot * MathPow(nextLot,sells));

   if(buys > 0)
     {
      if(BuyPriceMin - ask >= PipSteps)
        {
         if(CheckMoneyForTrade(sym,buyLot,OP_BUY) && CheckVolumeValue(sym,buyLot))
            if(!OrderSend(sym,OP_BUY,buyLot,ask,Slippage,0,0,Commentary,Magic,0,clrBlue))
               Print(sym+" Buy Average Failed"+ErrorDescription(GetLastError()));
        }
     }
   if(sells > 0)
     {
      if(bid - SelPriceMax >= PipSteps)
        {
         if(CheckMoneyForTrade(sym,selLot,OP_SELL) && CheckVolumeValue(sym,selLot))
            if(!OrderSend(sym,OP_SELL,selLot,bid,Slippage,0,0,Commentary,Magic,0,clrRed))
               Print(sym+" Sell Average Failed"+ErrorDescription(GetLastError()));
        }
     }

   double TPAverage = TPPlus * point;

   double CORRb = 0, CORRs = 0;
   CORRb = NormalizeDouble(TPAverage,digits);
   CORRs = NormalizeDouble(TPAverage,digits);

   for(int j=OrdersTotal()-1; j>=0; j--)
     {
      if(OrderSelect(j,SELECT_BY_POS,MODE_TRADES))
         if(OrderSymbol()==sym)
            if(OrderMagicNumber() == Magic)
              {
               if(buys >=2 && OrderType()==OP_BUY)
                 {
                  if(EnableTPAvg)
                    {
                     if(!compareDoubles(sym,OrderTakeProfit(),factb+CORRb))
                        if(!OrderModify(OrderTicket(),OrderOpenPrice(),BuySL,factb+CORRb,0,clrGreenYellow))
                           Print(sym+" Modify BuyTP Error "+ErrorDescription(GetLastError()));
                    }
                  else
                    {
                     if(!compareDoubles(sym,OrderTakeProfit(),BuyTP))
                        if(!OrderModify(OrderTicket(),OrderOpenPrice(),BuySL,BuyTP,0,clrGreenYellow))
                           Print(sym+" Modify BuyTP Error "+ErrorDescription(GetLastError()));
                    }
                 }
               if(sells >= 2 && OrderType()==OP_SELL)
                 {
                  if(EnableTPAvg)
                    {
                     if(!compareDoubles(sym,OrderTakeProfit(),facts-CORRs))
                        if(!OrderModify(OrderTicket(),OrderOpenPrice(),SellSL,facts-CORRs,0,clrGreenYellow))
                           Print(sym+" Modify SellTP Error "+ErrorDescription(GetLastError()));
                    }
                  else
                    {
                     if(!compareDoubles(sym,OrderTakeProfit(),SellTP))
                        if(!OrderModify(OrderTicket(),OrderOpenPrice(),SellSL,SellTP,0,clrGreenYellow))
                           Print(sym+" Modify SellTP Error "+ErrorDescription(GetLastError()));
                    }
                 }
              }
     }
   return;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Expert::compareDoubles(string sym, double val1, double val2)
  {
   int digits = (int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   if(NormalizeDouble(val1 - val2,digits-1)==0)
      return (true);

   return(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int StringFindCount(string str, string str2)
//+------------------------------------------------------------------+
// Returns the number of occurrences of STR2 in STR
// Usage:   int x = StringFindCount("ABCDEFGHIJKABACABB","AB")   returns x = 3
  {
   int c = 0;
   for(int i=0; i<StringLen(str); i++)
      if(StringSubstr(str,i,StringLen(str2)) == str2)
         c++;
   return(c);
  } // End int StringFindCount(string str, string str2)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void StrPairToStringArray(string str, string &a[], string p_suffix, string delim=",")
//+------------------------------------------------------------------+
  {
   int z1=-1, z2=0;
   for(int i=0; i<ArraySize(a); i++)
     {
      z2 = StringFind(str,delim,z1+1);
      a[i] = StringSubstr(str,z1+1,z2-z1-1) + p_suffix;
      if(z2 >= StringLen(str)-1)
         break;
      z1 = z2;
     }
   return;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Expert::CheckMoneyForTrade(string sym, double lots, int type)
  {
   double free_margin = AccountFreeMarginCheck(sym,type,lots);
//-- if there is not enough money
   if(free_margin<0)
     {
      string oper=(type==OP_BUY)? "Buy":"Sell";
      Print("Not enough money for ", oper," ",lots, " ", sym, " Error code=",GetLastError());
      return(false);
     }
//--- checking successful
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Expert::CheckVolumeValue(string sym, double volume)
  {
//--- minimal allowed volume for trade operations
   double min_volume=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   if(volume<min_volume)
     {
      Print("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=%.2f",min_volume);
      return(false);
     }

//--- maximal allowed volume of trade operations
   double max_volume=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   if(volume>max_volume)
     {
      Print("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=%.2f",max_volume);
      return(false);
     }

//--- get minimal step of volume changing
   double volume_step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);

   int ratio=(int)MathRound(volume/volume_step);
   if(MathAbs(ratio*volume_step-volume)>0.0000001)
     {
      Print("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=%.2f, the closest correct volume is %.2f",
            volume_step,ratio*volume_step);
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Expert::lotAdjust(string sym, double lots)
  {
   double value = 0;
   double lotStep = SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   value          = NormalizeDouble(lots/lotStep,0) * lotStep;

   if(value < minLot)
      value = minLot;
   if(value > maxLot)
      value = maxLot;

   return(value);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Expert::NewBar(string sym)
  {
//--- memorize the time of opening of the last bar in the static variable
   static datetime last_time=0;
//--- current time
   datetime lastbar_time=(datetime)SeriesInfoInteger(sym,PERIOD_CURRENT,SERIES_LASTBAR_DATE);

//--- if it is the first call of the function
   if(last_time==0)
     {
      //--- set the time and exit
      last_time=lastbar_time;
      return(false);
     }

//--- if the time differs
   if(last_time!=lastbar_time)
     {
      //--- memorize the time and return true
      last_time=lastbar_time;
      return(true);
     }
//--- if we passed to this line, then the bar is not new; return false
   return(false);
  }

//+------------------------------------------------------------------+
int Expert::Signal(string sym)
  {
   double ma1 = iMA(sym,Period(),20,0,MODE_EMA,PRICE_CLOSE,1);
   double ma2 = iMA(sym,Period(),50,0,MODE_EMA,PRICE_CLOSE,1);
   if(ma1 > ma2)
      return(1);
   if(ma1 < ma2)
      return(-1);

   return (0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Expert::BuyOrder(string sym)
  {
   double bid = MarketInfo(sym,MODE_BID);
   double ask = MarketInfo(sym,MODE_ASK);
   double point=MarketInfo(sym,MODE_POINT);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);

   if(digits == 3 || digits == 5)
      PipValue = 10;
   else
      PipValue = 1;

   double SL = ask - StopLoss*PipValue*point;
   if(StopLoss == 0)
      SL = 0;
   double TP = ask + TakeProfit*PipValue*point;
   if(TakeProfit == 0)
      TP = 0;
   int ticket = -1;
   if(true)
      ticket = OrderSend(sym, OP_BUY, lotAdjust(sym,Lots), ask, Slippage, 0, 0, Commentary, Magic, 0, clrBlue);
   else
      ticket = OrderSend(sym, OP_BUY, lotAdjust(sym,Lots), ask, Slippage, SL, TP, Commentary, Magic, 0, clrBlue);
   if(ticket > -1)
     {
      if(true)
        {
         bool sel = OrderSelect(ticket, SELECT_BY_TICKET);
         bool ret = OrderModify(OrderTicket(), OrderOpenPrice(), SL, TP, 0, clrBlue);
         if(ret == false)
            Print("OrderModify() error - ", ErrorDescription(GetLastError()));
        }

     }
   else
     {
      Print("OrderSend() error - ", ErrorDescription(GetLastError()));
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Expert::SellOrder(string sym)
  {
   double bid = MarketInfo(sym,MODE_BID);
   double ask = MarketInfo(sym,MODE_ASK);
   double point=MarketInfo(sym,MODE_POINT);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);

   if(digits == 3 || digits == 5)
      PipValue = 10;
   else
      PipValue = 1;

   double SL = bid + StopLoss*PipValue*point;
   if(StopLoss == 0)
      SL = 0;
   double TP = bid - TakeProfit*PipValue*point;
   if(TakeProfit == 0)
      TP = 0;
   int ticket = -1;
   if(true)
      ticket = OrderSend(sym, OP_SELL, lotAdjust(sym,Lots), bid, Slippage, 0, 0, Commentary, Magic, 0, clrRed);
   else
      ticket = OrderSend(sym, OP_SELL, lotAdjust(sym,Lots), bid, Slippage, SL, TP, Commentary, Magic, 0, clrRed);
   if(ticket > -1)
     {
      if(true)
        {
         bool sel = OrderSelect(ticket, SELECT_BY_TICKET);
         bool ret = OrderModify(OrderTicket(), OrderOpenPrice(), SL, TP, 0, clrRed);
         if(ret == false)
            Print("OrderModify() error - ", ErrorDescription(GetLastError()));
        }
     }
   else
     {
      Print("OrderSend() error - ", ErrorDescription(GetLastError()));
     }
  }
//+------------------------------------------------------------------+
void Expert::Trail(string sym)
  {
   double bid = MarketInfo(sym,MODE_BID);
   double ask = MarketInfo(sym,MODE_ASK);
   double point=MarketInfo(sym,MODE_POINT);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   int Stoplvl=(int)MarketInfo(sym,MODE_STOPLEVEL);


   double TS = (TrailingStop + Stoplvl)*point;
   double TST = (TrailingStep + Stoplvl)*point;

   int countBuy = 0, countSell = 0;
   for(int i=OrdersTotal()-1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == sym)
            if(OrderMagicNumber() == Magic)
              {
               if(OrderType() == OP_BUY)
                  countBuy++;
               if(OrderType() == OP_SELL)
                  countSell++;
              }
        }

   for(int i=OrdersTotal()-1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol()==sym)
            if(OrderMagicNumber()==Magic)
              {
               if(OrderType() == OP_BUY && countBuy == 1)
                 {
                  if(OrderStopLoss() == 0 || (OrderStopLoss() != 0 && OrderStopLoss() < OrderOpenPrice()))
                    {
                     if(bid - OrderOpenPrice() > TS+TST-1*point)
                       {
                        ModifyStopLoss(sym, bid-TS);
                       }
                    }
                  if(OrderStopLoss() > OrderOpenPrice())
                    {
                     if(bid - OrderStopLoss() > TST+(5*point))
                       {
                        ModifyStopLoss(sym, bid-TST);
                       }
                    }
                 }
               if(OrderType() == OP_SELL && countSell == 1)
                 {
                  if(OrderStopLoss() == 0 || (OrderStopLoss()!= 0 && OrderStopLoss() > OrderOpenPrice()))
                    {
                     if(OrderOpenPrice() - ask > TS+TST-1*point)
                       {
                        ModifyStopLoss(sym, ask+TS);
                       }
                    }
                  if(OrderStopLoss() < OrderOpenPrice())
                    {
                     if(OrderStopLoss()-ask > TST+(5*point))
                       {
                        ModifyStopLoss(sym, ask+TST);
                       }
                    }
                 }
              }
        }
     }
  }


//+------------------------------------------------------------------+
void Expert::ModifyStopLoss(string sym, double ldStopLoss)
  {
   if(!OrderModify(OrderTicket(),OrderOpenPrice(),ldStopLoss,OrderTakeProfit(),0,clrAqua))
      Print(sym+" Trail Error "+ErrorDescription(GetLastError()));

   return;
  }

//+------------------------------------------------------------------+
