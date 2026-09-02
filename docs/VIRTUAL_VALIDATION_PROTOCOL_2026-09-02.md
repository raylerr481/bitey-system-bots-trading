# Bitey SBT — Virtual Validation Protocol

**Fecha:** 2026-09-02  
**Modo:** Demo / capital ficticio  
**Capital inicial:** R$10.000  
**Símbolo:** EURUSD  
**Estrategia:** `ema-rsi-atr-v1`  
**Dinero real:** `false`  
**Broker orders:** `0`  
**Live trading:** deshabilitado

## Qué quedó implementado

1. `app/strategies/technical.py` incorpora una señal reproducible EMA + RSI + ATR, manteniendo el baseline SMA existente.
2. `app/services/virtual_validation.py` ejecuta un recorrido determinista sobre un fixture sintético fijo.
3. Cada operación propuesta pasa por `RiskEngine` antes de entrar en el `DemoEngine`.
4. El harness registra operaciones aceptadas y rechazos con su motivo.
5. Las posiciones abiertas se cierran al final del experimento para completar el P/L realizado.
6. Se calculan P/L, retorno, drawdown, operaciones, operaciones rechazadas, victorias, pérdidas y win rate.
7. `GET/POST /api/v1/validation/virtual` expone la prueba al frontend.
8. `web/server.py` conecta el botón **Ejecutar prueba local** del dashboard con ese endpoint.

## Importante sobre la evidencia

El fixture actual es **sintético y determinista**, no histórico de mercado. Por tanto, sus métricas sirven para demostrar la integridad técnica del circuito virtual y su reproducibilidad, **no** para afirmar que la estrategia gana dinero en EURUSD real.

No se registran métricas de rentabilidad como si fueran históricas hasta conectar un dataset EURUSD H1 verificable, versionado y con reglas de costes/slippage documentadas.

## Criterio de seguridad

La validación no contiene ninguna ruta de envío de órdenes a un broker. El resultado debe mantener:

- `real_money = false`
- `broker_orders = 0`
- `live_trading_enabled = false`

Una eventual activación de live queda fuera de este hito y requiere validación de seguridad independiente.

## Próximo hito

Conectar un dataset EURUSD H1 verificable y versionado, ejecutar una validación histórica reproducible, guardar el reporte de métricas y añadir una suite automatizada que compruebe Risk Gate, BUY/SELL, cierre, drawdown y bloqueo de dinero real.
