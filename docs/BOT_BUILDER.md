# SBT Bot Builder

Bitey SBT debe permitir construir bots algorítmicos desde una especificación cuantitativa y elegir el lenguaje de salida.

## Flujo

1. Seleccionar mercado/símbolo y timeframe.
2. Definir reglas de entrada y salida con indicadores/formulas del Quant Engine.
3. Definir riesgo: riesgo por operación, stop ATR/fijo, take profit, exposición máxima.
4. Elegir lenguaje: **Python**, **MQL5**, **Pine Script** o **JavaScript/TypeScript**.
5. Generar código desde una especificación intermedia (Bot Specification), no directamente desde texto libre.
6. Validar sintaxis y reglas contra el contrato de SBT.
7. Ejecutar backtest/stress-test/validación virtual antes de cualquier demo.
8. Mantener siempre `live=false`, `real_money=false`, `broker_orders=0`.

## Regla de arquitectura

El lenguaje es una capa de generación. Las fórmulas, indicadores, señales y reglas de riesgo permanecen en la especificación cuantitativa común para evitar que Python, MQL5, Pine o TypeScript produzcan estrategias matemáticamente distintas.

## Lenguajes iniciales

- Python: investigación, backtesting y prototipos.
- MQL5: Expert Advisors para MetaTrader 5, inicialmente en modo demo/no-live.
- Pine Script: indicadores y estrategias para TradingView.
- TypeScript/JavaScript: bots/servicios de integración y ejecución simulada.

## Seguridad

La generación de código nunca habilita automáticamente órdenes reales. Cualquier transición futura hacia demo/paper/live debe pasar por el Risk Gate y por validaciones explícitas e independientes.
