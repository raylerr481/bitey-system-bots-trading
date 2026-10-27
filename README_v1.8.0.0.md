# Bitey Ensemble Scalper MultiAsset — v1.8.0.0 ThirtyEvaluatorsExperimental

Rama: `experimental/30-evaluators-two-assemblies-csv-audit`

> **Estado: EXPERIMENTAL.** Sin validación de rendimiento. Probar en el Strategy Tester (cada tick, comisión real) y en demo antes de cualquier uso real. La sección «Limitaciones conocidas» describe diferencias entre la intención del diseño y el comportamiento actual del código.

## 1. Qué es

EA de MetaTrader 4 (MQL4) para scalping/day trading, **multiactivo** (hasta **5 posiciones simultáneas, una por activo**), **multidireccional** (BUY y SELL), con **SL/TP adaptativos**, **30 evaluadores** organizados en **2 asambleas de elección** y **registro CSV de auditoría** de decisiones, operaciones y ajustes de salida.

## 2. Reglas de integración

| # | Regla | Dónde se aplica |
|---|-------|-----------------|
| R1 | Máximo 5 posiciones abiertas, una por activo (`HARD_MAX_POSITIONS=5`, `InpMaxOpenPositions` se limita a 1..5). | `MaxPositions()`, `HasPositionForKey()` |
| R2 | BUY y SELL permitidos (`InpAllowBuy`, `InpAllowSell`); la dirección la decide la Asamblea 2. | `Analyze()` |
| R3 | 30 evaluadores = 6 familias × 5 variantes, votos `BUY / SELL / ABSTAIN`. | `Analyze()` |
| R4 | Asamblea 2 decide dirección por consenso de familias; Asamblea 1 elige qué activos ejecutar. | `Analyze()`, `RunCycle()` |
| R5 | SL y TP adaptativos (ATR) y adaptados a la ganancia neta (después de costos). | `OpenTrade()`, `ManageExits()` |
| R6 | El tipo de cuenta (demo/real) no condiciona la operativa. | `OnInit()` (`accountMode=NOT_A_GATE`) |
| R7 | Cada decisión, voto, orden, modificación y cierre se registra en CSV con un `decision_id` común. | módulo `BiteyCsv*` |

## 3. Flujo de decisión

```
Por cada símbolo, una vez por barra cerrada (M15 por defecto)
  │
  ├─ Prefilter: trading permitido, rollover, viernes, historial, cotización fresca,
  │             sesión, sin posición abierta, cooldown, expectativa negativa, spread
  │
  ├─ 30 evaluadores → votos (CSV: EvaluatorVotes)
  │
  ├─ ASAMBLEA 2 (dirección): consenso por familias + filtro HTF
  │       → BUY / SELL / ABSTAIN (CSV: TradeAssembly)
  │
  ├─ ASAMBLEA 1 (activos): ranking de candidatos por score − penalización de solapamiento
  │       + guardia de correlación → selección (CSV: AssetAssembly)
  │
  └─ OpenTrade: filtro de costos, riesgo, lotes, SL/TP inicial → orden (CSV: TradeAudit)
        └─ ManageExits: SL/TP adaptativo, salidas por tiempo/reversión/rollover (CSV: AdaptiveExits, ClosedTrades)
```

## 4. Los 30 evaluadores

Seis familias de cinco variantes cada una (parámetros distintos por variante):

| Familia | Evaluadores | Señal |
|---------|-------------|-------|
| `EMA_TREND` | EMA_1..5 | EMA rápida vs lenta + precio sobre la rápida + pendiente |
| `MACD_TREND` | MACD_1..5 | MACD vs señal + pendiente del MACD |
| `BREAKOUT` | DONCHIAN_1..5 | Cierre rompe el máximo/mínimo de N barras |
| `RSI_MOMENTUM` | RSI_MOMENTUM_1..5 | RSI >52 subiendo (<75) o <48 bajando (>25) |
| `MEAN_REVERSION` | BOLLINGER_REENTRY_1..5 | Reentrada a las bandas de Bollinger |
| `MEAN_REVERSION` | STOCHASTIC_1..5 | Cruce del estocástico desde zona extrema |

## 5. Las dos asambleas

**Asamblea 2 — dirección (por activo).** Cada familia vota BUY/SELL si al menos `InpAssemblyMinModelVotes` (3 de 5) de sus modelos coinciden y superan a los contrarios.

- **Régimen de tendencia** (`ADX ≥ InpTrendADX`, 20): las 4 primeras familias deciden; se requieren `InpAssemblyMinFamilies` (3 de 4) a favor y como máximo 1 en contra.
- **Régimen de rango** (`ADX < 20`): solo si `InpAllowRangeRegime=true` (por defecto **false**): las dos familias de reversión deben coincidir y el RSI14 estar en zona favorable.
- Filtro de tendencia en H1 (EMA50) si `InpUseHTFFilter`.
- Score: `10 × familias_a_favor + min(ADX,40)/4 − 30 × min(costoR,2) − 2 × familias_en_contra`.

**Asamblea 1 — activos.** Reúne los candidatos aprobados por la Asamblea 2 y los ordena por `score − InpDiversifyPenalty × solapamiento` (se reordena tras cada entrada), aplicando la guardia de correlación:
- máx. `InpMaxCryptoPositions` (2) criptos simultáneas;
- máx. `InpMaxCcyExposure` (2) posiciones netas en la misma dirección sobre una divisa FX;
- máx. `InpMaxCcyGross` (3) posiciones que toquen una misma divisa FX en cualquier dirección.

## 6. SL/TP adaptativo

- **Inicial:** SL = `InpStopATR` (1.5) × ATR (mínimo spread + nivel del broker); TP = `InpRewardRisk` (1.8) × distancia del SL.
- **Break-even:** con ganancia ≥ `InpBreakEvenTriggerATR` (1.0 ATR) el SL pasa a entrada + `InpBreakEvenLockATR` (0.15 ATR) + comisión.
- **Trailing por ATR:** desde 1.2 ATR, distancia 0.9 ATR que se estrecha 0.15 ATR por cada ATR extra de ganancia (mínimo 0.45 ATR), paso mínimo 0.08 ATR.
- **Bloqueo de ganancia neta (en R):** con ganancia neta ≥ 0.50 R el SL asegura +0.10 R neto tras costos estimados, subiendo en pasos de 0.05 R.
- **TP expandible:** con ganancia ≥ 1.5 ATR, ADX ≥ 22 y TP a menos de 1 ATR, se extiende (paso 0.25 ATR, máx. 5 ATR).
- **Salidas adicionales:** tiempo (48 barras), cruce EMA 9/21 confirmado con ganancia neta ≥ 0, rollover y cierre de viernes (no cripto; `*USDT` 24/7).
- El SL solo se mueve a favor de la operación.

## 7. Gestión de riesgo

- Riesgo por operación 0.5 % del capital de referencia (`InpReferenceCapitalUSD`, o `min(balance, equity)` con `InpUseEquityRisk`), incluyendo comisión round-turn; riesgo agregado máx. 2.5 %.
- Filtro de costos: spread + comisión ≤ `InpMaxCostR` (0.20) del stop; spread ≤ 10 % del stop.
- Tope de lotes: FX 0.30, otros 0.10.
- Frenos: pérdida diaria 3 %, drawdown mensual 8 %, racha de 4 pérdidas (pausa 60 min), expectativa negativa por símbolo (ban 24 h), suelo de equity opcional.

## 8. Auditoría CSV

Carpeta: `MQL4\Files` del terminal. Separador `;`. Marca de tiempo = hora del servidor del broker (`TimeCurrent()`).
`decision_id` = `<símbolo>_<hora unix de la barra evaluada>`; une votos, asambleas, orden, ajustes y cierre.

| Archivo | Contenido |
|---------|-----------|
| `Bitey_ActionLog.csv` | Diario cronológico de decisiones, rechazos, selección, apertura, ajustes y cierre. |
| `Bitey_EvaluatorVotes.csv` | Un voto por evaluador (30 filas por evaluación): dirección, score, confianza, validez. |
| `Bitey_TradeAssembly.csv` | Veredicto de la Asamblea 2 (BUY/SELL/ABSTAIN), consenso, modelos a favor/en contra. |
| `Bitey_AssetAssembly.csv` | Candidatos y selección de la Asamblea 1, incluidos los rechazos del prefiltro. |
| `Bitey_TradeAudit.csv` | Apertura: lotes, precio, SL/TP inicial, riesgo estimado. |
| `Bitey_AdaptiveExits.csv` | Cada cambio de SL/TP: valores anterior y nuevo, resultado neto del momento. |
| `Bitey_ClosedTrades.csv` | Cierre: bruto, comisión, swap, neto, duración. |
| `Bitey_Performance.csv` | Se crea con cabecera; el EA aún no escribe filas. |
| `Bitey_Ens_TradeAudit_<magic>.csv` | Auditoría por operación con MFE/MAE (heredada de v1.4). |
| `Bitey_Ens_NetByAsset_<magic>.csv` | Resumen neto por activo, actualizado cada 60 s. |

Notas: con `InpLogTradesCSV=false` se desactiva también `Bitey_ClosedTrades.csv`. Configurar el historial de cuenta de MT4 en «Todo el historial».

## 9. Limitaciones conocidas (por corregir antes de confiar en los resultados)

1. **Pool de candidatos limitado por los cupos libres.** El corte `CountOpenPositions()+nc>=maxPos` hace que solo los primeros N símbolos (en orden de Market Watch) entren al ranking; el resto se marca como evaluado y se descarta. El ranking y la penalización por solapamiento solo reordenan ese subconjunto.
2. **10 de los 30 evaluadores no deciden con la configuración por defecto.** Las familias de reversión (Bollinger, Estocástico) solo actúan con `InpAllowRangeRegime=true`; en tendencia deciden 20 modelos.
3. **Auditoría incompleta:**
   - tras `SELECT` no se registra el resultado si `OpenTrade` rechaza (costo, spread, riesgo, correlación, `ORDER_REJECTED`);
   - `close_reason` guarda el comentario de entrada, no el motivo real del cierre (el motivo solo se imprime en el Diario);
   - `slippage_points`, `expected_net_estimate`, `estimated_cost`, spread/comisión/slippage estimados se escriben siempre como 0;
   - los ajustes de salida usan el motivo genérico `ADAPTIVE_SLTP_UPDATE` (no distinguen BE, trailing, bloqueo neto, TP);
   - no existe «sin CSV no se abren operaciones».
4. **Volumen y rendimiento del registro:** se abre y cierra el archivo en cada fila; con ~114 símbolos se pueden generar miles de filas por barra.
5. **Código residual:** `Vote()`, `FamilyDir()`, `EnvelopeVotes()` e inputs `InpFamilyMinVotes`, `InpUseEnvelopeFamily`, `InpEnvelope*` no tienen efecto; algunos comentarios de cabecera y los presets A/B están desactualizados.

## 10. Checklist de aceptación

- [ ] Compila sin errores ni advertencias en MT4.
- [ ] Nunca más de 5 posiciones abiertas, una por activo.
- [ ] Se observan BUY y SELL en el probador.
- [ ] Cada evaluación genera 30 filas en `Bitey_EvaluatorVotes.csv` con el mismo `decision_id` que la Asamblea 2.
- [ ] Todo candidato seleccionado termina en una orden o en un rechazo registrado con motivo.
- [ ] El SL solo avanza a favor en `Bitey_AdaptiveExits.csv`.
- [ ] `Bitey_ClosedTrades.csv` reconcilia con el historial del broker (ticket, neto).
- [ ] Backtest + demo documentados (periodo, activos, parámetros, resultados).
