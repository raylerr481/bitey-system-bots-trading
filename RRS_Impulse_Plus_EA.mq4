//+------------------------------------------------------------------+
//|                                                           RRS EA |
//|                                   Copyright 2025, RRS Fortune EA |
//|                                             rajeeevrrs@gmail.com |
//+------------------------------------------------------------------+
#property copyright "RRS Fortune EA"
#property link      "https://t.me/rajeevrrs"
#property strict
#property version   "1.40"
#import "urlmon.dll"
int URLDownloadToFileW(int pCaller,string szURL,string szFileName,int dwReserved,int Callback);
#import
//---
#define INAME     "RRSNews"
#define TITLE  0
#define COUNTRY 1
#define DATE  2
#define TIME  3
#define IMPACT  4
#define FORECAST 5
#define PREVIOUS 6

//+------------------------------------------------------------------+
//| EA Inputs                                                        |
//+------------------------------------------------------------------+

extern string __TradingIndicator__ = "***Trading Indicator***";
extern bool RSI = true;
extern bool BollingerBands = true;
extern bool MovingAverage = true;
extern bool Stochastic = false;

extern string __TimeFrame__ = "***TimeFrame Settings***";
extern bool PeriodM1 = true;
extern bool PeriodM5 = true;
extern bool PeriodM15 = true;
extern bool PeriodM30 = true;
extern bool PeriodH1 = false;
extern bool PeriodH4 = false;
extern bool PeriodD1 = false;

extern string __TradingStrategy__ = "***Trading Strategy***";
enum TradeDirection_enum {Trend, CounterTrend};
extern TradeDirection_enum TradeDirection = CounterTrend;
enum SignalStrength_enum {SingleTF, MultiTF};
extern SignalStrength_enum SignalStrength = SingleTF;
extern bool Inverse = false;

extern string __LotSettings__ = "***Lot Settings***";
enum LotMode_enum {Random_Lot, Lot_Percentage};
extern LotMode_enum LotMode = Lot_Percentage;
extern double minLot_Size = 0.01;
extern double maxLot_Size = 0.50;
extern int LotPercentage = 2;

extern string __TradeExit__ = "***Close Trades***";
enum TakeProfit_enum {Classic_TP, Virtual_TP};
extern TakeProfit_enum TakeProfit_Type = Virtual_TP;
extern int TakeProfit = 1000;
enum StopLoss_enum {Classic_SL, Virtual_SL};
extern StopLoss_enum StopLoss_Type = Virtual_SL;
extern int StopLoss = 500;
enum Trailing_enum {Classic_Trailing, Virtual_Trailing};
extern Trailing_enum Trailing_Type = Virtual_Trailing;
extern int Trailing_Start = 500;
extern int Trailing_Gap = 20;
extern int CandleExit = 10;

extern string __RestricationSettings__ = "***Restrication Settings***";
extern int maxSpread = 100;
extern int Slippage = 3;
extern int MaxOpenTrade = 10;
extern bool TradeMode = true;

extern string __RSI_Indicator__ = "***RSI Indicator Settings***";
extern ENUM_APPLIED_PRICE RSI_AppliedPrice = PRICE_CLOSE;
extern int RSI_Period = 14;
extern int RSI_shift = 0;
extern int RSI_UpLevel = 80;
extern int RSI_BelowLevel = 20;

extern string __BollingerBands_Indicator__ = "***Bollinger Bands Indicator Settings***";
extern ENUM_APPLIED_PRICE BollingerBands_AppliedPrice = PRICE_CLOSE;
extern int BollingerBands_Period = 20;
extern double BollingerBands_deviation = 2.0;
extern int BollingerBands_BandShift = 0;
extern int BollingerBands_Shift = 0;

extern string __MovingAverage_Indicator__ = "***Moving Average Indicator Settings***";
extern ENUM_MA_METHOD MovingAverage_Method = MODE_EMA;
extern ENUM_APPLIED_PRICE MovingAverage_AppliedPrice = PRICE_CLOSE;
extern int MovingAverage_Period = 200;
extern int MovingAverage_MAShift = 0;
extern int MovingAverage_Shift = 0;

extern string __Stochastic_Indicator__ = "***Stochastic Indicator Settings***";
extern ENUM_MA_METHOD Stochastic_Method = MODE_SMA;
extern int Stochastic_Kperiod = 14;
extern int Stochastic_Dperiod = 3;
extern int Stochastic_Slowing = 3;
extern int Stochastic_PriceField = 0;
extern int Stochastic_Shift = 0;
extern int Stochastic_UpLevel = 90;
extern int Stochastic_BelowLevel = 10;

extern string __Risk_Management__ = "***Risk Management***";
enum RiskManagementAction_enum {StopEA, CloseAndContinue};
extern RiskManagementAction_enum RiskManagement_Action = CloseAndContinue;
enum RiskInMoneyMode_enum {FixedMoney, BalancePercentage};
extern RiskInMoneyMode_enum Risk_In_Money_Type = BalancePercentage;
extern double Money_In_Risk = 5.0;

extern string __MoneyManagement__ = "***Money Management***";
enum MoneyManagementAction_enum {Stop_EA, Close_And_Continue};
extern MoneyManagementAction_enum MoneyManagement_Action = Close_And_Continue;
enum MoneyManagement_enum {Fixed_Money, Balance_Percentage};
extern MoneyManagement_enum MoneyManagement_Type = Balance_Percentage;
extern double Target_Revenue = 5.0;

extern string __NewsTradingManagement__ = "***News Management***";
enum NewsManagement_enum {NewsDeactivated, HighImpactNews, ImportantNews};
extern NewsManagement_enum NewsManagement = NewsDeactivated;
extern int BeforeNews_Minutes = 120;
extern int AfterNews_Minutes = 120;
extern int News_CutLoss = 20;
extern int News_ReCheckMinutes = 2000;
extern string Important_News = "CPI,FOMC,Non-Farm Employment Change,Federal Funds Rate";

extern string __Currencies__ = "***Assest Management***";
extern string Trade_Currencies = "USD,GBP,AUD,CAD,JPY,XAU,XAG,EUR,CHF,SDG,HKD,NZD";

extern string __ExpertAdvisor__ = "***EA Settings***";
extern int Magic = 1000;
extern bool ShowIndicatorStatus = false;
extern string EA_Notes = "Note For Your Reference";

//Timezone
int localHours = (TimeLocal() - TimeGMT()) / 3600;
int localMinutes = ((TimeLocal() - TimeGMT()) % 3600) / 60;
int brokerHours = (TimeCurrent() - TimeGMT()) / 3600;
int brokerMinutes = ((TimeCurrent() - TimeGMT()) % 3600) / 60;

//Int
int gBuyMagic, gSellMagic;
int OrderCount_BuyMagicOPBUY, OrderCount_SellMagicOPSELL, OrderCount_Symbol_OPBUY, OrderCount_Symbol_OPSELL;
int BuySellRandomMath;
int gSymbolIndex = 0;
int gSymbolRandomIndex = 0;
int gTimeFrameIndex = 0;
int gTimeFrameIndexForSymbol = 0;
int gBuyTotalOrder, gSellTotalOrder, gTotalOpenOrder;
int gRandomSpread, gBuySpread, gSellSpread;
int tBuySize = 0, tSellSize = 0;

//String
string gTradeComment;
string gRandomSymbol;
string gBuySymbol, gSellSymbol;
string gSingleTimeFrameSignalStatus, gRSISignal, gStochasticSignal, gBollingerBandsSignal, gMovingAverageSignal, gMultiTimeFrameSignalStatus;
string cTimeFrame, gSingleTFCheckingStatus, cRSIAppliedPrice, cSTOMethod, cSTOPriceField, cBBAppliedPrice, cTradeDirection, cSignalStrength, cLotMode, cMMAction, cRMAction, cMMType, cRiskType, cLotPercentage, cTradeMode, cMAMethod;
string cPeriodM1, cPeriodM5, cPeriodM30, cPeriodM15, cPeriodH1, cPeriodH4, cPeriodD1, cTakeProfitType, cStopLossType, cTrailingType;
string cRSI, cStochastic, cBollingerBands, cMovingAverage, cIndicatorStaus;
string tcRSI, tcStochastic, tcBollinger, tcTradeDirection, tcSignalStrength, tcMovingAverage;
string DemoRealCheck = IsDemo() ? "Demo" : "Real";

//Double
double gSymbolEA_FloatingPL, gBuyPL, gSellPL, gBuyOpenLot, gSellOpenLot,gTotalOpenLot;
double gTargeted_Revenue, gRisk_Money;
double OrderSend_StopLoss, OrderSend_TakeProfit;
double gRandomLotSize;
double rBID, rASK, bBID, bASK, sBID, sASK, rPoint, bPoint, sPoint;

//News Filter XML Values
string NewsURLChecking, XMLUpdateTime, XMLUpcomingImpact, XMLReadTime, XMLDownloadTime, cNewsStatus; //News XML Status
string gImportantNews_Array[];
bool gUpcomingImpact;
double gAvgChartPrice = (WindowPriceMax() + WindowPriceMin()) / 2; // Chart Update
string xmlFileName;
string sData;
string Event[200][7];
string eTitle[200][200],eCountry[200][200],eImpact[200][200],eForecast[200][200],ePrevious[200][200];
bool assignVal=true;
int eMinutes[10];
datetime eTime[200][200];
datetime xmlModifed;
int TimeOfDay;
datetime Midnight;
bool IsEvent;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   gBuyMagic    = Magic + 1;
   gSellMagic   = Magic + 11;

//Money Management
   if(MoneyManagement_Type == Balance_Percentage)
      gTargeted_Revenue = (1 + Target_Revenue/100) * AccountBalance();
   else
      gTargeted_Revenue = Target_Revenue + AccountBalance();

//Trade Comments
   tcTradeDirection = TradeDirection == Trend ? "T" : "CT";
   tcSignalStrength = SignalStrength == SingleTF ? "STF" : "MTF";
   if(RSI)
      tcRSI = "R";
   if(Stochastic)
      tcStochastic = "S";
   if(BollingerBands)
      tcBollinger = "B";
   if(MovingAverage)
      tcMovingAverage = "M";

   string tcPeriodM1 = PeriodM1  ? "1M"  : "";
   string tcPeriodM5 = PeriodM5  ? "5M"  : "";
   string tcPeriodM15 = PeriodM15 ? "15M" : "";
   string tcPeriodM30 = PeriodM30 ? "30M" : "";
   string tcPERIODH1 = PeriodH1  ? "1H" : "";
   string tcPeriodH4 = PeriodH4  ? "4H" : "";
   string tcPeriodD1 = PeriodD1  ? "1D" : "";

   if(SignalStrength == MultiTF)
      gTradeComment = tcRSI+tcBollinger+tcStochastic+tcMovingAverage + "+" + tcPeriodM1+tcPeriodM5+tcPeriodM15+tcPeriodM30+tcPERIODH1+tcPeriodH4+tcPeriodD1 + "+" + tcTradeDirection + "+" + tcSignalStrength + "+RRS";

   cRSIAppliedPrice = RSI_AppliedPrice == PRICE_CLOSE  ? "Close Price" :
                      RSI_AppliedPrice == PRICE_OPEN   ? "Open Price" :
                      RSI_AppliedPrice == PRICE_HIGH   ? "High Price" :
                      RSI_AppliedPrice == PRICE_LOW    ? "Low Price" :
                      RSI_AppliedPrice == PRICE_MEDIAN ? "Median Price" :
                      RSI_AppliedPrice == PRICE_TYPICAL? "Typical Price" :
                      RSI_AppliedPrice == PRICE_WEIGHTED? "Weighted Price" : "Unknown Price Type";

   cBBAppliedPrice = BollingerBands_AppliedPrice == PRICE_CLOSE   ? "Close Price" :
                     BollingerBands_AppliedPrice == PRICE_OPEN    ? "Open Price" :
                     BollingerBands_AppliedPrice == PRICE_HIGH    ? "High Price" :
                     BollingerBands_AppliedPrice == PRICE_LOW     ? "Low Price" :
                     BollingerBands_AppliedPrice == PRICE_MEDIAN  ? "Median Price" :
                     BollingerBands_AppliedPrice == PRICE_TYPICAL ? "Typical Price" :
                     BollingerBands_AppliedPrice == PRICE_WEIGHTED? "Weighted Price" : "Unknown Price Type";


   cSTOMethod = Stochastic_Method == MODE_SMA  ? "Simple Moving Average (SMA)" :
                Stochastic_Method == MODE_EMA  ? "Exponential Moving Average (EMA)" :
                Stochastic_Method == MODE_SMMA ? "Smoothed Moving Average (SMMA)" :
                Stochastic_Method == MODE_LWMA ? "Linear Weighted Moving Average (LWMA)" : "Unknown MA Method";

   cSTOPriceField = Stochastic_PriceField == 0 ? "Low/High" :
                    Stochastic_PriceField == 1 ? "Close/Close" : "Unknown Mode";

   cMAMethod = MovingAverage_Method == MODE_SMA  ? "Simple Moving Average (SMA)" :
               MovingAverage_Method == MODE_EMA  ? "Exponential Moving Average (EMA)" :
               MovingAverage_Method == MODE_SMMA ? "Smoothed Moving Average (SMMA)" :
               MovingAverage_Method == MODE_LWMA ? "Linear Weighted Moving Average (LWMA)" : "Unknown MA Method";

   cTradeDirection = TradeDirection == Trend ? "Trend" : "CounterTrend";
   cSignalStrength = SignalStrength == SingleTF ? "Single TimeFrame" : "MultiTimeFrame";
   cPeriodM1 = PeriodM1 ? "Active" : "Inactive";
   cPeriodM5 = PeriodM5 ? "Active" : "Inactive";
   cPeriodM15 = PeriodM15 ? "Active" : "Inactive";
   cPeriodM30 = PeriodM30 ? "Active" : "Inactive";
   cPeriodH1 = PeriodH1 ? "Active" : "Inactive";
   cPeriodH4 = PeriodH4 ? "Active" : "Inactive";
   cPeriodD1 = PeriodD1 ? "Active" : "Inactive";
   cRSI = RSI ? "Active" : "Inactive";
   cStochastic = Stochastic ? "Active" : "Inactive";
   cBollingerBands = BollingerBands ? "Active" : "Inactive";
   cMovingAverage = MovingAverage ? "Active" : "Inactive";
   cLotMode = LotMode == Lot_Percentage ? "Percentage" : "Random";
   cNewsStatus = NewsManagement == NewsDeactivated ? "Inactive" : NewsManagement == HighImpactNews ? "High Impact News" : "Important News";
   cMMAction = MoneyManagement_Action == Stop_EA ? "Stop EA Once it fullied Money Management" : "Close Existing Trade & Continue with new Trades";
   cRMAction = RiskManagement_Action == StopEA ? "Stop EA Once Hit Risk Management" : "Close Existing Trade & Continue with new Trades";
   cMMType = MoneyManagement_Type == Fixed_Money ? "Fixed Money" : "Balance Percentage";
   cRiskType = Risk_In_Money_Type == FixedMoney ? "Fixed Money" : "Balance Percentage";
   DemoRealCheck = IsDemo() ? "Demo" : "Real";
   cLotPercentage = LotMode == Lot_Percentage ? " => " + LotPercentage + "%" : "";
   cTradeMode = TradeMode ? "Active" : "Inactive";
   cTakeProfitType = TakeProfit_Type == Classic_TP ? "Classic Take Profit" : "Virtual Take Profit";
   cStopLossType = StopLoss_Type == Classic_SL ? "Classic Stop Loss" : "Virtual Stop Loss";
   cTrailingType = Trailing_Type == Classic_Trailing ? "Classing Trailing Stop" : "Virtual Trailing Stop";

//+------------------------------------------------------------------+
//| News Filter Start                                                |
//+------------------------------------------------------------------+
   gAvgChartPrice = (WindowPriceMax() + WindowPriceMin()) / 2; // Chart Update
//--- get today time
   TimeOfDay=(int)TimeLocal()%86400;
   Midnight=TimeLocal()-TimeOfDay;
//--- set xml file name ffcal_week_this (fixed name)
   xmlFileName=INAME+"-WeeklyNews.xml";
//--- checks the existence of the file.
   if(!FileIsExist(xmlFileName))
     {
      xmlDownload();
      xmlRead();
      //Print("XML File downloaded");
     }
//--- else just read it
   else
     {
      xmlRead();
      //Print("Ordered to Reading XML News");
     }
//--- get last modification time
   xmlModifed=(datetime)FileGetInteger(xmlFileName,FILE_MODIFY_DATE,false);
//--- check for updates
   if(FileIsExist(xmlFileName))
     {
      if(xmlModifed<TimeLocal()-(60*60))
        {
         //Print(INAME+": xml file is out of date - Updating");
         xmlUpdate();
        }
      //--- set timer to update old xml file every x hours
      EventSetTimer(60*60);
     }

   assignVal=true;
//+------------------------------------------------------------------+
//| News Filter End                                                  |
//+------------------------------------------------------------------+

   return(INIT_SUCCEEDED);
  }


//+------------------------------------------------------------------+
//| On Deinit                                                        |
//+------------------------------------------------------------------+
int deinit()
  {
   ObjectsDeleteAll(0,"#",-1,-1);
   ObjectsDeleteAll(0,"Tr_",-1,-1);
   ObjectsDeleteAll(0,"NFtext_",-1,-1);
   return (0);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
//Pre-defined OnTick Value
   MathSrand(GetTickCount());
   BuySellRandomMath = MathRand() % 4;
   gRandomSymbol = (SignalStrength != SingleTF) ? randomsymbol() : (gTimeFrameIndexForSymbol == 0) ? randomsymbol() : gRandomSymbol; //Random Symbol
   gBuySymbol = GetAllOpenTradeSymbols(gBuyMagic, OP_BUY); //BUY Symbol
   gSellSymbol = GetAllOpenTradeSymbols(gSellMagic, OP_SELL); //Sell Symbol
   if(IsTesting()) //For Tester Mode
      gRandomSymbol = _Symbol;
   gRandomLotSize = LotValue();
   rBID = MarketInfo(gRandomSymbol, MODE_BID);
   rASK = MarketInfo(gRandomSymbol, MODE_ASK);
   bBID = MarketInfo(gBuySymbol, MODE_BID);
//bASK = MarketInfo(gBuySymbol, MODE_ASK);
//sBID = MarketInfo(gSellSymbol, MODE_BID);
   sASK = MarketInfo(gSellSymbol, MODE_ASK);
   rPoint = MarketInfo(gRandomSymbol, MODE_POINT);
   bPoint = MarketInfo(gBuySymbol, MODE_POINT);
   sPoint = MarketInfo(gSellSymbol, MODE_POINT);
   gRandomSpread = MarketInfo(gRandomSymbol, MODE_SPREAD);
   gBuySpread = MarketInfo(gBuySymbol, MODE_SPREAD);
   gSellSpread = MarketInfo(gSellSymbol, MODE_SPREAD);
   OrderCount_BuyMagicOPBUY = trade_count_ordertype(OP_BUY, gBuyMagic);
   OrderCount_SellMagicOPSELL = trade_count_ordertype(OP_SELL, gSellMagic);
   OrderCount_Symbol_OPBUY = TradeCountBySymbol(OP_BUY, gBuyMagic, gRandomSymbol);
   OrderCount_Symbol_OPSELL = TradeCountBySymbol(OP_SELL, gSellMagic, gRandomSymbol);


//Calculating P/L
   gBuyPL = CalculateTradeFloating(gBuyMagic);
   gSellPL = CalculateTradeFloating(gSellMagic);
   gSymbolEA_FloatingPL =  gBuyPL + gSellPL ;

//Calculating Lot size
   gBuyOpenLot = TotalOpenLot(gBuyMagic);
   gSellOpenLot = TotalOpenLot(gSellMagic);
   gTotalOpenLot = gBuyOpenLot + gSellOpenLot;

//Calculating Total Orders
   gBuyTotalOrder = trades_count(gBuyMagic);
   gSellTotalOrder = trades_count(gSellMagic);
   gTotalOpenOrder = gBuyTotalOrder + gSellTotalOrder;

//Signals
   if(ShowIndicatorStatus)
      SignalStatus();
   else
      cIndicatorStaus = "";
   if(SignalStrength == MultiTF)
      MultiTF_IndicatorPossibilities();
   else
      SingleTimeFrame();

//Trailing TP
   if(Trailing_Gap > 0 && Trailing_Start > 0)
     {
      if(Trailing_Type == Classic_Trailing)
         TrailingStopLoss();
      else
         VirtualTrailingStopLoss();
     }

//Virtual Take Profit
   if(TakeProfit_Type == Virtual_TP && TakeProfit > 0)
      VirtualTakeProfit();

//Virtual StopLoss
   if(StopLoss_Type == Virtual_SL && StopLoss > 0)
      VirtualStopLoss();

//Candle Exit
   if(CandleExit > 0)
      CandleClose();

//Risk In Money
   if(Risk_In_Money_Type == BalancePercentage)
      gRisk_Money =(-1.0 * AccountBalance() * (Money_In_Risk * 0.01));
   else
      gRisk_Money = (-1.0 * Money_In_Risk);

   if(gSymbolEA_FloatingPL <= gRisk_Money)
     {
      CloseOpenAndPendingTrades(gBuyMagic);
      CloseOpenAndPendingTrades(gSellMagic);

      if(RiskManagement_Action == StopEA)
        {
         TradeMode = FALSE;
         Print("EA is Stopped => Hitted Risk Management");
        }

      if(MoneyManagement_Type == Balance_Percentage)
         gTargeted_Revenue = (1 + Target_Revenue/100) * AccountBalance();
      else
         gTargeted_Revenue = Target_Revenue + AccountBalance();

      Print("Risk Management => Successfully Closed");
     }

//Money Management
   if(gTargeted_Revenue > 0 && AccountEquity() >= gTargeted_Revenue)
     {
      CloseOpenAndPendingTrades(gBuyMagic);
      CloseOpenAndPendingTrades(gSellMagic);;

      if(MoneyManagement_Action == Stop_EA)
        {
         TradeMode = FALSE;
         Print("EA is Stopped => Fullied Money Management");
        }

      if(MoneyManagement_Type == Balance_Percentage)
         gTargeted_Revenue = (1 + Target_Revenue/100) * AccountBalance();
      else
         gTargeted_Revenue = Target_Revenue + AccountBalance();

      Print("Money Management => Closed Trade & Redefined Target Revenue");
     }

//NewsFilter Status
   if(NewsManagement != NewsDeactivated && UpcomingNewsImpact(gRandomSymbol,0) == 2)
      gUpcomingImpact = TRUE;
   else
      gUpcomingImpact = FALSE;

//Order Placement
   if((OrderCount_BuyMagicOPBUY + OrderCount_SellMagicOPSELL) < MaxOpenTrade && gRandomSpread < maxSpread && !gUpcomingImpact && TradeMode)
     {
      NewOrderSend();
      cTradeMode = "Active => Looking for signal";
     }
   else
     {
      if(!TradeMode)
         cTradeMode = "Paused => Enable in EA Settings";
      if(gUpcomingImpact)
         cTradeMode = "Paused => it News time";
      if((OrderCount_BuyMagicOPBUY + OrderCount_SellMagicOPSELL) > MaxOpenTrade)
         cTradeMode = "Paused => Maxium Open Trade Reached";
      if(gRandomSpread > maxSpread)
         cTradeMode = "Paused => Spread is too high";
     }

//News CutLoss
   if(gUpcomingImpact && gSymbolEA_FloatingPL >= -News_CutLoss && gSymbolEA_FloatingPL <= News_CutLoss && gSymbolEA_FloatingPL != 0)
     {
      CloseOpenAndPendingTrades(gBuyMagic);
      CloseOpenAndPendingTrades(gSellMagic);
      Print("News Time Closing : Closed All the trade ");
     }

   ChartComment(); //Chart Comment to show details
// --------- OnTick End ------------ //
  }

//+------------------------------------------------------------------+
//|                  OnTimer                                         |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
   assignVal=true;
//Print(INAME+": xml file is out of date");
   xmlUpdate();
//---
  }

//+------------------------------------------------------------------+
//| Doube Side Buy And Sell Order                                    |
//+------------------------------------------------------------------+
void NewOrderSend()
  {
   int iStopLevel = MarketInfo(gRandomSymbol, MODE_STOPLEVEL) < gRandomSpread ? gRandomSpread + 2 : MarketInfo(gRandomSymbol, MODE_STOPLEVEL) + 2;
   string iNewTrade = "None";

   if(!Inverse)
     {
      if((TradeDirection == Trend && (gSingleTimeFrameSignalStatus == "ABOVE" || gMultiTimeFrameSignalStatus == "ABOVE")) || (TradeDirection == CounterTrend && (gSingleTimeFrameSignalStatus == "BELOW" || gMultiTimeFrameSignalStatus == "BELOW")))
         iNewTrade = "BUY";
      if((TradeDirection == CounterTrend && (gSingleTimeFrameSignalStatus == "ABOVE" || gMultiTimeFrameSignalStatus == "ABOVE")) || (TradeDirection == Trend && (gSingleTimeFrameSignalStatus == "BELOW" || gMultiTimeFrameSignalStatus == "BELOW")))
         iNewTrade = "SELL";
     }
   else
     {
      if((TradeDirection == Trend && (gSingleTimeFrameSignalStatus == "ABOVE" || gMultiTimeFrameSignalStatus == "ABOVE")) || (TradeDirection == CounterTrend && (gSingleTimeFrameSignalStatus == "BELOW" || gMultiTimeFrameSignalStatus == "BELOW")))
         iNewTrade = "SELL";
      if((TradeDirection == CounterTrend && (gSingleTimeFrameSignalStatus == "ABOVE" || gMultiTimeFrameSignalStatus == "ABOVE")) || (TradeDirection == Trend && (gSingleTimeFrameSignalStatus == "BELOW" || gMultiTimeFrameSignalStatus == "BELOW")))
         iNewTrade = "BUY";
     }

   if(OrderCount_Symbol_OPBUY == 0 && CheckMoneyForTrade(gRandomSymbol, gRandomLotSize, OP_BUY) && iNewTrade == "BUY")
     {
      OrderSend_StopLoss = (StopLoss > 0 && StopLoss_Type == Classic_SL) ? rASK - MathMax(StopLoss, iStopLevel+2) * rPoint : 0;
      OrderSend_TakeProfit = (TakeProfit > 0 && TakeProfit_Type == Classic_TP) ? rASK + MathMax(TakeProfit, iStopLevel+2) * rPoint : 0;
      ResetLastError();
      if(OrderSend(gRandomSymbol, OP_BUY, gRandomLotSize, rASK, Slippage, OrderSend_StopLoss, OrderSend_TakeProfit, gTradeComment, gBuyMagic, 0, clrNONE) == -1)
         Print(gRandomSymbol + " >> Buy Order => Error Code : " + GetLastError());
     }

   if(OrderCount_Symbol_OPSELL == 0 && CheckMoneyForTrade(gRandomSymbol, gRandomLotSize, OP_SELL) && iNewTrade == "SELL")
     {
      OrderSend_StopLoss = (StopLoss > 0 && StopLoss_Type == Classic_SL) ? rBID + MathMax(StopLoss, iStopLevel+2) * rPoint : 0;
      OrderSend_TakeProfit = (TakeProfit > 0 && TakeProfit_Type == Classic_TP) ? rBID - MathMax(TakeProfit, iStopLevel+2) * rPoint : 0;
      ResetLastError();
      if(OrderSend(gRandomSymbol, OP_SELL, gRandomLotSize, rBID, Slippage, OrderSend_StopLoss, OrderSend_TakeProfit, gTradeComment, gSellMagic, 0, clrNONE) == -1)
         Print(gRandomSymbol + " >> Sell Order => Error Code : " + GetLastError());
     }
  }

// Calculate Trade profits and Loss
double CalculateTradeFloating(int CalculateTradeFloating_Magic)
  {
   double CalculateTradeFloating_Value = 0;
   for(int CalculateTradeFloating_i = 0; CalculateTradeFloating_i < OrdersTotal(); CalculateTradeFloating_i++)
     {
      OrderSelect(CalculateTradeFloating_i, SELECT_BY_POS, MODE_TRADES);
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(CalculateTradeFloating_Magic == OrderMagicNumber())
         CalculateTradeFloating_Value += OrderProfit() + OrderSwap() + OrderCommission();
     }
   return CalculateTradeFloating_Value;
  }

//+------------------------------------------------------------------+
//|       Total Open Lot                                             |
//+------------------------------------------------------------------+
double TotalOpenLot(int TotalOpenLot_Magic)
  {
   double TotalOpenLot_Value = 0;
   for(int TotalOpenLot_i = 0; TotalOpenLot_i < OrdersTotal(); TotalOpenLot_i++)
     {
      OrderSelect(TotalOpenLot_i, SELECT_BY_POS, MODE_TRADES);
      if((OrderType() != OP_BUY && OrderType() != OP_SELL))
         continue;
      if(TotalOpenLot_Magic == OrderMagicNumber())
         TotalOpenLot_Value += OrderLots();
     }
   return TotalOpenLot_Value;
  }


//+------------------------------------------------------------------+
//|      Trade Count                                                 |
//+------------------------------------------------------------------+
int trades_count(int trade_count_magic)
  {
   int count_0 = 0;
   for(int pos_4 = 0; pos_4 < OrdersTotal(); pos_4++)
     {
      OrderSelect(pos_4, SELECT_BY_POS, MODE_TRADES);
      if(OrderMagicNumber() != trade_count_magic)
         continue;
      count_0++;
     }
   return count_0;
  }

// Trade closing based on Magic number
void CloseOpenAndPendingTrades(int trade_close_magic)
  {
   for(int pos_0 = OrdersTotal() - 1; pos_0 >= 0; pos_0--)
     {
      OrderSelect(pos_0, SELECT_BY_POS, MODE_TRADES);
      if(OrderMagicNumber() != trade_close_magic)
         continue;

      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
        {
         ResetLastError();
         if(!OrderDelete(OrderTicket()))
            Print(__FUNCTION__ " => Pending Order failed to close, error code:", GetLastError());
        }
      else
        {
         ResetLastError();
         if(OrderType() == OP_BUY)
           {
            if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), Slippage, clrNONE))
               Print(__FUNCTION__ " => Buy Order failed to close, error code:", GetLastError());
           }
         if(OrderType() == OP_SELL)
           {
            if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), Slippage, clrNONE))
               Print(__FUNCTION__ " => Sell Order failed to close, error code:", GetLastError());
           }
        }
     }
  }


// Trade Counting based on Order Type and Magic Number
int trade_count_ordertype(int trade_count_ordertype_value, int trade_count_ordertype_magic)
  {
   int count_4 = 0;
   for(int pos_8 = 0; pos_8 < OrdersTotal(); pos_8++)
     {
      OrderSelect(pos_8, SELECT_BY_POS, MODE_TRADES);
      if(OrderMagicNumber() != trade_count_ordertype_magic)
         continue;
      if(trade_count_ordertype_value == OrderType())
         count_4++;
     }
   return count_4;
  }

//+------------------------------------------------------------------+
//|      Trade Count Symbol                                          |
//+------------------------------------------------------------------+
int TradeCountBySymbol(int trade_count_ordertype_value, int trade_count_ordertype_magic, string TradeOrderSymbolCount)
  {
   int count_4 = 0;
   for(int pos_8 = 0; pos_8 < OrdersTotal(); pos_8++)
     {
      if(OrderSelect(pos_8, SELECT_BY_POS, MODE_TRADES)) // Ensure order selection is successful
        {
         if(OrderMagicNumber() == trade_count_ordertype_magic && OrderSymbol() == TradeOrderSymbolCount && trade_count_ordertype_value == OrderType())
            count_4++;
        }
     }
   return count_4;
  }

// Chart Comment Status
void ChartComment()
  {
   string c_Risk_Type, c_mm_Type;

   if(Risk_In_Money_Type == BalancePercentage)
      c_Risk_Type = "(Percentage : " + Money_In_Risk + "% ) => (Money In Risk : " + -1 * gRisk_Money + ")";
   else
      c_Risk_Type = "(Money In Risk : " + -1 * gRisk_Money + ")";

   if(MoneyManagement_Type == Balance_Percentage)
      c_mm_Type = "(Percentage : " + Target_Revenue + "% ) => (Target Revenue : " + gTargeted_Revenue + ")";
   else
      c_mm_Type = "(Target Revenue = " + Target_Revenue + " : " + gTargeted_Revenue + ")";


   Comment("                                               ---------------------------------------------"
           "\n                                             :: ===>RRS Fortune EA<==="
           "\n                                             ------------------------------------------------" +
           "\n                                             :: Currency Pair                  : (Checking : " + gRandomSymbol + ") |:| (Buy Operational : " + gBuySymbol + ") |:| (Sell Operational : " + gSellSymbol + ")" +
           "\n                                             :: " + gRandomSymbol + " Info                  : (Spread : " + gRandomSpread + ") |:| (Stop Level : " + MarketInfo(gRandomSymbol, MODE_STOPLEVEL) + ") |:| (Freeze Level : " + MarketInfo(gRandomSymbol, MODE_FREEZELEVEL) + ") |:| (Leverage : 1:" + IntegerToString(AccountLeverage()) + ") |:| (Account Type : " + DemoRealCheck + ")" +
           "\n                                             :: EA Floating P/L              : " + gSymbolEA_FloatingPL + " ==> Buy (" + gBuyPL + ") + Sell (" + gSellPL + ")" +
           "\n                                             :: EA Open Lot                  : " + gTotalOpenLot + " ==> Buy (" + gBuyOpenLot + ") + Sell (" + gSellOpenLot + ")" +
           "\n                                             :: EA Total Trade              : " + gTotalOpenOrder + " ==> Buy (" + gBuyTotalOrder + ") + Sell (" + gSellTotalOrder + ")" +
           "\n                                             ------------------------------------------------" +
           "\n                                             :: Trade Mode                     : " + cTradeMode +
           "\n                                             :: Trade Direction                : " + cTradeDirection +
           "\n                                             :: Signal Strength                : " + cSignalStrength +
           "\n                                             :: Indicator                         : (RSI : " + cRSI + ") |:| (Stochastic : " + cStochastic + ") |:| (Bollinger Bands : " + cBollingerBands + ") |:| (Moving Average : " + cMovingAverage + ")" +
           "\n                                             :: TimeFrame                       : (M1 : " + cPeriodM1 + ") |:| (M5 : " + cPeriodM5 + ") |:| (M15 : " + cPeriodM15 + ") |:| (M30 : " + cPeriodM30 + ") |:| (H1 : " + cPeriodH1 + ") |:| (H4 : " + cPeriodH4 + ") |:| (D1 : " + cPeriodD1 + ") |:| (Checking TF : " + gSingleTFCheckingStatus + ")" +
           "\n                                             :: News   			                        : (Status : " + cNewsStatus + ") |:| (Pause Before : " + BeforeNews_Minutes + ") |:| (Pause After : " + AfterNews_Minutes + ") |:| (CutLoss : " + News_CutLoss + ") |:| (ReCheck Minitues: " + News_ReCheckMinutes + ") |:| (Last Download : " + XMLDownloadTime + ") |:| (Last Read : " + XMLReadTime + ") |:| (Last Updated : " + XMLUpdateTime + ") |:| (Last Checked : " + XMLUpcomingImpact + ") |:| (nfs.faireconomy.media : " + NewsURLChecking + ")" +
           "\n                                             ------------------------------------------------" +
           "\n                                             :: Candle Exit                      : " + CandleExit + 
           "\n                                             :: Take Profit                      : " + TakeProfit + " (Type : " + cTakeProfitType + ")" +
           "\n                                             :: Stop Loss                      : " + StopLoss + " (Type : " + cStopLossType + ")" +
           "\n                                             :: Trailing                          : (Start : " + Trailing_Start + ") |:| (Gap : " + Trailing_Gap + ") |:| (Type : " + cTrailingType + ")" +
           "\n                                             :: Lot Size                         : (Mode : " + cLotMode + cLotPercentage + ") |:| (Min Lot : " + minLot_Size + ") |:| (Max Lot : " + maxLot_Size + ") |:| (Lot : " + gRandomLotSize + ")" +
           "\n                                             :: Restrication                   : (Maximum Open Trade : " + MaxOpenTrade + ") |:| (Maximum Spread : " + maxSpread + ") |:| (Slippage : " + Slippage + ")" +
           "\n                                             :: Risk Management          : (Type : " + cRiskType + ") |:| (Action : " + cRMAction + ") |:| "  + c_Risk_Type  +
           "\n                                             :: Money Management      : (Type : " + cMMType + ") |:| (Action : " + cMMAction + ") |:| " + c_mm_Type +
           "\n                                             ------------------------------------------------" +
           "\n                                             :: RSI                             : (Applied Price : " + cRSIAppliedPrice + ") |:| (Period : " + RSI_Period + ") |:| (Shift : " + RSI_shift + ") |:| (UP Level : " + RSI_UpLevel + ") |:| (Below Level : " + RSI_BelowLevel + ")" +
           "\n                                             :: Stochastic                     : (Method : " + cSTOMethod + ") |:| (Kperiod : " + Stochastic_Kperiod + ") |:| (Dperiod : " + Stochastic_Dperiod + ") |:| (Slowing : " + Stochastic_Slowing + ") |:| (Price Field : " + cSTOPriceField + ") |:| (Shift : " + Stochastic_Shift + ") |:| (UP Level : " + Stochastic_UpLevel + ") |:| (Below Level : " + Stochastic_BelowLevel + ")" +
           "\n                                             :: Moving Average            : (Period : " + MovingAverage_Period + ") |:| (MA Shift : " + MovingAverage_MAShift + ") |:| (Method : " + cMAMethod + ") |:| (Applied Price : " + MovingAverage_AppliedPrice + ") |:| (Shift : " + MovingAverage_Shift + ")" +
           "\n                                             :: Bollinger Bands              : (Applied Price : " + cBBAppliedPrice + ") |:| (Period : " + BollingerBands_Period + ") |:| (Deviation : " + BollingerBands_deviation + ") |:| (Band Shift : " + BollingerBands_BandShift + ") |:| (Shift : " + BollingerBands_Shift + ")" +
           cIndicatorStaus +
           "\n                                             ------------------------------------------------" +
           "\n                                             :: Magic Number               : " + Magic + " => (Buy Magic : " + gBuyMagic + ") |:| (Sell Magic : " + gSellMagic + ")" +
           "\n                                             :: Timezone                      : (Local PC : " + localHours + ":" + localMinutes + ")" + " |:| (Broker Timezone : " + brokerHours + ":" + brokerMinutes + ")" +
           "\n                                             :: Notes                           : " + EA_Notes +
           "\n                                             ------------------------------------------------" +
           "\n                                             :: Email                           : rajeeevrrs@gmail.com " +
           "\n                                             :: Telegram                     : @rajeevrrs " +
           "\n                                             :: Skype                         : rajeev-rrs " +
           "\n                                             ------------------------------------------------");
  }

//+--------------------------------------------------------------------+
// Trailing SL                                                         +
//+--------------------------------------------------------------------+
void TrailingStopLoss()
  {
// Loop through all open orders
   double TrailingStopLoss_entryPrice;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         TrailingStopLoss_entryPrice = OrderOpenPrice();
         if(OrderMagicNumber() == gBuyMagic && OrderType() == OP_BUY && OrderSymbol() == gBuySymbol)
           {
            int BuyTrailingGap = MathMax(MathMax(MarketInfo(gBuySymbol, MODE_STOPLEVEL) + 2, gBuySpread + 2), Trailing_Gap);
            if(bBID - (TrailingStopLoss_entryPrice + Trailing_Start * bPoint) > bPoint * BuyTrailingGap)
              {
               if(OrderStopLoss() < bBID - bPoint * BuyTrailingGap || OrderStopLoss() == 0)
                 {
                  ResetLastError();
                  RefreshRates();
                  if(!OrderModify(OrderTicket(), OrderOpenPrice(), bBID - bPoint * BuyTrailingGap, OrderTakeProfit(), 0, clrNONE))
                     Print(__FUNCTION__ + " => " + gBuySymbol + " : Buy Order Error Code : " + GetLastError());
                 }
              }
           }

         if(OrderMagicNumber() == gSellMagic && OrderType() == OP_SELL && OrderSymbol() == gSellSymbol)
           {
            int SellTrailingGap = MathMax(MathMax(MarketInfo(gSellSymbol, MODE_STOPLEVEL) + 2, gSellSpread + 2), Trailing_Gap);
            if((TrailingStopLoss_entryPrice - Trailing_Start * sPoint) - sASK > sPoint * SellTrailingGap)
              {
               if(OrderStopLoss() > sASK + sPoint * SellTrailingGap || OrderStopLoss() == 0)
                 {
                  ResetLastError();
                  RefreshRates();
                  if(!OrderModify(OrderTicket(), OrderOpenPrice(), sASK + sPoint * SellTrailingGap, OrderTakeProfit(), 0, clrNONE))
                     Print(__FUNCTION__ + " => " + gSellSymbol + " : Sell Order Error Code : " + GetLastError());
                 }
              }
           }
        }
     }
  }


//+------------------------------------------------------------------+
//|    Check Balance and Margin                                      |
//+------------------------------------------------------------------+
bool CheckMoneyForTrade(string symb, double lots,int type)
  {
   double free_margin=AccountFreeMarginCheck(symb,type, lots);
//-- if there is not enough money
   if(free_margin<0)
     {
      Print("Not enough money to trade");
      return(false);
     }
//--- checking successful
   return(true);
  }
//+------------------------------------------------------------------+
//|  Random Symbol                                                   |
//+------------------------------------------------------------------+
string randomsymbol()
  {
   string randomsymbol_pairs[];
   int count = StringSplit(Trade_Currencies, ',', randomsymbol_pairs);

   int totalSymbols = SymbolsTotal(true);  // Include all Market Watch symbols
   string validSymbols[];

   for(int i = 0; i < totalSymbols; i++)
     {
      string symbolName = SymbolName(i, true);
      bool found = false;

      // Check if the symbol contains a valid pair
      for(int j = 0; j < count; j++)
        {
         for(int k = 0; k < count; k++)
           {
            if(j != k)  // Prevent matching same symbols (e.g., USDUSD)
              {
               if(StringFind(symbolName, randomsymbol_pairs[j]) != -1 &&
                  StringFind(symbolName, randomsymbol_pairs[k]) != -1)
                 {
                  found = true;
                  break;  // Break inner loop if a match is found
                 }
              }
           }
         if(found)
            break;  // Exit outer loop to avoid duplicate addition
        }

      // Add only if not already in the list
      if(found)
        {
         bool alreadyAdded = false;
         for(int m = 0; m < ArraySize(validSymbols); m++)
           {
            if(validSymbols[m] == symbolName)
              {
               alreadyAdded = true;
               break;
              }
           }

         if(!alreadyAdded)
           {
            ArrayResize(validSymbols, ArraySize(validSymbols) + 1);
            validSymbols[ArraySize(validSymbols) - 1] = symbolName;
           }
        }
     }

   if(ArraySize(validSymbols) > 0)
     {
      gSymbolRandomIndex = gSymbolRandomIndex < ArraySize(validSymbols) ? gSymbolRandomIndex : 0;
      string SelectedAssetSymbol = validSymbols[gSymbolRandomIndex];
      gSymbolRandomIndex++;
      return SelectedAssetSymbol;
     }
   return ""; // Return empty if no valid symbol found
  }


//+------------------------------------------------------------------+
//|   Get Open Trade Symbol by Magic                                 |
//+------------------------------------------------------------------+
string GetAllOpenTradeSymbols(int OrderMagicNumberr, int OrderTypee)
  {
   string GetAllOpenTradeSymbols_symbols = "";
   string GetAllOpenTradeSymbols_symbolsArray[];
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))  // Select order
        {
         if(OrderMagicNumber() == OrderMagicNumberr && OrderType() == OrderTypee)
           {
            string GetAllOpenTradeSymbols_symbol = OrderSymbol();
            if(StringFind(GetAllOpenTradeSymbols_symbols, GetAllOpenTradeSymbols_symbol) == -1)  // Check if symbol is already added
              {
               ArrayResize(GetAllOpenTradeSymbols_symbolsArray, ArraySize(GetAllOpenTradeSymbols_symbolsArray) + 1);
               GetAllOpenTradeSymbols_symbolsArray[ArraySize(GetAllOpenTradeSymbols_symbolsArray) - 1] = OrderSymbol();
              }
           }
        }
     }
// Return a random symbol from the valid list
   if(ArraySize(GetAllOpenTradeSymbols_symbolsArray) > 0)
     {
      gSymbolIndex = gSymbolIndex < ArraySize(GetAllOpenTradeSymbols_symbolsArray) ? gSymbolIndex : 0;
      string SelectedOpenSymbol = GetAllOpenTradeSymbols_symbolsArray[gSymbolIndex];
      gSymbolIndex++;
      return SelectedOpenSymbol;
     }
   return "";
  }

//+------------------------------------------------------------------+
//|        Random Lot size                                           |
//+------------------------------------------------------------------+
double LotValue()
  {
// Retrieve lot constraints
   double LotValue;
   double minLot  = MarketInfo(gRandomSymbol, MODE_MINLOT);
   double maxLot  = MarketInfo(gRandomSymbol, MODE_MAXLOT);
   double lotStep = MarketInfo(gRandomSymbol, MODE_LOTSTEP);

// Ensure lotStep is valid
   if(lotStep <= 0)
      lotStep = 0.01; // Default to a small valid step

// Generate a random value within the specified range
   if(LotMode == Lot_Percentage)
     {
      LotValue = NormalizeDouble((MathMin(AccountBalance(), AccountEquity()) / MarketInfo(gRandomSymbol, MODE_MARGINREQUIRED)) * (LotPercentage * 0.01), 2) ;
      if(LotValue < minLot_Size)
         LotValue = minLot_Size;
      if(LotValue > maxLot_Size)
         LotValue = maxLot_Size;
     }
   else
      LotValue = minLot_Size + (maxLot_Size - minLot_Size) * MathRand() / 32767.0;

// Adjust to the nearest lot step
   LotValue = minLot + lotStep * MathRound((LotValue - minLot) / lotStep);

// Final check to ensure it remains within bounds
   LotValue = MathMax(minLot, MathMin(LotValue, maxLot));

// Normalize to 2 decimal places
   return NormalizeDouble(LotValue, 2);
  }

//+------------------------------------------------------------------+
//|    Indicator Possibilities                                       |
//+------------------------------------------------------------------+
void MultiTF_IndicatorPossibilities()
  {
   gRSISignal = "NoSignal";
   gStochasticSignal = "NoSignal";
   gBollingerBandsSignal = "NoSignal";
   gMovingAverageSignal = "NoSignal";

   ENUM_TIMEFRAMES periods[7];
   int count = 0;

   if(PeriodM1)
      periods[count++] = PERIOD_M1;
   if(PeriodM5)
      periods[count++] = PERIOD_M5;
   if(PeriodM15)
      periods[count++] = PERIOD_M15;
   if(PeriodM30)
      periods[count++] = PERIOD_M30;
   if(PeriodH1)
      periods[count++] = PERIOD_H1;
   if(PeriodH4)
      periods[count++] = PERIOD_H4;
   if(PeriodD1)
      periods[count++] = PERIOD_D1;

   if(count == 0)
      return;  // Exit if no timeframes are selected

   bool rsiUp = true, rsiDown = true;
   bool stoUp = true, stoDown = true;
   bool bbUp = true, bbDown = true;
   bool maUp = true, maDown = true;

   for(int i = 0; i < count; i++)
     {
      ENUM_TIMEFRAMES tf = periods[i];

      if(RSI)
        {
         double rsiValue = iRSI(gRandomSymbol, tf, RSI_Period, RSI_AppliedPrice, RSI_shift);
         if(rsiValue <= RSI_UpLevel)
            rsiUp = false;
         if(rsiValue >= RSI_BelowLevel)
            rsiDown = false;
        }

      if(Stochastic)
        {
         double mainValue = iStochastic(gRandomSymbol, tf, Stochastic_Kperiod, Stochastic_Dperiod,
                                        Stochastic_Slowing, Stochastic_Method, Stochastic_PriceField, MODE_MAIN, Stochastic_Shift);
         double signalValue = iStochastic(gRandomSymbol, tf, Stochastic_Kperiod, Stochastic_Dperiod,
                                          Stochastic_Slowing, Stochastic_Method, Stochastic_PriceField, MODE_SIGNAL, Stochastic_Shift);
         if(mainValue <= Stochastic_UpLevel || signalValue <= Stochastic_UpLevel)
            stoUp = false;
         if(mainValue >= Stochastic_BelowLevel || signalValue >= Stochastic_BelowLevel)
            stoDown = false;
        }

      if(BollingerBands)
        {
         double upperBand = iBands(gRandomSymbol, tf, BollingerBands_Period, BollingerBands_deviation,
                                   BollingerBands_BandShift, BollingerBands_AppliedPrice, MODE_UPPER, BollingerBands_Shift);
         double lowerBand = iBands(gRandomSymbol, tf, BollingerBands_Period, BollingerBands_deviation,
                                   BollingerBands_BandShift, BollingerBands_AppliedPrice, MODE_LOWER, BollingerBands_Shift);
         if(rBID <= upperBand)
            bbUp = false;
         if(rASK >= lowerBand)
            bbDown = false;
        }

      if(MovingAverage)
        {
         double MA_Value = iMA(gRandomSymbol, tf, MovingAverage_Period, MovingAverage_MAShift, MovingAverage_Method, MovingAverage_AppliedPrice, MovingAverage_Shift);
         if(rBID <= MA_Value)
            maUp = false;
         if(rASK >= MA_Value)
            maDown = false;
        }
     }

   if(RSI)
     {
      if(rsiUp)
         gRSISignal = "ABOVE";
      else
         if(rsiDown)
            gRSISignal = "BELOW";
     }
   if(Stochastic)
     {
      if(stoUp)
         gStochasticSignal = "ABOVE";
      else
         if(stoDown)
            gStochasticSignal = "BELOW";
     }
   if(BollingerBands)
     {
      if(bbUp)
         gBollingerBandsSignal = "ABOVE";
      else
         if(bbDown)
            gBollingerBandsSignal = "BELOW";
     }
   if(MovingAverage)
     {
      if(TradeDirection == Trend)
        {
         if(maUp)
            gMovingAverageSignal = "ABOVE";
         else
            if(maDown)
               gMovingAverageSignal = "BELOW";
        }
      else
         if(TradeDirection == CounterTrend)
           {
            if(maUp)
               gMovingAverageSignal = "BELOW";
            else
               if(maDown)
                  gMovingAverageSignal = "ABOVE";
           }
     }

   gMultiTimeFrameSignalStatus = "NoSignal";
   string signals[4];
   count = 0;

   if(RSI)
      signals[count++] = gRSISignal;
   if(Stochastic)
      signals[count++] = gStochasticSignal;
   if(BollingerBands)
      signals[count++] = gBollingerBandsSignal;
   if(MovingAverage)
      signals[count++] = gMovingAverageSignal;

   if(count == 0)
      return;

   bool allABOVE = true, allBELOW = true;
   for(int j = 0; j < count && (allABOVE || allBELOW); j++)
     {
      if(signals[j] != "ABOVE")
         allABOVE = false;
      if(signals[j] != "BELOW")
         allBELOW = false;
     }

   if(allABOVE)
      gMultiTimeFrameSignalStatus = "ABOVE";
   else
      if(allBELOW)
         gMultiTimeFrameSignalStatus = "BELOW";
  }

//+------------------------------------------------------------------+
//|   Single Timeframe Function                                      |
//+------------------------------------------------------------------+
void SingleTimeFrame()
  {
   gSingleTimeFrameSignalStatus = "NoSignal";
   ENUM_TIMEFRAMES TimeFrameArray[7];
   int count = 0;
   int enabledCount = 0;
   int aboveCount = 0;
   int belowCount = 0;

   if(PeriodM1)
      TimeFrameArray[count++] = PERIOD_M1;
   if(PeriodM5)
      TimeFrameArray[count++] = PERIOD_M5;
   if(PeriodM15)
      TimeFrameArray[count++] = PERIOD_M15;
   if(PeriodM30)
      TimeFrameArray[count++] = PERIOD_M30;
   if(PeriodH1)
      TimeFrameArray[count++] = PERIOD_H1;
   if(PeriodH4)
      TimeFrameArray[count++] = PERIOD_H4;
   if(PeriodD1)
      TimeFrameArray[count++] = PERIOD_D1;

   if(count == 0)
      return;

   gTimeFrameIndex = gTimeFrameIndex < count ? gTimeFrameIndex : 0;
   ENUM_TIMEFRAMES SelectedTimeFrame = TimeFrameArray[gTimeFrameIndex];
   gTimeFrameIndexForSymbol = gTimeFrameIndex;
   gTimeFrameIndex++;

   gSingleTFCheckingStatus =
      SelectedTimeFrame == PERIOD_M1  ? "1M"  :
      SelectedTimeFrame == PERIOD_M5  ? "5M" :
      SelectedTimeFrame == PERIOD_M15 ? "15M" :
      SelectedTimeFrame == PERIOD_M30 ? "30M" :
      SelectedTimeFrame == PERIOD_H1  ? "1H" :
      SelectedTimeFrame == PERIOD_H4  ? "4H" :
      SelectedTimeFrame == PERIOD_D1  ? "1D" : "Inactive";

   gTradeComment = tcRSI+tcBollinger+tcStochastic+tcMovingAverage + "+" + gSingleTFCheckingStatus + "+" + tcTradeDirection + "+" + tcSignalStrength + "+RRS";

   double RSI_Value = iRSI(gRandomSymbol, SelectedTimeFrame, RSI_Period, RSI_AppliedPrice, RSI_shift);
   double Stochastic_Main = iStochastic(gRandomSymbol, SelectedTimeFrame, Stochastic_Kperiod, Stochastic_Dperiod, Stochastic_Slowing, Stochastic_Method, Stochastic_PriceField, MODE_MAIN, Stochastic_Shift);
   double Stochastic_Signal = iStochastic(gRandomSymbol, SelectedTimeFrame, Stochastic_Kperiod, Stochastic_Dperiod, Stochastic_Slowing, Stochastic_Method, Stochastic_PriceField, MODE_SIGNAL, Stochastic_Shift);
   double BB_Upper = iBands(gRandomSymbol, SelectedTimeFrame, BollingerBands_Period, BollingerBands_deviation, BollingerBands_BandShift, BollingerBands_AppliedPrice, MODE_UPPER, BollingerBands_Shift);
   double BB_Lower = iBands(gRandomSymbol, SelectedTimeFrame, BollingerBands_Period, BollingerBands_deviation, BollingerBands_BandShift, BollingerBands_AppliedPrice, MODE_LOWER, BollingerBands_Shift);
   double iMovingAverage = iMA(gRandomSymbol, SelectedTimeFrame, MovingAverage_Period, MovingAverage_MAShift, MovingAverage_Method, MovingAverage_AppliedPrice, MovingAverage_Shift);
   double iMovingAverageFive = iMA(gRandomSymbol, SelectedTimeFrame, MovingAverage_Period*5, MovingAverage_MAShift, MovingAverage_Method, MovingAverage_AppliedPrice, MovingAverage_Shift);

   if(RSI)
     {
      enabledCount++;
      if(RSI_Value > RSI_UpLevel)
         aboveCount++;
      if(RSI_Value < RSI_BelowLevel)
         belowCount++;
     }

   if(Stochastic)
     {
      enabledCount++;
      if(Stochastic_Main > Stochastic_UpLevel && Stochastic_Signal > Stochastic_UpLevel)
         aboveCount++;
      if(Stochastic_Main < Stochastic_BelowLevel && Stochastic_Signal < Stochastic_BelowLevel)
         belowCount++;
     }

   if(BollingerBands)
     {
      enabledCount++;
      if(rBID > BB_Upper)
         aboveCount++;
      if(rASK < BB_Lower)
         belowCount++;
     }

   if(MovingAverage)
     {
      enabledCount++;
      if(TradeDirection == Trend)
        {
         if(rBID > iMovingAverage && rBID > iMovingAverageFive)
            aboveCount++;
         if(rASK < iMovingAverage && rASK < iMovingAverageFive)
            belowCount++;
        }
      else
         if(TradeDirection == CounterTrend)
           {
            if(rASK < iMovingAverage && rASK < iMovingAverageFive)
               aboveCount++;
            if(rBID > iMovingAverage && rBID > iMovingAverageFive)
               belowCount++;
           }
     }

// Now check if ALL enabled indicators match
   if(enabledCount == aboveCount)
      gSingleTimeFrameSignalStatus = "ABOVE";
   else
      if(enabledCount == belowCount)
         gSingleTimeFrameSignalStatus = "BELOW";
      else
         gSingleTimeFrameSignalStatus = "NoSignal";
   /**
   if((!RSI || RSI_Value > RSI_UpLevel) &&
     (!Stochastic || Stochastic_Main > Stochastic_UpLevel && Stochastic_Signal > Stochastic_UpLevel) &&
     (!BollingerBands || rBID > BB_Upper) &&
     (!MovingAverage || (TradeDirection == Trend && rBID > iMovingAverage) || (TradeDirection == CounterTrend && rASK < iMovingAverage)))
     gSingleTimeFrameSignalStatus = "ABOVE";

   if((!RSI || RSI_Value < RSI_BelowLevel) &&
     (!Stochastic || Stochastic_Main < Stochastic_BelowLevel && Stochastic_Signal < Stochastic_BelowLevel) &&
     (!BollingerBands ||rASK < BB_Lower) &&
     (!MovingAverage || (TradeDirection == Trend && rASK < iMovingAverage) || (TradeDirection == CounterTrend && rBID > iMovingAverage)))
     gSingleTimeFrameSignalStatus = "BELOW";
     **/
  }

//+------------------------------------------------------------------+
//|    Candle Close                                                  |
//+------------------------------------------------------------------+
void CandleClose()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if((OrderMagicNumber() == gBuyMagic || OrderMagicNumber() == gSellMagic) && (OrderType() == OP_BUY || OrderType() == OP_SELL))
           {
            datetime openTime = OrderOpenTime();
            string CandleCloseSymbol = (OrderType() == OP_BUY) ? gBuySymbol : gSellSymbol;
            if(CandleCloseSymbol == "")
               CandleCloseSymbol = OrderSymbol(); // Fallback

            ENUM_TIMEFRAMES CandlePeriod = PERIOD_CURRENT; // Default
            string fOrderComment = OrderComment();
            if(StringFind(fOrderComment, "1M") != -1)
               CandlePeriod = PERIOD_M1;
            else
               if(StringFind(fOrderComment, "5M") != -1)
                  CandlePeriod = PERIOD_M5;
               else
                  if(StringFind(fOrderComment, "15M") != -1)
                     CandlePeriod = PERIOD_M15;
                  else
                     if(StringFind(fOrderComment, "30M") != -1)
                        CandlePeriod = PERIOD_M30;
                     else
                        if(StringFind(fOrderComment, "1H") != -1)
                           CandlePeriod = PERIOD_H1;
                        else
                           if(StringFind(fOrderComment, "4H") != -1)
                              CandlePeriod = PERIOD_H4;
                           else
                              if(StringFind(fOrderComment, "1D") != -1)
                                 CandlePeriod = PERIOD_D1;

            // Calculate candle shift
            int openCandleIndex = iBarShift(CandleCloseSymbol, CandlePeriod, openTime, true);
            // Check if it's time to close the order
            if(openCandleIndex >= CandleExit)
              {
               if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrNONE))
                  Print(__FUNCTION__, " => Order ", OrderTicket(), " Failed to Close. Error: ", GetLastError());
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|    Signal Status                                                 |
//+------------------------------------------------------------------+
void SignalStatus()
  {
   ENUM_TIMEFRAMES timeframes[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};

   string sRSI_[7], sStochastic_[7], sMovingAverage_[7], sBollingerBands_[7];

   for(int i = 0; i < ArraySize(timeframes); i++)
     {
      ENUM_TIMEFRAMES tf = timeframes[i];

      // RSI Calculation
      double rsiValue = iRSI(gRandomSymbol, tf, RSI_Period, RSI_AppliedPrice, RSI_shift);
      sRSI_[i] = (rsiValue > RSI_UpLevel) ? "ABOVE" : (rsiValue < RSI_BelowLevel) ? "BELOW" : "NEUTRAL";

      // Stochastic Calculation
      double mainValue = iStochastic(gRandomSymbol, tf, Stochastic_Kperiod, Stochastic_Dperiod, Stochastic_Slowing, Stochastic_Method, Stochastic_PriceField, MODE_MAIN, Stochastic_Shift);
      double signalValue = iStochastic(gRandomSymbol, tf, Stochastic_Kperiod, Stochastic_Dperiod, Stochastic_Slowing, Stochastic_Method, Stochastic_PriceField, MODE_SIGNAL, Stochastic_Shift);
      sStochastic_[i] = (mainValue > Stochastic_UpLevel && signalValue > Stochastic_UpLevel) ? "ABOVE" : (mainValue < Stochastic_BelowLevel && signalValue < Stochastic_BelowLevel) ? "BELOW" : "NEUTRAL";

      // Moving Average Calculation
      double iMovingAverage = iMA(gRandomSymbol, tf, MovingAverage_Period, MovingAverage_MAShift, MovingAverage_Method, MovingAverage_AppliedPrice, MovingAverage_Shift);
      sMovingAverage_[i] = (rBID > iMovingAverage) ? "ABOVE" : (rASK < iMovingAverage) ? "BELOW" : "NEUTRAL";

      // Bollinger Bands Calculation
      double BB_Upper = iBands(gRandomSymbol, tf, BollingerBands_Period, BollingerBands_deviation, BollingerBands_BandShift, BollingerBands_AppliedPrice, MODE_UPPER, BollingerBands_Shift);
      double BB_Lower = iBands(gRandomSymbol, tf, BollingerBands_Period, BollingerBands_deviation, BollingerBands_BandShift, BollingerBands_AppliedPrice, MODE_LOWER, BollingerBands_Shift);
      sBollingerBands_[i] = (rBID > BB_Upper) ? "ABOVE" : (rASK < BB_Lower) ? "BELOW" : "NEUTRAL";
     }

   cIndicatorStaus =
      "\n                                             ------------------------------------------------" +
      "\n                                             :: RSI                             : (M1 : " + sRSI_[0] + ") |:| (M5 : " + sRSI_[1] + ") |:| (M15 : " + sRSI_[2] + ") |:| (M30 : " + sRSI_[3] + ") |:| (H1 : " + sRSI_[4] + ") |:| (H4 : " + sRSI_[5] + ") |:| (D1 : " + sRSI_[6] + ")" +
      "\n                                             :: Stochastic                     : (M1 : " + sStochastic_[0] + ") |:| (M5 : " + sStochastic_[1] + ") |:| (M15 : " + sStochastic_[2] + ") |:| (M30 : " + sStochastic_[3] + ") |:| (H1 : " + sStochastic_[4] + ") |:| (H4 : " + sStochastic_[5] + ") |:| (D1 : " + sStochastic_[6] + ")" +
      "\n                                             :: Moving Average            : (M1 : " + sMovingAverage_[0] + ") |:| (M5 : " + sMovingAverage_[1] + ") |:| (M15 : " + sMovingAverage_[2] + ") |:| (M30 : " + sMovingAverage_[3] + ") |:| (H1 : " + sMovingAverage_[4] + ") |:| (H4 : " + sMovingAverage_[5] + ") |:| (D1 : " + sMovingAverage_[6] + ")" +
      "\n                                             :: Bollinger Bands              : (M1 : " + sBollingerBands_[0] + ") |:| (M5 : " + sBollingerBands_[1] + ") |:| (M15 : " + sBollingerBands_[2] + ") |:| (M30 : " + sBollingerBands_[3] + ") |:| (H1 : " + sBollingerBands_[4] + ") |:| (H4 : " + sBollingerBands_[5] + ") |:| (D1 : " + sBollingerBands_[6] + ")";

  }

//+------------------------------------------------------------------+
//|  Virtual Take Profits                                            |
//+------------------------------------------------------------------+
void VirtualTakeProfit()
  {
   for(int pos_0 = OrdersTotal() - 1; pos_0 >= 0; pos_0--)
     {
      OrderSelect(pos_0, SELECT_BY_POS, MODE_TRADES);
      ResetLastError();
      if(OrderMagicNumber() == gBuyMagic && OrderSymbol() == gBuySymbol && OrderType() == OP_BUY)
        {
         if(bBID >= OrderOpenPrice() + TakeProfit * bPoint)
           {
            if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrNONE))
               Print(__FUNCTION__ " => Buy Order failed to close, error code: ", GetLastError());
           }
        }
      if(OrderMagicNumber() == gSellMagic && OrderSymbol() == gSellSymbol && OrderType() == OP_SELL)
        {
         if(sASK <= OrderOpenPrice() - TakeProfit * sPoint)
           {
            if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrNONE))
               Print(__FUNCTION__ " => Sell Order failed to close, error code: ", GetLastError());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|  Virtual Stop Loss                                               |
//+------------------------------------------------------------------+
void VirtualStopLoss()
  {
   for(int pos_0 = OrdersTotal() - 1; pos_0 >= 0; pos_0--)
     {
      OrderSelect(pos_0, SELECT_BY_POS, MODE_TRADES);
      ResetLastError();
      if(OrderMagicNumber() == gBuyMagic && OrderSymbol() == gBuySymbol && OrderType() == OP_BUY)
        {
         if(bBID <= OrderOpenPrice() - StopLoss * bPoint)
           {
            if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrNONE))
               Print(__FUNCTION__ " => Buy Order failed to close, error code : ", GetLastError());
           }
        }
      if(OrderMagicNumber() == gSellMagic && OrderSymbol() == gSellSymbol && OrderType() == OP_SELL)
        {
         if(sASK >= OrderOpenPrice() + StopLoss * sPoint)
           {
            if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrNONE))
               Print(__FUNCTION__ " => Sell Order failed to close, error code : ", GetLastError());
           }
        }
     }
  }

struct VirtualSL
  {
   int               tOrderTicket;
   double            tStopLoss;
  };

VirtualSL tVirtualBuySLArray[100];
VirtualSL tVirtualSellSLArray[100];
//+------------------------------------------------------------------+
//|   Virtual Trailing : Find Index                                                               |
//+------------------------------------------------------------------+
int findIndex(int tTicket, VirtualSL &tArray[], int &tSize)
  {
   for(int i = 0; i < tSize; i++)
     {
      if(tArray[i].tOrderTicket == tTicket)
         return i;
     }
   return -1;
  }

//+------------------------------------------------------------------+
//|      Virtual Trailing : Store StopLoss                           |
//+------------------------------------------------------------------+
void storeSL(int tTicket, double tSL, VirtualSL &tArray[], int &tSize)
  {
   int tIndex = findIndex(tTicket, tArray, tSize);
   if(tIndex != -1)
      tArray[tIndex].tStopLoss = tSL;
   else
     {
      tArray[tSize].tOrderTicket = tTicket;
      tArray[tSize].tStopLoss = tSL;
      tSize++;
     }
  }

//+------------------------------------------------------------------+
//|       Virtual Trailing : Get StopLoss                            |
//+------------------------------------------------------------------+
double getSL(int tTicket, VirtualSL &tArray[], int tSize)
  {
   int tIndex = findIndex(tTicket, tArray, tSize);
   return (tIndex != -1) ? tArray[tIndex].tStopLoss : 0;
  }

//+------------------------------------------------------------------+
//|         Virtual Trailing : Delete StopLoss                       |
//+------------------------------------------------------------------+
void deleteSL(int tTicket, VirtualSL &tArray[], int &tSize)
  {
   int tIndex = findIndex(tTicket, tArray, tSize);
   if(tIndex != -1)
     {
      for(int i = tIndex; i < tSize - 1; i++)
         tArray[i] = tArray[i + 1];
      tSize--;
     }
  }

//+------------------------------------------------------------------+
//|         Virtual Trailing                                         |
//+------------------------------------------------------------------+
void VirtualTrailingStopLoss()
  {
   double tLastSL, tNewSL;
   if(OrdersTotal() == 0)
     {
      tBuySize = 0;
      tSellSize = 0;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         double tEntryPrice = OrderOpenPrice();
         int tTicket = OrderTicket();

         if(OrderMagicNumber() == gBuyMagic && OrderType() == OP_BUY && OrderSymbol() == gBuySymbol)
           {
            int BuyTrailingGap = MathMax(MathMax(MarketInfo(gBuySymbol, MODE_STOPLEVEL) + 2, gBuySpread + 2), Trailing_Gap);
            tLastSL = getSL(tTicket, tVirtualBuySLArray, tBuySize);
            if(bBID <= tLastSL && tLastSL != 0)
              {
               deleteSL(tTicket, tVirtualBuySLArray, tBuySize);
               if(!OrderClose(tTicket, OrderLots(), OrderClosePrice(), 3, clrNONE))
                  Print(__FUNCTION__, " => Buy Order failed to close: ", GetLastError());
              }
            if(bBID - (tEntryPrice + Trailing_Start * bPoint) > bPoint * BuyTrailingGap)
              {
               tNewSL = bBID - (bPoint * BuyTrailingGap);
               if(tLastSL < tNewSL || tLastSL == 0.00)
                  storeSL(tTicket, tNewSL, tVirtualBuySLArray, tBuySize);
              }
           }

         if(OrderMagicNumber() == gSellMagic && OrderType() == OP_SELL && OrderSymbol() == gSellSymbol)
           {
            int SellTrailingGap = MathMax(MathMax(MarketInfo(gSellSymbol, MODE_STOPLEVEL) + 2, gSellSpread + 2), Trailing_Gap);
            tLastSL = getSL(tTicket, tVirtualSellSLArray, tSellSize);
            if(sASK >= tLastSL && tLastSL != 0)
              {
               deleteSL(tTicket, tVirtualSellSLArray, tSellSize);
               if(!OrderClose(tTicket, OrderLots(), OrderClosePrice(), 3, clrNONE))
                  Print(__FUNCTION__, " => Sell Order failed to close: ", GetLastError());
              }
            if((tEntryPrice - Trailing_Start * sPoint) - sASK > sPoint * SellTrailingGap)
              {
               tNewSL = sASK + (sPoint * SellTrailingGap);
               if(tLastSL > tNewSL || tLastSL == 0.00)
                  storeSL(tTicket, tNewSL, tVirtualSellSLArray, tSellSize);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Creating Text object                                             |
//+------------------------------------------------------------------+
bool TextCreate(const long            chart_ID=0,               // chart's ID
                const string            name="Text",              // object name
                const int               sub_window=0,             // subwindow index
                datetime                time=0,                   // anchor point time
                double                  price=0,                  // anchor point price
                const string            text="Text",              // the text itself
                const color             clr=clrRed,               // color
                const string            font="Arial",             // font
                const int               font_size=10,             // font size
                const double            angle=90,                // text slope
                const ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT_LOWER, // anchor type
                const bool              back=false,               // in the background
                const bool              selection=false,          // highlight to move
                const bool              hidden=true,              // hidden in the object list
                const long              z_order=0)                // priority for mouse click
  {

//--- reset the error value
   ResetLastError();
//--- create Text object
   if(!ObjectCreate(chart_ID,name,OBJ_TEXT,sub_window,time,price))
     {
      Print(__FUNCTION__,": failed to create \"Text\" object! Error code = ",GetLastError());
      return(false);
     }
//--- set the text
   ObjectSetString(chart_ID,name,OBJPROP_TEXT,text);
//--- set text font
   ObjectSetString(chart_ID,name,OBJPROP_FONT,font);
//--- set font size
   ObjectSetInteger(chart_ID,name,OBJPROP_FONTSIZE,font_size);
//--- set the slope angle of the text
   ObjectSetDouble(chart_ID,name,OBJPROP_ANGLE,angle);
//--- set anchor type
   ObjectSetInteger(chart_ID,name,OBJPROP_ANCHOR,anchor);
//--- set color
   ObjectSetInteger(chart_ID,name,OBJPROP_COLOR,clr);
//--- display in the foreground (false) or background (true)
   ObjectSetInteger(chart_ID,name,OBJPROP_BACK,back);
//--- enable (true) or disable (false) the mode of moving the object by mouse
   ObjectSetInteger(chart_ID,name,OBJPROP_SELECTABLE,selection);
   ObjectSetInteger(chart_ID,name,OBJPROP_SELECTED,selection);
//--- hide (true) or display (false) graphical object name in the object list
   ObjectSetInteger(chart_ID,name,OBJPROP_HIDDEN,hidden);
//--- set the priority for receiving the event of a mouse click in the chart
   ObjectSetInteger(chart_ID,name,OBJPROP_ZORDER,z_order);
//--- successful execution
   return(true);
  }
//+------------------------------------------------------------------+
//| Create the Verticle line                                         |
//+------------------------------------------------------------------+
bool VLineCreate(const long            chart_ID=0,        // chart's ID
                 const string          name="VLine",      // line name
                 const int             sub_window=0,      // subwindow index
                 datetime              time=0,            // line time
                 const color           clr=clrBlue,        // line color
                 const ENUM_LINE_STYLE style=STYLE_SOLID, // line style
                 const int             width=1,           // line width
                 const bool            back=false,        // in the background
                 const bool            selection=false,   // highlight to move
                 const bool            hidden=true,       // hidden in the object list
                 const long            z_order=0)         // priority for mouse click
  {
//--- create a vertical line
   if(!ObjectCreate(chart_ID,name,OBJ_VLINE,sub_window,time,0))
     {
      Print(__FUNCTION__,": failed to create \"Vline\" object! Error code = ",GetLastError());
      return(false);
     }
//--- set line color
   ObjectSetInteger(chart_ID,name,OBJPROP_COLOR,clr);
//--- set line display style
   ObjectSetInteger(chart_ID,name,OBJPROP_STYLE,style);
//--- set line width
   ObjectSetInteger(chart_ID,name,OBJPROP_WIDTH,width);
//--- display in the foreground (false) or background (true)
   ObjectSetInteger(chart_ID,name,OBJPROP_BACK,back);
//--- enable (true) or disable (false) the mode of moving the line by mouse
//--- when creating a graphical object using ObjectCreate function, the object cannot be
//--- highlighted and moved by default. Inside this method, selection parameter
//--- is true by default making it possible to highlight and move the object
   ObjectSetInteger(chart_ID,name,OBJPROP_SELECTABLE,selection);
   ObjectSetInteger(chart_ID,name,OBJPROP_SELECTED,selection);
//--- hide (true) or display (false) graphical object name in the object list
   ObjectSetInteger(chart_ID,name,OBJPROP_HIDDEN,hidden);
//--- set the priority for receiving the event of a mouse click in the chart
   ObjectSetInteger(chart_ID,name,OBJPROP_ZORDER,z_order);
//--- successful execution
   return(true);
  }

//+------------------------------------------------------------------+
//|   XML Download                                                   |
//+------------------------------------------------------------------+
void xmlDownload()
  {
   Sleep(3000);
//---
   ResetLastError();

   string cookie=NULL, headers;
   string reqheaders="User-Agent: Mozilla/4.0\r\n";
   char post[],result[];
   int res;
   string url="http://nfs.faireconomy.media/ff_calendar_thisweek.xml";
   ResetLastError();
   int timeout=5000;
   res=WebRequest("GET",url,reqheaders,timeout,post,result,headers);
   if(res==-1)
     {
      Print("Error in WebRequest. Error code  =",GetLastError());
      //--- Perhaps the URL is not listed, display a message about the necessity to add the address
      MessageBox("Add the address '"+url+"' in the list of allowed URLs on tab 'Expert Advisors'","Error",MB_ICONINFORMATION);
      NewsURLChecking = "Not Added ==>> Please add URL in Tool => Option => Expert Advisor";
     }
   else
     {
      //--- Load successfully
      NewsURLChecking = "Added";
      XMLDownloadTime = TimeToString(TimeLocal());
      //PrintFormat("The file has been successfully loaded, File size =%d bytes.",ArraySize(result));
      //--- Save the data to a file
      int filehandle=FileOpen(xmlFileName,FILE_WRITE|FILE_BIN);
      //--- Checking errors
      if(filehandle!=INVALID_HANDLE)
        {
         //--- Save the contents of the result[] array to a file
         FileWriteArray(filehandle,result,0,ArraySize(result));
         //--- Close the file
         FileClose(filehandle);
        }
      else
         Print("Error in FileOpen. Error code=",GetLastError());
     }
//---
  }
//+------------------------------------------------------------------+
//| Read the XML file                                                |
//+------------------------------------------------------------------+
void xmlRead()
  {
//---
   ResetLastError();
   sData="";
   ulong pos[];
//Print("Reading XML News File");
   int FileHandle=FileOpen(xmlFileName,FILE_READ|FILE_BIN|FILE_ANSI);
   if(FileHandle!=INVALID_HANDLE)
     {
      //--- receive the file size
      ulong size=FileSize(FileHandle);
      //--- read data from the file
      while(!FileIsEnding(FileHandle))
         sData=FileReadString(FileHandle,(int)size);
      //--- close
      FileClose(FileHandle);
     }
//--- check for errors
   else
      PrintFormat(INAME+": failed to open %s file, Error code = %d",xmlFileName,GetLastError());
//Print("XML Reading Done.");
   XMLReadTime = TimeToString(TimeLocal());
//---
  }

//+------------------------------------------------------------------+
//| Check for update XML                                             |
//+------------------------------------------------------------------+
void xmlUpdate()
  {
   Sleep(3000);
//--- do not download on saturday
   if(TimeDayOfWeek(Midnight)==6)
      return;
   else
     {
      //Print(INAME+": Downloading and Updating XML News file...");
      //Print(INAME+": deleting old XML file");
      FileDelete(xmlFileName);
      xmlDownload();
      xmlRead();
      xmlModifed=(datetime)FileGetInteger(xmlFileName,FILE_MODIFY_DATE,false);
      //PrintFormat(INAME+": XML updated successfully! last modified: %s",(string)xmlModifed);
      XMLUpdateTime = TimeToString(TimeLocal());
     }
//---
  }

//+------------------------------------------------------------------+
//| Converts ff time & date into yyyy.mm.dd hh:mm - by deVries       |
//+------------------------------------------------------------------+
string MakeDateTime(string strDate,string strTime)
  {
//---
   int n1stDash=StringFind(strDate, "-");
   int n2ndDash=StringFind(strDate, "-", n1stDash+1);

   string strMonth=StringSubstr(strDate,0,2);
   string strDay=StringSubstr(strDate,3,2);
   string strYear=StringSubstr(strDate,6,4);

   string tempStr[];
   StringSplit(strTime,StringGetCharacter(":",0),tempStr);
   int nTimeColonPos=StringFind(strTime,":");
   string strHour=tempStr[0];
   string strMinute=StringSubstr(tempStr[1],0,2);
   string strAM_PM=StringSubstr(tempStr[1],2,2);

   int nHour24=StringToInteger(strHour);
   if((strAM_PM=="pm" || strAM_PM=="PM") && nHour24!=12)
      nHour24+=12;
   if((strAM_PM=="am" || strAM_PM=="AM") && nHour24==12)
      nHour24=0;
   string strHourPad="";
   if(nHour24<10)
      strHourPad="0";
   return((strYear+"."+strMonth+"."+strDay+" "+strHourPad+nHour24+":"+strMinute));
//---
  }

//+------------------------------------------------------------------+
//| Convert day of the week to text                                  |
//+------------------------------------------------------------------+
string DayToStr(datetime time)
  {
   int ThisDay=TimeDayOfWeek(time);
   string day="";
   switch(ThisDay)
     {
      case 0:
         day="Sun";
         break;
      case 1:
         day="Mon";
         break;
      case 2:
         day="Tue";
         break;
      case 3:
         day="Wed";
         break;
      case 4:
         day="Thu";
         break;
      case 5:
         day="Fri";
         break;
      case 6:
         day="Sat";
         break;
     }
   return(day);
  }
//+------------------------------------------------------------------+
//| Convert months to text                                           |
//+------------------------------------------------------------------+
string MonthToStr()
  {
   int ThisMonth=Month();
   string month="";
   switch(ThisMonth)
     {
      case 1:
         month="Jan";
         break;
      case 2:
         month="Feb";
         break;
      case 3:
         month="Mar";
         break;
      case 4:
         month="Apr";
         break;
      case 5:
         month="May";
         break;
      case 6:
         month="Jun";
         break;
      case 7:
         month="Jul";
         break;
      case 8:
         month="Aug";
         break;
      case 9:
         month="Sep";
         break;
      case 10:
         month="Oct";
         break;
      case 11:
         month="Nov";
         break;
      case 12:
         month="Dec";
         break;
     }
   return(month);
  }

//+------------------------------------------------------------------+
//|  Checking Upcoming News                                          |
//+------------------------------------------------------------------+
int UpcomingNewsImpact(string symb,int n)
  {
   int news_total=0;
   string MainSymbol=StringSubstr(symb,0,3);
   string SecondSymbol=StringSubstr(symb,3,3);
//---
   if(assignVal)
     {
      //--- BY AUTHORS WITH SOME MODIFICATIONS
      //--- define the XML Tags, Vars
      string sTags[7]= {"<title>","<country>","<date><![CDATA[","<time><![CDATA[","<impact><![CDATA[","<forecast><![CDATA[","<previous><![CDATA["};
      string eTags[7]= {"</title>","</country>","]]></date>","]]></time>","]]></impact>","]]></forecast>","]]></previous>"};
      int index=0;
      int next=-1;
      int BoEvent=0,begin=0,end=0;
      string myEvent="";
      //--- Minutes calculation
      datetime EventTime=0;
      int EventMinute=0;
      //--- split the currencies into the two parts

      //--- loop to get the data from xml tags
      while(true)
        {
         BoEvent=StringFind(sData,"<event>",BoEvent);
         if(BoEvent==-1)
            break;
         BoEvent+=7;
         next=StringFind(sData,"</event>",BoEvent);
         if(next == -1)
            break;
         myEvent = StringSubstr(sData,BoEvent,next-BoEvent);
         BoEvent = next;
         begin=0;
         for(int i=0; i<7; i++)
           {
            Event[index][i]="";
            next=StringFind(myEvent,sTags[i],begin);
            //--- Within this event, if tag not found, then it must be missing; skip it
            if(next==-1)
               continue;
            else
              {
               //--- We must have found the sTag okay...
               //--- Advance past the start tag
               begin=next+StringLen(sTags[i]);
               end=StringFind(myEvent,eTags[i],begin);
               //---Find start of end tag and Get data between start and end tag
               if(end>begin && end!=-1)
                  Event[index][i]=StringSubstr(myEvent,begin,end-begin);
              }
           }
         //--- filters that define whether we want to skip this particular currencies or events

         if(Event[index][COUNTRY]!=MainSymbol && Event[index][COUNTRY]!=SecondSymbol)
            continue;
         if(Event[index][IMPACT] == "Medium" || Event[index][IMPACT] == "Low" || Event[index][IMPACT] == "Holiday")
            continue;
         if(Event[index][TIME]=="Tentative" || Event[index][TIME]=="" || Event[index][TIME]=="All Day")
            continue;
         if(StringFind(Event[index][TITLE],"Speaks") != -1)
            continue;


         //--- sometimes they forget to remove the tags :)
         if(StringFind(Event[index][TITLE],"<![CDATA[")!=-1)
            StringReplace(Event[index][TITLE],"<![CDATA[","");
         if(StringFind(Event[index][TITLE],"]]>")!=-1)
            StringReplace(Event[index][TITLE],"]]>","");
         if(StringFind(Event[index][TITLE],"]]>")!=-1)
            StringReplace(Event[index][TITLE],"]]>","");
         //---
         if(StringFind(Event[index][FORECAST],"&lt;")!=-1)
            StringReplace(Event[index][FORECAST],"&lt;","");
         if(StringFind(Event[index][PREVIOUS],"&lt;")!=-1)
            StringReplace(Event[index][PREVIOUS],"&lt;","");

         //--- set some values (dashes) if empty
         if(Event[index][FORECAST]=="")
            Event[index][FORECAST]="---";
         if(Event[index][PREVIOUS]=="")
            Event[index][PREVIOUS]="---";
         //--- Convert Event time to MT4 time
         string evD=MakeDateTime(Event[index][DATE],Event[index][TIME]);
         EventTime=datetime(evD);
         index++;
        }
      //--- loop to set arrays/buffers that uses to draw objects and alert
      for(int ii=0; ii<index; ii++)
        {
         eTitle[ii][n]    = Event[ii][TITLE];
         eCountry[ii][n]  = Event[ii][COUNTRY];
         eImpact[ii][n]   = Event[ii][IMPACT];
         eTime[ii][n]     = datetime(MakeDateTime(Event[ii][DATE],Event[ii][TIME]))-TimeGMTOffset();
        }
      news_total=index;
     }

   datetime tn=TimeLocal(); //TimeCurrent() or TimeLocal()
   int newsresult = -1;

   for(int qi=0; qi<news_total; qi++)
     {
      if((NewsManagement == HighImpactNews && eImpact[qi][n]=="High"))
        {
         //gAvgChartPrice = (WindowPriceMax() + WindowPriceMin()) / 2;
         //ObjectsDeleteAll(0,"Tr_",-1,-1);
         //ObjectsDeleteAll(0,"NFtext_",-1,-1);
         if(ObjectFind(0, "Tr_" + eTitle[qi][n]) == -1 && ObjectFind(0, "NFtext_" + (eTime[qi][n])) == -1)
           {
            VLineCreate(0,"Tr_"+eTitle[qi][n],0,eTime[qi][n]+(TimeCurrent()-TimeLocal()),clrRed,STYLE_SOLID);
            TextCreate(0,"NFtext_"+(eTime[qi][n]),0,eTime[qi][n]+(TimeCurrent()-TimeLocal()-60),gAvgChartPrice,eTitle[qi][n],clrRed);
           }

         if((tn <= (eTime[qi][n]) && tn >= (eTime[qi][n]-BeforeNews_Minutes*60))  || (tn >= eTime[qi][n] && tn <= (eTime[qi][n]+AfterNews_Minutes*60)))
            newsresult = 2;
        }
      else
        {
         for(int newsi = 0; newsi < ArraySize(gImportantNews_Array); newsi++)
           {
            if(StringFind(eTitle[qi][n], gImportantNews_Array[newsi]) != -1)
              {
               //gAvgChartPrice = (WindowPriceMax() + WindowPriceMin()) / 2;
               //ObjectsDeleteAll(0,"Tr_",-1,-1);
               //ObjectsDeleteAll(0,"NFtext_",-1,-1);
               if(ObjectFind(0, "Tr_" + eTitle[qi][n]) == -1 && ObjectFind(0, "NFtext_" + (eTime[qi][n])) == -1)
                 {
                  VLineCreate(0,"Tr_"+eTitle[qi][n],0,eTime[qi][n]+(TimeCurrent()-TimeLocal()),clrRed,STYLE_SOLID);
                  TextCreate(0,"NFtext_"+(eTime[qi][n]),0,eTime[qi][n]+(TimeCurrent()-TimeLocal()-60),gAvgChartPrice,eTitle[qi][n],clrRed);
                 }

               if((tn <= (eTime[qi][n]) && tn >= (eTime[qi][n]-BeforeNews_Minutes*60))  || (tn >= eTime[qi][n] && tn <= (eTime[qi][n]+AfterNews_Minutes*60)))
                  newsresult = 2;
              }
           }
        }
     }
   XMLUpcomingImpact = TimeToString(TimeLocal());
   return newsresult;
  }

//+------------------------------------------------------------------+
//|   Important News to Array                                        |
//+------------------------------------------------------------------+
void ImportantNews_ConvertStringToArray()
  {
   int ImportantNews_count = StringSplit(Important_News, ',', gImportantNews_Array);
   for(int i = 0; i < ImportantNews_count; i++)
     {
      gImportantNews_Array[i] = StringTrimLeft(StringTrimRight(gImportantNews_Array[i])); // Trim spaces before and after
     }
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
