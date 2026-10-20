//+------------------------------------------------------------------+
//|                                                EA_SOLUSD_ATR.mq4 |
//|  Inspirado en EA_Multidireccional_Avanzado (EMA + RSI + EMA200   |
//|  + ATR). Adaptado a cripto (SOL/USD): mercado 24/7, distancias   |
//|  normalizadas por ATR (no en puntos), filtro de spread y lote    |
//|  calculado con el valor de tick real del simbolo.                |
//|                                                                  |
//|  NO GARANTIZA GANANCIAS. Probar en demo / Probador antes de      |
//|  usar dinero real.                                               |
//+------------------------------------------------------------------+
#property copyright "BiteFixes"
#property version   "1.00"
#property strict

//--- Estrategia
input int    EMA_Fast                = 9;      // EMA rapida
input int    EMA_Slow                = 21;     // EMA lenta
input int    EMA_Trend               = 200;    // EMA de tendencia macro
input bool   Use_Trend_Filter        = true;   // Compras solo sobre EMA200, ventas solo bajo EMA200
input double Min_Cross_Gap_ATR       = 0.05;   // Separacion minima EMA fast/slow (en multiplos de ATR)
input int    RSI_Period              = 14;
input double RSI_Buy_Min             = 50.0;   // Compra: RSI entre Min y Max
input double RSI_Buy_Max             = 70.0;
input double RSI_Sell_Min            = 30.0;   // Venta: RSI entre Min y Max
input double RSI_Sell_Max            = 50.0;

//--- ATR / SL / TP (todo en multiplos de ATR)
input int    ATR_Period              = 14;
input double ATR_SL_Mult             = 1.5;
input double ATR_TP_Mult             = 4.0;

//--- Trailing stop basado en ATR
input bool   Use_Trailing            = true;
input double Trail_Start_ATR         = 1.5;    // Empieza cuando la ganancia supera X*ATR
input double Trail_Dist_ATR          = 1.0;    // Distancia del SL al precio

//--- Salida por reversion de tendencia
input bool   Close_On_Trend_Flip     = true;
input int    Flip_Confirm_Bars       = 2;      // Velas cerradas que confirman el cruce contrario

//--- Gestion de riesgo
input double Risk_Percent            = 0.5;    // % del balance arriesgado por operacion
input double Max_Risk_Multiple_MinLot= 2.0;    // Si el lote minimo arriesga mas que X veces el objetivo, no opera
input double Max_Daily_Loss_Pct      = 3.0;    // Pausa el dia si la perdida del dia supera este % del balance
input int    Max_Trades_Per_Day      = 4;
input double Max_Spread_ATR          = 0.15;   // No entra si el spread supera X*ATR

//--- Horario (hora del servidor). Cripto opera 24/7: desactivado por defecto
input bool   Use_Time_Filter         = false;
input int    Start_Hour              = 0;
input int    End_Hour                = 23;
input bool   Use_Friday_Close        = false;
input int    Friday_Close_Hour       = 21;

//--- General
input int    Magic_Number            = 50505;
input int    Slippage                = 50;     // En puntos del simbolo (ajustar segun digitos)
input string Trade_Comment           = "EA_SOLUSD_ATR";

datetime g_lastBar = 0;

//+------------------------------------------------------------------+
int LotDigits(double step)
{
   int d = 0;
   double x = step;
   while(MathAbs(x - MathRound(x)) > 0.00000001 && d < 8)
   {
      x *= 10.0;
      d++;
   }
   return d;
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(EMA_Fast >= EMA_Slow)
   {
      Print("Parametros invalidos: EMA_Fast debe ser menor que EMA_Slow");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(Risk_Percent <= 0.0 || ATR_SL_Mult <= 0.0 || ATR_TP_Mult <= 0.0)
   {
      Print("Parametros invalidos: riesgo, SL y TP deben ser mayores que 0");
      return INIT_PARAMETERS_INCORRECT;
   }

   Print("=== EA_SOLUSD_ATR iniciado en ", Symbol(), " TF=", Period(), " ===");
   Print("Digits=", Digits, " Point=", DoubleToString(Point, Digits),
         " MinLot=", DoubleToString(MarketInfo(Symbol(), MODE_MINLOT), 4),
         " LotStep=", DoubleToString(MarketInfo(Symbol(), MODE_LOTSTEP), 4),
         " MaxLot=", DoubleToString(MarketInfo(Symbol(), MODE_MAXLOT), 2),
         " ContractSize=", DoubleToString(MarketInfo(Symbol(), MODE_LOTSIZE), 4),
         " TickValue=", DoubleToString(MarketInfo(Symbol(), MODE_TICKVALUE), 6),
         " TickSize=", DoubleToString(MarketInfo(Symbol(), MODE_TICKSIZE), Digits),
         " StopLevel=", (int)MarketInfo(Symbol(), MODE_STOPLEVEL));

   if(StringFind(Symbol(), "SOL") < 0)
      Print("AVISO: el simbolo ", Symbol(), " no parece ser Solana. Este EA esta pensado para SOLUSD.");

   if(MarketInfo(Symbol(), MODE_TICKVALUE) <= 0.0)
      Print("AVISO: TickValue = 0. El EA no podra calcular el lote hasta que el simbolo tenga datos.");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
// Selecciona la orden abierta de este EA/simbolo. Devuelve ticket o -1
int SelectMyOrder()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) return OrderTicket();
   }
   return -1;
}

//+------------------------------------------------------------------+
// P/L del dia (cerradas + flotante) y operaciones abiertas hoy
void DailyStats(double &pnl, int &trades)
{
   pnl = 0.0;
   trades = 0;
   datetime dayStart = iTime(Symbol(), PERIOD_D1, 0);

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() > OP_SELL) continue;
      if(OrderOpenTime() >= dayStart) trades++;
      if(OrderCloseTime() >= dayStart) pnl += OrderProfit() + OrderSwap() + OrderCommission();
   }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() > OP_SELL) continue;
      if(OrderOpenTime() >= dayStart) trades++;
      pnl += OrderProfit() + OrderSwap() + OrderCommission();
   }
}

//+------------------------------------------------------------------+
bool InTradingHours()
{
   int h = TimeHour(TimeCurrent());
   if(Start_Hour <= End_Hour) return (h >= Start_Hour && h <= End_Hour);
   return (h >= Start_Hour || h <= End_Hour);
}

//+------------------------------------------------------------------+
// 1 = compra, -1 = venta, 0 = nada. Usa solo velas cerradas (shift 1 y 2)
int GetSignal(double atr)
{
   double f1 = iMA(Symbol(), 0, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double s1 = iMA(Symbol(), 0, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double f2 = iMA(Symbol(), 0, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 2);
   double s2 = iMA(Symbol(), 0, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 2);
   double rsi = iRSI(Symbol(), 0, RSI_Period, PRICE_CLOSE, 1);
   double emaT = iMA(Symbol(), 0, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE, 1);
   double c1 = iClose(Symbol(), 0, 1);

   if(MathAbs(f1 - s1) < Min_Cross_Gap_ATR * atr) return 0;

   if(f2 <= s2 && f1 > s1)
   {
      if(rsi >= RSI_Buy_Min && rsi <= RSI_Buy_Max && (!Use_Trend_Filter || c1 > emaT))
         return 1;
   }
   if(f2 >= s2 && f1 < s1)
   {
      if(rsi >= RSI_Sell_Min && rsi <= RSI_Sell_Max && (!Use_Trend_Filter || c1 < emaT))
         return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
// Cruce contrario sostenido durante N velas cerradas
bool FlipConfirmed(bool isBuy)
{
   int n = MathMax(1, Flip_Confirm_Bars);
   for(int i = 1; i <= n; i++)
   {
      double f = iMA(Symbol(), 0, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, i);
      double s = iMA(Symbol(), 0, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, i);
      if(isBuy  && f >= s) return false;
      if(!isBuy && f <= s) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
// Lote segun % de riesgo y distancia del SL, usando el valor real del tick
double CalcLots(double slDist)
{
   double tickVal = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(tickVal <= 0.0 || tickSize <= 0.0 || slDist <= 0.0 || step <= 0.0) return 0.0;

   double riskMoney = AccountBalance() * Risk_Percent / 100.0;
   double lossPerLot = (slDist / tickSize) * tickVal;
   if(lossPerLot <= 0.0) return 0.0;

   double lots = riskMoney / lossPerLot;
   lots = MathFloor(lots / step) * step;

   if(lots < minLot)
   {
      // El lote minimo arriesga mas de lo deseado: solo se permite hasta cierto limite
      if(minLot * lossPerLot > riskMoney * Max_Risk_Multiple_MinLot)
      {
         Print("Operacion omitida: lote minimo ", DoubleToString(minLot, 4),
               " arriesga ", DoubleToString(minLot * lossPerLot, 2),
               " (objetivo ", DoubleToString(riskMoney, 2), ")");
         return 0.0;
      }
      lots = minLot;
   }
   if(lots > maxLot) lots = maxLot;
   return NormalizeDouble(lots, LotDigits(step));
}

//+------------------------------------------------------------------+
void OpenTrade(int dir, double atr)
{
   double stopLvl = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double spread = Ask - Bid;
   double slDist = atr * ATR_SL_Mult;
   double tpDist = atr * ATR_TP_Mult;

   double minSL = stopLvl + spread + Point;
   if(slDist < minSL) slDist = minSL;
   if(tpDist < stopLvl + Point) tpDist = stopLvl + Point;

   double lots = CalcLots(slDist);
   if(lots <= 0.0) return;

   int cmd = (dir > 0) ? OP_BUY : OP_SELL;

   ResetLastError();
   double fm = AccountFreeMarginCheck(Symbol(), cmd, lots);
   if(fm <= 0.0 || GetLastError() == ERR_NOT_ENOUGH_MONEY)
   {
      Print("Margen insuficiente para ", DoubleToString(lots, 4), " lotes");
      return;
   }

   for(int attempt = 0; attempt < 3; attempt++)
   {
      RefreshRates();
      double price, sl, tp;
      if(cmd == OP_BUY)
      {
         price = Ask;
         sl = NormalizeDouble(price - slDist, Digits);
         tp = NormalizeDouble(price + tpDist, Digits);
      }
      else
      {
         price = Bid;
         sl = NormalizeDouble(price + slDist, Digits);
         tp = NormalizeDouble(price - tpDist, Digits);
      }

      int ticket = OrderSend(Symbol(), cmd, lots, price, Slippage, sl, tp,
                             Trade_Comment, Magic_Number, 0, (cmd == OP_BUY) ? clrLime : clrRed);
      if(ticket > 0)
      {
         Print("Orden abierta #", ticket, (cmd == OP_BUY ? " BUY " : " SELL "),
               DoubleToString(lots, 4), " @ ", DoubleToString(price, Digits),
               " SL=", DoubleToString(sl, Digits), " TP=", DoubleToString(tp, Digits),
               " ATR=", DoubleToString(atr, Digits));
         return;
      }

      int err = GetLastError();
      Print("OrderSend fallo, error ", err, " (intento ", attempt + 1, ")");
      if(err != ERR_REQUOTE && err != ERR_PRICE_CHANGED && err != ERR_OFF_QUOTES &&
         err != ERR_BROKER_BUSY && err != ERR_TRADE_CONTEXT_BUSY)
         return;
      Sleep(500);
   }
}

//+------------------------------------------------------------------+
// Cierra la orden actualmente seleccionada
void CloseSelected()
{
   int ticket = OrderTicket();
   double lots = OrderLots();
   int type = OrderType();

   for(int attempt = 0; attempt < 3; attempt++)
   {
      RefreshRates();
      double price = (type == OP_BUY) ? Bid : Ask;
      if(OrderClose(ticket, lots, price, Slippage, clrYellow))
      {
         Print("Orden cerrada #", ticket);
         return;
      }
      int err = GetLastError();
      Print("OrderClose fallo, error ", err, " (intento ", attempt + 1, ")");
      if(err != ERR_REQUOTE && err != ERR_PRICE_CHANGED && err != ERR_OFF_QUOTES &&
         err != ERR_BROKER_BUSY && err != ERR_TRADE_CONTEXT_BUSY)
         return;
      Sleep(500);
   }
}

//+------------------------------------------------------------------+
// Trailing basado en ATR, con validacion del nivel de stop del broker
void ManageTrailing()
{
   if(SelectMyOrder() < 0) return;

   double atr = iATR(Symbol(), 0, ATR_Period, 1);
   if(atr <= 0.0) return;

   double stopLvl = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double tick = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tick <= 0.0) tick = Point;

   int ticket = OrderTicket();
   int type = OrderType();
   double open = OrderOpenPrice();
   double sl = OrderStopLoss();
   double tp = OrderTakeProfit();

   if(type == OP_BUY)
   {
      if(Bid - open < Trail_Start_ATR * atr) return;
      double newSL = NormalizeDouble(Bid - Trail_Dist_ATR * atr, Digits);
      if(Bid - newSL < stopLvl + Point) return;
      if(sl == 0.0 || newSL > sl + tick)
      {
         if(!OrderModify(ticket, open, newSL, tp, 0, clrNONE))
            Print("Trailing BUY fallo, error ", GetLastError());
      }
   }
   else if(type == OP_SELL)
   {
      if(open - Ask < Trail_Start_ATR * atr) return;
      double newSL = NormalizeDouble(Ask + Trail_Dist_ATR * atr, Digits);
      if(newSL - Ask < stopLvl + Point) return;
      if(sl == 0.0 || newSL < sl - tick)
      {
         if(!OrderModify(ticket, open, newSL, tp, 0, clrNONE))
            Print("Trailing SELL fallo, error ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(Bars < EMA_Trend + Flip_Confirm_Bars + 5) return;

   // Trailing en cada tick
   if(Use_Trailing) ManageTrailing();

   // Logica de senales solo una vez por vela nueva
   if(Time[0] == g_lastBar) return;
   g_lastBar = Time[0];

   double atr = iATR(Symbol(), 0, ATR_Period, 1);
   if(atr <= 0.0) return;

   bool fridayStop = (Use_Friday_Close && DayOfWeek() == 5 && Hour() >= Friday_Close_Hour);

   // Con posicion abierta: solo gestionar salida
   if(SelectMyOrder() >= 0)
   {
      bool isBuy = (OrderType() == OP_BUY);
      if(fridayStop || (Close_On_Trend_Flip && FlipConfirmed(isBuy)))
         CloseSelected();
      return;
   }

   // Sin posicion: filtros y entrada
   if(fridayStop) return;
   if(Use_Time_Filter && !InTradingHours()) return;

   double pnl;
   int tradesToday;
   DailyStats(pnl, tradesToday);
   if(tradesToday >= Max_Trades_Per_Day) return;
   if(pnl <= -AccountBalance() * Max_Daily_Loss_Pct / 100.0) return;

   if((Ask - Bid) > Max_Spread_ATR * atr) return;

   int sig = GetSignal(atr);
   if(sig != 0) OpenTrade(sig, atr);
}
//+------------------------------------------------------------------+
