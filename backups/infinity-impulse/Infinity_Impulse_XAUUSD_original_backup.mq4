//+------------------------------------------------------------------+
//|                                Infinity_Impulse_XAUUSD_MT4.mq4   |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//--- Parámetros de Entrada
input string   InpSymbol            = "XAUUSD";      // Símbolo (Oro)
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M5;     // Temporalidad (M5)
input double   InpRiskPercent       = 1.0;           // Riesgo por operación (%)
input double   InpStopLossPts       = 300;           // Stop Loss en Puntos
input double   InpTakeProfitPts     = 600;           // Take Profit en Puntos
input int      InpMaxPositions      = 2;             // Máximo de posiciones simultáneas

input group "=== Indicadores de Tendencia y Filtro ==="
input int      InpEMAPeriod         = 50;            // Período EMA de Tendencia
input int      InpBBPeriod          = 20;            // Período Bandas de Bollinger
input double   InpBBDeviation       = 2.0;           // Desviación Bollinger

input group "=== Configuración General ==="
input int      InpMagicNumber       = 202650;        // Magic Number
input int      InpSlippage          = 5;             // Deslizamiento máximo en puntos

//--- Variables globales
datetime last_bar_time;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   last_bar_time = 0;
   Print("Infinity Impulse MT4 inicializado correctamente para ", InpSymbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Nada que liberar explícitamente en MT4 para funciones nativas iMA/iBands
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Verificar nueva barra en la temporalidad configurada
   datetime current_bar_time = iTime(InpSymbol, InpTimeframe, 0);
   if(current_bar_time == last_bar_time) return;
   
   // Validar límite de posiciones simultáneas abiertas por este EA
   if(CountOpenPositions() >= InpMaxPositions) return;

   // Obtener valores de los indicadores para la vela cerrada anterior (índice 1)
   double ema_value = iMA(InpSymbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
   
   // En MT4, iBands devuelve: mode = 0 (Base), MODE_UPPER (Banda Superior), MODE_LOWER (Banda Inferior)
   double upper_bb  = iBands(InpSymbol, InpTimeframe, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double lower_bb  = iBands(InpSymbol, InpTimeframe, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_LOWER, 1);

   double close_1   = iClose(InpSymbol, InpTimeframe, 1);
   double open_1    = iOpen(InpSymbol, InpTimeframe, 1);
   
   double ask       = MarketInfo(InpSymbol, MODE_ASK);
   double bid       = MarketInfo(InpSymbol, MODE_BID);
   double point     = MarketInfo(InpSymbol, MODE_POINT);

   // Lógica de Impulso / Ruptura (Bidireccional)
   bool buy_signal  = (close_1 > upper_bb) && (close_1 > ema_value) && (close_1 > open_1);
   bool sell_signal = (close_1 < lower_bb) && (close_1 < ema_value) && (close_1 < open_1);

   if(buy_signal)
   {
      double sl = ask - (InpStopLossPts * point);
      double tp = ask + (InpTakeProfitPts * point);
      double lots = CalculateLotSize(InpStopLossPts);

      int ticket = OrderSend(InpSymbol, OP_BUY, lots, ask, InpSlippage, sl, tp, "Infinity_Buy", InpMagicNumber, 0, clrBlue);
      if(ticket > 0)
      {
         last_bar_time = current_bar_time;
      }
   }
   else if(sell_signal)
   {
      double sl = bid + (InpStopLossPts * point);
      double tp = bid - (InpTakeProfitPts * point);
      double lots = CalculateLotSize(InpStopLossPts);

      int ticket = OrderSend(InpSymbol, OP_SELL, lots, bid, InpSlippage, sl, tp, "Infinity_Sell", InpMagicNumber, 0, clrRed);
      if(ticket > 0)
      {
         last_bar_time = current_bar_time;
      }
   }
}

//+------------------------------------------------------------------+
//| Cuenta las posiciones abiertas asociadas al Magic Number         |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == InpSymbol && OrderMagicNumber() == InpMagicNumber)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Cálculo automático de lotes basado en el riesgo porcentual       |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_points)
{
   double balance = AccountBalance();
   double risk_money = balance * (InpRiskPercent / 100.0);
   
   double tick_value = MarketInfo(InpSymbol, MODE_TICKVALUE);
   double tick_size  = MarketInfo(InpSymbol, MODE_TICKSIZE);
   double point      = MarketInfo(InpSymbol, MODE_POINT);
   
   if(sl_points <= 0 || tick_value <= 0) return 0.01;

   double loss_per_lot = (sl_points * (point / tick_size)) * tick_value;
   if(loss_per_lot <= 0) return 0.01;

   double lots = risk_money / loss_per_lot;
   
   double min_lot  = MarketInfo(InpSymbol, MODE_MINLOT);
   double max_lot  = MarketInfo(InpSymbol, MODE_MAXLOT);
   double lot_step = MarketInfo(InpSymbol, MODE_LOTSTEP);

   lots = NormalizeDouble(MathRound(lots / lot_step) * lot_step, 2);
   if(lots < min_lot) lots = min_lot;
   if(lots > max_lot) lots = max_lot;

   return lots;
}
//+------------------------------------------------------------------+