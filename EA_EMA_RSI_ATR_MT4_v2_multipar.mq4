//+------------------------------------------------------------------+
//|                            EA_EMA_RSI_ATR_MT4_v2_multipar.mq4     |
//|  Estrategia: Cruce de EMA(9/21) + filtro RSI(14, 70/30)           |
//|  Gestion de riesgo: SL/TP dinamicos basados en ATR                |
//|  Lote calculado por % de riesgo sobre el equity                   |
//|  Control de una operacion por vela POR SIMBOLO                    |
//|  Circuit breaker diario y drawdown mensual: a nivel de CUENTA     |
//|  (equity total), no por simbolo, porque el capital es compartido  |
//|  entre todos los pares que opera el EA.                           |
//|                                                                    |
//|  v1.90: la unica corrida larga (2005-2026) con resultado positivo |
//|  que tenemos (v1.80, PF 1.47, +$12.61) se apoya en solo 51        |
//|  operaciones en 21 anos -- muy pocas para confiar plenamente y    |
//|  muy pocas para generar un ingreso mensual real. En vez de        |
//|  relajar los filtros de calidad (que fueron los que llevaron el   |
//|  PF de <1.0 a >1.0), esta version reutiliza EXACTAMENTE la misma  |
//|  logica de senal, riesgo y proteccion, pero la corre en paralelo  |
//|  sobre una lista de pares (Symbols_List). Esto multiplica las     |
//|  oportunidades sin tocar ningun umbral que ya demostro funcionar. |
//|                                                                    |
//|  IMPORTANTE: esto es una hipotesis de mejora, NO un resultado     |
//|  probado. Hay que correr el mismo backtest 2005-2026 (ahora en    |
//|  modo multi-par, ej. usando el Optimizador o corriendo cada par   |
//|  por separado y sumando resultados) para confirmar si el PF se    |
//|  mantiene o mejora al aumentar la frecuencia.                     |
//|                                                                    |
//|  NOTA TECNICA: el Probador de Estrategias de MT4 solo simula UN   |
//|  simbolo por corrida (el del grafico donde se adjunta el EA). La  |
//|  logica multi-simbolo definida abajo SI funciona en cuenta real / |
//|  demo (forward testing), pero para backtest hay que probar cada   |
//|  par por separado (cambiando el grafico) y comparar/sumar los     |
//|  resultados manualmente -- MT4 no permite backtest multi-simbolo  |
//|  nativo en un solo run.                                            |
//+------------------------------------------------------------------+
#property copyright "BiteFixes"
#property version   "1.90"
#property strict

#include "Fibonacci_Module_MT4.mqh"

//====================================================================
// PARAMETROS DE ESTRATEGIA (identicos a v1.80, validados)
//====================================================================
input string _grp0                = "=== Simbolos a operar (solo en cuenta real/demo, no en backtest) ===";
input string Symbols_List         = "EURUSD,GBPUSD,USDJPY,USDCHF"; // separados por coma, sin espacios
input int    Max_Symbols           = 10; // tope de simbolos que el arreglo puede manejar

input string _grp1               = "=== Estrategia EMA / RSI ===";
input int    EMA_Fast_Period      = 9;
input int    EMA_Slow_Period      = 21;
input int    RSI_Period           = 14;
input double RSI_Overbought       = 70.0;
input double RSI_Oversold         = 30.0;
input ENUM_TIMEFRAMES Trade_TF    = PERIOD_M15;

input string _grp2               = "=== Gestion de Riesgo ===";
input int    ATR_Period           = 14;
input double ATR_SL_Multiplier    = 1.5;
input double ATR_TP_Multiplier    = 3.0;
input double Risk_Percent         = 0.5;     // % del equity TOTAL arriesgado por operacion (se comparte entre todos los pares)
input double MaxRiskPercentHard   = 5.0;
input int    Magic_Number         = 202601;
input int    Slippage_Points      = 5;

input string _grp2b              = "=== Limite de Exposicion Simultanea ===";
input int    Max_Open_Positions_Total = 3; // maximo de posiciones abiertas AL MISMO TIEMPO entre todos los pares
                                            // evita que una senal correlacionada en varios pares a la vez dispare
                                            // mas riesgo del que Risk_Percent fue pensado para manejar

input string _grp3               = "=== Circuit Breaker Diario (nivel cuenta) ===";
input bool   Use_Daily_CircuitBreaker = true;
input double Daily_Loss_Limit_Pct     = 3.0;

input string _grp4               = "=== Control de Drawdown Mensual (nivel cuenta) ===";
input bool   Use_Monthly_DD_Control   = true;
input double Monthly_DD_Reduce_Pct    = 5.0;
input double Monthly_DD_HardStop_Pct  = 10.0;
input double Monthly_DD_Reduce_Factor = 0.5;

input string _grp5               = "=== Filtro de Regimen (ADX) ===";
input bool   Use_ADX_Filter       = true;
input int    ADX_Period           = 14;
input double ADX_Threshold        = 22.0;

input string _grp5b              = "=== Filtro de Sesion Horaria ===";
input bool   Use_Session_Filter   = true;
input int    Session_Start_Hour   = 7;
input int    Session_End_Hour     = 20;

input string _grp5c              = "=== Filtro de Calidad de Cruce ===";
input bool   Use_EMA_Separation_Filter = true;
input double Min_EMA_Separation_ATR    = 0.15;
input bool   Use_RSI_Momentum_Filter   = true;
input bool   Use_Spread_Filter         = true;
input double Max_Spread_Points         = 30;

input string _grp6               = "=== Filtro Fibonacci ===";
input bool   Fib_UseAsFilter      = true;

input string _grp7               = "=== Filtro de Volatilidad Extrema ===";
input bool   Use_Volatility_Filter = true;
input int    ATR_Avg_Period        = 50;
input double ATR_Spike_Multiplier  = 2.5;

input string _grp8               = "=== Kill Switch por Gap Violento (por simbolo) ===";
input bool   Use_Gap_KillSwitch      = true;
input double Gap_ATR_Multiplier      = 3.0;
input bool   Gap_KillSwitch_ClosePositions = true;

input string _grp9               = "=== Freno Global Permanente (nivel cuenta) ===";
input bool   Use_Global_Equity_Floor  = true;
input double Global_Max_Drawdown_Pct  = 12.0;

input string _grp9b              = "=== Reactivacion Mensual tras Freno Global ===";
input bool   Allow_Monthly_Reactivation = true;
input double Reactivation_Max_ATR_Multiplier = 1.3;
input int    Reactivation_Consecutive_Months_Required = 2;
input int    Max_Reactivations_Total = 3;

input string _grp9c              = "=== Trailing Stop ===";
input bool   Use_Trailing_Stop        = true;
input double Trailing_Activation_ATR  = 1.0;
input double Trailing_Distance_ATR    = 1.5;
input double Trailing_Step_Points     = 20;

input string _grp10              = "=== Depuracion ===";
input bool   Debug_Print          = true;

//====================================================================
// VARIABLES GLOBALES A NIVEL DE CUENTA (una sola instancia, compartida)
//====================================================================
double   dayStartEquity   = 0.0;
datetime currentDay       = 0;

double   monthStartEquity = 0.0;
int      currentMonth     = -1;

bool     tradingHaltedToday = false;
bool     tradingHaltedMonth = false;

double   initialEquity        = 0.0;
bool     globalHaltActive     = false;
int      lastReactivationCheckMonth = -1;
int      consecutiveCalmMonths      = 0;
int      totalReactivations         = 0;
bool     permanentlyDeadForReal     = false;

//====================================================================
// VARIABLES POR SIMBOLO (arreglos paralelos, indexados junto a g_symbols[])
//====================================================================
string   g_symbols[];
int      g_symbolCount = 0;

datetime g_lastBarTime[];
datetime g_lastGapCheckBarTime[];
datetime g_gapKillSwitchDay[];
bool     g_dailyGapKillSwitchActive[];

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   initialEquity = AccountEquity();
   globalHaltActive = false;
   ResetDailyTracking();
   ResetMonthlyTracking();

   ParseSymbolsList();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Parsea Symbols_List (separado por comas) y arma los arreglos      |
//| paralelos de estado por simbolo. Si un simbolo no existe en el    |
//| broker (MarketInfo devuelve 0), se descarta con un aviso.         |
//+------------------------------------------------------------------+
void ParseSymbolsList()
  {
   string rawList = Symbols_List;
   string parts[];
   int count = StringSplit(rawList, ',', parts);

   ArrayResize(g_symbols, 0);
   ArrayResize(g_lastBarTime, 0);
   ArrayResize(g_lastGapCheckBarTime, 0);
   ArrayResize(g_gapKillSwitchDay, 0);
   ArrayResize(g_dailyGapKillSwitchActive, 0);

   g_symbolCount = 0;

   for(int i = 0; i < count && g_symbolCount < Max_Symbols; i++)
     {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(sym == "")
         continue;

      double testBid = MarketInfo(sym, MODE_BID);
      if(testBid <= 0)
        {
         Print("Simbolo '", sym, "' no disponible en este broker, se omite.");
         continue;
        }

      int newSize = g_symbolCount + 1;
      ArrayResize(g_symbols, newSize);
      ArrayResize(g_lastBarTime, newSize);
      ArrayResize(g_lastGapCheckBarTime, newSize);
      ArrayResize(g_gapKillSwitchDay, newSize);
      ArrayResize(g_dailyGapKillSwitchActive, newSize);

      g_symbols[g_symbolCount] = sym;
      g_lastBarTime[g_symbolCount] = 0;
      g_lastGapCheckBarTime[g_symbolCount] = 0;
      g_gapKillSwitchDay[g_symbolCount] = 0;
      g_dailyGapKillSwitchActive[g_symbolCount] = false;

      g_symbolCount++;
     }

   Print("EA multi-par inicializado con ", g_symbolCount, " simbolos: ", Symbols_List);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }

//+------------------------------------------------------------------+
//| Reinicia el tracking diario (equity de inicio del dia, a nivel    |
//| de CUENTA, no por simbolo)                                        |
//+------------------------------------------------------------------+
void ResetDailyTracking()
  {
   dayStartEquity     = AccountEquity();
   currentDay         = iTime(NULL, PERIOD_D1, 0);
   tradingHaltedToday = false;
  }

//+------------------------------------------------------------------+
//| Reinicia el tracking mensual (equity de inicio del mes)           |
//+------------------------------------------------------------------+
void ResetMonthlyTracking()
  {
   currentMonth       = TimeMonth(TimeCurrent());
   monthStartEquity   = AccountEquity();
   tradingHaltedMonth = false;
  }

//+------------------------------------------------------------------+
//| Circuit breaker diario -- a nivel de CUENTA (equity total),       |
//| porque el capital arriesgado se comparte entre todos los pares    |
//+------------------------------------------------------------------+
bool CheckDailyCircuitBreaker()
  {
   if(!Use_Daily_CircuitBreaker)
      return false;

   datetime todayStart = iTime(NULL, PERIOD_D1, 0);
   if(todayStart != currentDay)
      ResetDailyTracking();

   double equity = AccountEquity();
   double lossPct = (dayStartEquity - equity) / dayStartEquity * 100.0;

   if(lossPct >= Daily_Loss_Limit_Pct)
     {
      if(!tradingHaltedToday)
        {
         Print("Circuit breaker diario activado (cuenta completa). Perdida del dia: ", DoubleToString(lossPct, 2), "%");
         CloseAllPositionsAllSymbols();
        }
      tradingHaltedToday = true;
     }

   return tradingHaltedToday;
  }

//+------------------------------------------------------------------+
//| Drawdown mensual -- a nivel de CUENTA                             |
//+------------------------------------------------------------------+
double GetMonthlyDrawdownFactor()
  {
   if(!Use_Monthly_DD_Control)
      return 1.0;

   int nowMonth = TimeMonth(TimeCurrent());
   if(nowMonth != currentMonth)
      ResetMonthlyTracking();

   double equity = AccountEquity();
   double ddPct  = (monthStartEquity - equity) / monthStartEquity * 100.0;

   if(ddPct >= Monthly_DD_HardStop_Pct)
     {
      if(!tradingHaltedMonth)
        {
         Print("Hard stop mensual activado (cuenta completa). Drawdown del mes: ", DoubleToString(ddPct, 2), "%");
         CloseAllPositionsAllSymbols();
        }
      tradingHaltedMonth = true;
      return -1.0;
     }
   else if(ddPct >= Monthly_DD_Reduce_Pct)
     {
      return Monthly_DD_Reduce_Factor;
     }

   tradingHaltedMonth = false;
   return 1.0;
  }

//+------------------------------------------------------------------+
//| Filtro ADX -- por simbolo                                         |
//+------------------------------------------------------------------+
bool IsTrendingMarket(string sym)
  {
   if(!Use_ADX_Filter)
      return true;

   double adxMain = iADX(sym, Trade_TF, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   bool ok = (adxMain >= ADX_Threshold);
   if(!ok && Debug_Print)
      Print(sym, ": rechazado por ADX: ", DoubleToString(adxMain, 2), " < ", DoubleToString(ADX_Threshold, 2));
   return ok;
  }

//+------------------------------------------------------------------+
//| Filtro de sesion horaria -- no depende del simbolo, es hora del   |
//| broker, comun a todos los pares                                   |
//+------------------------------------------------------------------+
bool IsWithinTradingSession()
  {
   if(!Use_Session_Filter)
      return true;

   int hourNow = TimeHour(TimeCurrent());
   bool ok;

   if(Session_Start_Hour <= Session_End_Hour)
      ok = (hourNow >= Session_Start_Hour && hourNow < Session_End_Hour);
   else
      ok = (hourNow >= Session_Start_Hour || hourNow < Session_End_Hour);

   return ok;
  }

//+------------------------------------------------------------------+
//| Filtro de volatilidad extrema -- por simbolo                      |
//+------------------------------------------------------------------+
bool IsVolatilityAcceptable(string sym)
  {
   if(!Use_Volatility_Filter)
      return true;

   double currentAtr = iATR(sym, Trade_TF, ATR_Period, 1);

   double sumAtr = 0.0;
   for(int i = 2; i <= ATR_Avg_Period + 1; i++)
      sumAtr += iATR(sym, Trade_TF, ATR_Period, i);
   double avgAtr = sumAtr / ATR_Avg_Period;

   if(avgAtr <= 0)
      return true;

   bool ok = (currentAtr <= avgAtr * ATR_Spike_Multiplier);
   if(!ok && Debug_Print)
      Print(sym, ": rechazado por volatilidad extrema (", DoubleToString(currentAtr / avgAtr, 2), "x el promedio)");
   return ok;
  }

//+------------------------------------------------------------------+
//| Cierra TODAS las posiciones del EA en TODOS los simbolos          |
//| (usado por los circuit breakers a nivel de cuenta)                |
//+------------------------------------------------------------------+
void CloseAllPositionsAllSymbols()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != Magic_Number)
         continue;

      double closePrice = (OrderType() == OP_BUY) ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK);
      bool res = OrderClose(OrderTicket(), OrderLots(), closePrice, Slippage_Points, clrOrange);
      if(!res)
         Print("Error cerrando orden #", OrderTicket(), " (", OrderSymbol(), "): ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Cierra las posiciones del EA en UN solo simbolo (usado por el     |
//| kill switch de gap, que es especifico de cada par)                |
//+------------------------------------------------------------------+
void CloseSymbolPositions(string sym)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != sym || OrderMagicNumber() != Magic_Number)
         continue;

      double closePrice = (OrderType() == OP_BUY) ? MarketInfo(sym, MODE_BID) : MarketInfo(sym, MODE_ASK);
      bool res = OrderClose(OrderTicket(), OrderLots(), closePrice, Slippage_Points, clrOrange);
      if(!res)
         Print(sym, ": error cerrando orden #", OrderTicket(), ": ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Kill switch por gap violento -- por simbolo (idx = indice en los  |
//| arreglos g_*)                                                     |
//+------------------------------------------------------------------+
void CheckGapKillSwitch(int idx)
  {
   if(!Use_Gap_KillSwitch)
      return;

   string sym = g_symbols[idx];

   datetime today = iTime(sym, PERIOD_D1, 0);
   if(today != g_gapKillSwitchDay[idx])
     {
      g_gapKillSwitchDay[idx]         = today;
      g_dailyGapKillSwitchActive[idx] = false;
     }

   datetime barTime = iTime(sym, Trade_TF, 0);
   if(barTime == g_lastGapCheckBarTime[idx])
      return;
   g_lastGapCheckBarTime[idx] = barTime;

   double atrValue = iATR(sym, Trade_TF, ATR_Period, 1);
   if(atrValue <= 0)
      return;

   double gap = MathAbs(iOpen(sym, Trade_TF, 0) - iClose(sym, Trade_TF, 1));

   if(gap >= atrValue * Gap_ATR_Multiplier)
     {
      g_dailyGapKillSwitchActive[idx] = true;
      Print(sym, ": *** KILL SWITCH ACTIVADO *** Gap de ", DoubleToString(gap, 5),
            " (", DoubleToString(gap / atrValue, 2), "x ATR). Trading pausado en ", sym, " por hoy.");
      if(Gap_KillSwitch_ClosePositions)
         CloseSymbolPositions(sym);
     }
  }

//+------------------------------------------------------------------+
//| Freno global permanente -- a nivel de CUENTA (identico a v1.80)   |
//+------------------------------------------------------------------+
bool CheckGlobalEquityFloor()
  {
   if(!Use_Global_Equity_Floor)
      return false;

   if(permanentlyDeadForReal)
      return true;

   if(globalHaltActive)
     {
      if(Allow_Monthly_Reactivation)
        {
         int nowMonth = TimeMonth(TimeCurrent());
         if(nowMonth != lastReactivationCheckMonth)
           {
            lastReactivationCheckMonth = nowMonth;

            // Usamos el primer simbolo de la lista como referencia de volatilidad
            // para decidir la reactivacion (aproximacion razonable: si el par
            // principal esta calmado, es representativo del regimen general).
            string refSym = (g_symbolCount > 0) ? g_symbols[0] : Symbol();

            double currentAtr = iATR(refSym, Trade_TF, ATR_Period, 1);
            double sumAtr = 0.0;
            for(int i = 2; i <= ATR_Avg_Period + 1; i++)
               sumAtr += iATR(refSym, Trade_TF, ATR_Period, i);
            double avgAtr = sumAtr / ATR_Avg_Period;

            bool volatilidadNormal = (avgAtr > 0 && currentAtr <= avgAtr * Reactivation_Max_ATR_Multiplier);

            if(volatilidadNormal)
              {
               consecutiveCalmMonths++;
               if(consecutiveCalmMonths >= Reactivation_Consecutive_Months_Required)
                 {
                  totalReactivations++;
                  if(totalReactivations > Max_Reactivations_Total)
                    {
                     permanentlyDeadForReal = true;
                     Print("### FRENO DEFINITIVO ### Se agotaron las ", Max_Reactivations_Total, " reactivaciones.");
                     return true;
                    }

                  globalHaltActive     = false;
                  consecutiveCalmMonths = 0;
                  initialEquity        = AccountEquity();
                  Print("### REACTIVACION #", totalReactivations, " ### Nuevo equity de referencia: ", DoubleToString(initialEquity, 2));
                  return false;
                 }
              }
            else
               consecutiveCalmMonths = 0;
           }
         return true;
        }
      return true;
     }

   if(initialEquity <= 0)
      return false;

   double equity = AccountEquity();
   double ddPct  = (initialEquity - equity) / initialEquity * 100.0;

   if(ddPct >= Global_Max_Drawdown_Pct)
     {
      globalHaltActive      = true;
      consecutiveCalmMonths = 0;
      lastReactivationCheckMonth = TimeMonth(TimeCurrent());
      Print("### FRENO GLOBAL ACTIVADO ### Drawdown total: ", DoubleToString(ddPct, 2), "%.");
      CloseAllPositionsAllSymbols();
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Calcula el lote -- por simbolo, pero el riesgo % es sobre el      |
//| EQUITY TOTAL de la cuenta (compartido entre todos los pares)      |
//+------------------------------------------------------------------+
double CalculateLotSize(string sym, double slDistancePoints, double reduceFactor)
  {
   double equity     = AccountEquity();
   double riskAmount = equity * (Risk_Percent / 100.0) * reduceFactor;

   double tickValue = MarketInfo(sym, MODE_TICKVALUE);
   double tickSize  = MarketInfo(sym, MODE_TICKSIZE);
   double point     = MarketInfo(sym, MODE_POINT);

   double slDistance   = slDistancePoints * point;
   double valuePerLot  = (tickSize > 0) ? (slDistance / tickSize) * tickValue : 0.0;

   double lot = (valuePerLot > 0) ? riskAmount / valuePerLot : 0.0;

   double minLot  = MarketInfo(sym, MODE_MINLOT);
   double maxLot  = MarketInfo(sym, MODE_MAXLOT);
   double lotStep = MarketInfo(sym, MODE_LOTSTEP);

   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;

   if(lot < minLot)
     {
      double impliedRiskPct = (minLot * valuePerLot) / equity * 100.0;
      if(impliedRiskPct > MaxRiskPercentHard)
        {
         if(Debug_Print)
            Print(sym, ": lote minimo implicaria ", DoubleToString(impliedRiskPct, 2), "% de riesgo (> tope). Omitido.");
         return -1.0;
        }
      lot = minLot;
     }

   lot = MathMax(minLot, MathMin(maxLot, lot));
   return lot;
  }

//+------------------------------------------------------------------+
//| Filtro de calidad de cruce -- identico a v1.80, parametrizado     |
//+------------------------------------------------------------------+
bool IsSignalQualityOk(string sym, bool isBuySignal, double emaFast1, double emaSlow1,
                        double rsi1, double rsi2, double atrValue)
  {
   if(Use_EMA_Separation_Filter)
     {
      double separation = MathAbs(emaFast1 - emaSlow1);
      if(atrValue > 0 && separation < Min_EMA_Separation_ATR * atrValue)
        {
         if(Debug_Print)
            Print(sym, ": rechazado por separacion EMA insuficiente");
         return false;
        }
     }

   if(Use_RSI_Momentum_Filter)
     {
      bool momentumOk = isBuySignal ? (rsi1 > rsi2) : (rsi1 < rsi2);
      if(!momentumOk)
        {
         if(Debug_Print)
            Print(sym, ": rechazado por momentum RSI contrario");
         return false;
        }
     }

   if(Use_Spread_Filter)
     {
      double spreadPoints = MarketInfo(sym, MODE_SPREAD);
      if(spreadPoints > Max_Spread_Points)
        {
         if(Debug_Print)
            Print(sym, ": rechazado por spread excesivo (", spreadPoints, " puntos)");
         return false;
        }
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Trailing stop -- por simbolo                                      |
//+------------------------------------------------------------------+
void ManageTrailingStop(string sym)
  {
   if(!Use_Trailing_Stop)
      return;

   double atrValue = iATR(sym, Trade_TF, ATR_Period, 1);
   if(atrValue <= 0)
      return;

   double point = MarketInfo(sym, MODE_POINT);
   double activationDist = Trailing_Activation_ATR * atrValue;
   double trailDist       = Trailing_Distance_ATR * atrValue;
   double stepDist        = Trailing_Step_Points * point;

   double bid = MarketInfo(sym, MODE_BID);
   double ask = MarketInfo(sym, MODE_ASK);

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != sym || OrderMagicNumber() != Magic_Number)
         continue;

      if(OrderType() == OP_BUY)
        {
         double profitDist = bid - OrderOpenPrice();
         if(profitDist < activationDist)
            continue;

         double newSL = bid - trailDist;
         if(newSL > OrderStopLoss() + stepDist)
            OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrBlue);
        }
      else if(OrderType() == OP_SELL)
        {
         double profitDist = OrderOpenPrice() - ask;
         if(profitDist < activationDist)
            continue;

         double newSL = ask + trailDist;
         if(newSL < OrderStopLoss() - stepDist || OrderStopLoss() == 0)
            OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrBlue);
        }
     }
  }

//+------------------------------------------------------------------+
//| Verifica si ya existe una posicion abierta de este EA en UN       |
//| simbolo especifico                                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition(string sym)
  {
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() == sym && OrderMagicNumber() == Magic_Number)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Cuenta el total de posiciones abiertas del EA en TODOS los        |
//| simbolos (para el limite Max_Open_Positions_Total)                |
//+------------------------------------------------------------------+
int TotalOpenPositionsAllSymbols()
  {
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() == Magic_Number)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Evalua senales y gestiona trailing para UN simbolo (idx = indice) |
//+------------------------------------------------------------------+
void ProcessSymbol(int idx)
  {
   string sym = g_symbols[idx];

   CheckGapKillSwitch(idx);
   if(g_dailyGapKillSwitchActive[idx])
      return;

   ManageTrailingStop(sym);

   datetime barTime = iTime(sym, Trade_TF, 0);
   if(barTime == g_lastBarTime[idx])
      return;
   g_lastBarTime[idx] = barTime;

   if(HasOpenPosition(sym))
      return;

   if(TotalOpenPositionsAllSymbols() >= Max_Open_Positions_Total)
      return;

   if(!IsWithinTradingSession())
      return;

   if(!IsTrendingMarket(sym))
      return;

   if(!IsVolatilityAcceptable(sym))
      return;

   double emaFast1 = iMA(sym, Trade_TF, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaFast2 = iMA(sym, Trade_TF, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE, 2);
   double emaSlow1 = iMA(sym, Trade_TF, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaSlow2 = iMA(sym, Trade_TF, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE, 2);
   double rsi1     = iRSI(sym, Trade_TF, RSI_Period, PRICE_CLOSE, 1);
   double rsi2     = iRSI(sym, Trade_TF, RSI_Period, PRICE_CLOSE, 2);
   double atrValue = iATR(sym, Trade_TF, ATR_Period, 1);

   bool crossUp   = (emaFast2 <= emaSlow2 && emaFast1 > emaSlow1);
   bool crossDown = (emaFast2 >= emaSlow2 && emaFast1 < emaSlow1);

   bool rsiOkBuy  = (rsi1 < RSI_Overbought);
   bool rsiOkSell = (rsi1 > RSI_Oversold);

   bool signalBuy  = crossUp   && rsiOkBuy;
   bool signalSell = crossDown && rsiOkSell;

   if(!signalBuy && !signalSell)
      return;

   if(!IsSignalQualityOk(sym, signalBuy, emaFast1, emaSlow1, rsi1, rsi2, atrValue))
      return;

   if(Fib_UseAsFilter)
     {
      FibSwing swing = FindLastSwing(sym, Trade_TF);
      double currentPrice = MarketInfo(sym, MODE_BID);

      if(swing.valid)
        {
         bool enZonaDorada = IsPriceInGoldenZone(currentPrice, swing);
         bool invalidado   = IsSwingInvalidated(currentPrice, swing);

         if(!enZonaDorada || invalidado)
           {
            if(Debug_Print)
               Print(sym, ": senal EMA/RSI rechazada por filtro Fibonacci");
            return;
           }
        }
     }

   double point = MarketInfo(sym, MODE_POINT);
   double slDistancePoints = (atrValue * ATR_SL_Multiplier) / point;

   double ddFactor = GetMonthlyDrawdownFactor();
   double lot = CalculateLotSize(sym, slDistancePoints, ddFactor);
   if(lot <= 0)
      return;

   double bid = MarketInfo(sym, MODE_BID);
   double ask = MarketInfo(sym, MODE_ASK);
   int ticket = -1;

   if(signalBuy)
     {
      double sl = ask - atrValue * ATR_SL_Multiplier;
      double tp = ask + atrValue * ATR_TP_Multiplier;
      ticket = OrderSend(sym, OP_BUY, lot, ask, Slippage_Points, sl, tp, "EMA_RSI_ATR Buy", Magic_Number, 0, clrGreen);
     }
   else if(signalSell)
     {
      double sl = bid + atrValue * ATR_SL_Multiplier;
      double tp = bid - atrValue * ATR_TP_Multiplier;
      ticket = OrderSend(sym, OP_SELL, lot, bid, Slippage_Points, sl, tp, "EMA_RSI_ATR Sell", Magic_Number, 0, clrRed);
     }

   if(ticket < 0)
      Print(sym, ": error al enviar orden: ", GetLastError());
   else
      Print(sym, ": operacion abierta, ticket #", ticket);
  }

//+------------------------------------------------------------------+
//| OnTick                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // --- Proteccion a nivel de CUENTA: se revisan una sola vez por tick, ---
   // --- no por simbolo, porque el equity es compartido.                ---
   if(CheckGlobalEquityFloor())
      return;

   if(CheckDailyCircuitBreaker())
      return;

   if(GetMonthlyDrawdownFactor() < 0)
      return;

   // --- Recorre cada simbolo de la lista y evalua senales/trailing ---
   // --- de forma independiente para cada uno.                       ---
   for(int idx = 0; idx < g_symbolCount; idx++)
      ProcessSymbol(idx);
  }
//+------------------------------------------------------------------+
