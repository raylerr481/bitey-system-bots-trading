# TradingSystemBot

**TradingSystemBot** es una plataforma web y, posteriormente, una aplicación móvil para investigación, backtesting y operación controlada de sistemas algorítmicos.

El repositorio conserva el nombre técnico `bitey-system-bots-trading` para no romper las integraciones existentes. El nombre visible del producto es **TradingSystemBot**.

> **Objetivo:** construir una plataforma propia de trading asistido por IA, inspirada en los flujos modernos de investigación y automatización, pero implementada desde cero y conectada a nuestro propio motor.

---

## 1. Qué vamos a construir

TradingSystemBot tendrá dos productos que comparten el mismo backend:

### A. TradingSystemBot Web

La web será el centro principal del sistema.

```text
TradingSystemBot
│
├── Dashboard
├── Analista IA
├── Mercados
├── Estrategias
├── Backtesting
├── Bot Factory
├── AI Arena
├── Portfolio
├── Risk Engine
├── Demo Trading
├── Paper Trading
├── Alertas
└── Configuración
```

La experiencia será **español primero**, con selector de:

- 🇪🇸 Español
- 🇧🇷 Português
- 🇺🇸 English

### B. Aplicación móvil TradingSystemBot

Después de estabilizar la web construiremos la aplicación móvil con **Expo / React Native**.

La aplicación no tendrá un segundo motor de trading. Utilizará el mismo backend de TradingSystemBot.

```text
                ┌─────────────────────┐
                │ TradingSystemBot Web│
                └──────────┬──────────┘
                           │
                ┌──────────▼──────────┐
                │ TradingSystemBot API│
                │      FastAPI        │
                └──────────┬──────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
      PostgreSQL        Trading Engine       IA
      / Supabase       Risk / Backtest    ChatGPT
          │                │                │
          └────────────────┼────────────────┘
                           │
                    ┌──────▼──────┐
                    │ Mobile App  │
                    │ Expo / RN   │
                    └─────────────┘
```

---

# 2. Cómo tener una web como esta

No necesitamos construir una plataforma monolítica ni empezar desde cero.

La estrategia correcta es separar **interfaz, inteligencia y ejecución**.

## Capa 1 — Frontend

La carpeta `web/` contiene la primera versión de la interfaz TradingSystemBot.

Está preparada para desplegarse en **Cloudflare Pages**.

La web debe ser responsable de:

- navegación;
- gráficos;
- formularios;
- selección de estrategias;
- visualización de posiciones;
- dashboards;
- chat con IA;
- resultados de backtesting;
- configuración del usuario.

La web **no debe guardar API keys de brokers ni claves de OpenAI**.

## Capa 2 — Backend

El backend existente es FastAPI.

Será el cerebro operativo de la plataforma:

```text
FastAPI
│
├── /api/v1/system
├── /api/v1/ai
├── /api/v1/backtest
├── /api/v1/bot-profiles
├── /api/v1/strategy
├── /api/v1/demo
├── /api/v1/trading
├── /api/v1/alpaca
└── /api/v1/mt5
```

La interfaz web llama estas APIs mediante HTTPS.

## Capa 3 — Datos

Supabase/PostgreSQL será la fuente persistente para:

- usuarios;
- perfiles;
- estrategias;
- bots;
- configuraciones;
- backtests;
- operaciones demo/paper;
- portfolios;
- eventos;
- auditoría;
- conversaciones de IA.

## Capa 4 — IA

ChatGPT será una **capa de análisis**, no una capa con permiso absoluto sobre el dinero.

La IA podrá:

- explicar mercados;
- analizar estrategias;
- comparar estrategias;
- interpretar backtests;
- detectar anomalías;
- generar hipótesis;
- explicar riesgo;
- crear informes;
- ayudar a diseñar bots;
- responder en español, portugués o inglés.

La IA no podrá:

- eliminar límites de riesgo;
- convertir demo en real por su cuenta;
- modificar un límite crítico sin autorización;
- colocar órdenes reales directamente;
- saltarse el Risk Engine.

---

# 3. Experiencia de usuario

El usuario entra y encuentra:

```text
┌─────────────────────────────────────────────────────┐
│ TradingSystemBot                 ES ▼     ● Online  │
├───────────────┬─────────────────────────────────────┤
│ Dashboard     │                                     │
│ Analista IA   │  Capital        Riesgo       Bots   │
│ Mercados      │  $10,000        1.0%         3      │
│ Estrategias   │                                     │
│ Backtesting   │  ┌───────────────────────────────┐  │
│ Bot Factory   │  │       Market Dashboard        │  │
│ AI Arena      │  │                               │  │
│ Portfolio     │  │        gráficos / señales     │  │
│ Riesgo        │  └───────────────────────────────┘  │
│ Configuración │                                     │
└───────────────┴─────────────────────────────────────┘
```

El diseño debe sentirse como una plataforma profesional de trading, pero seguir siendo comprensible para un principiante.

---

# 4. Bot Factory

El usuario podrá crear o seleccionar un bot.

Ejemplo:

```text
BOT FACTORY

Nombre: EUR/USD Trend Bot
Mercado: EUR/USD
Timeframe: 15m
Estrategia: SMA Crossover

Capital: $10,000
Máximo por posición: 2%
Pérdida diaria: 1%

[ Analizar con IA ]
[ Backtest ]
[ Ejecutar Demo ]
```

El sistema deberá explicar cada parámetro antes de permitir avanzar.

---

# 5. AI Arena

AI Arena será uno de los módulos diferenciales.

La misma evidencia se podrá analizar mediante diferentes estrategias:

```text
                 MISMA EVIDENCIA
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
   SMA Crossover    RSI + SMA       Breakout
       │               │               │
       └───────────────┼───────────────┘
                       ▼
                COMPARACIÓN IA
                       │
             Riesgo / evidencia /
             contradicciones /
             confianza / escenarios
```

La IA no elegirá automáticamente una estrategia ganadora. Presentará evidencia para que el usuario pueda decidir.

---

# 6. Backtesting

El Backtesting será un módulo real, no una pantalla decorativa.

Flujo:

```text
Datos históricos
       ↓
Estrategia
       ↓
Parámetros
       ↓
Backtest Engine
       ↓
Métricas
       ↓
Análisis IA
       ↓
Demo
       ↓
Paper Trading
```

Métricas previstas:

- retorno;
- drawdown;
- win rate;
- profit factor;
- número de operaciones;
- exposición;
- volatilidad;
- Sharpe cuando corresponda;
- peor periodo;
- sensibilidad de parámetros.

---

# 7. Trading en tiempo real

La arquitectura soportará fuentes como:

- TradingView Webhooks;
- Alpaca Paper Trading;
- MetaTrader 5 Demo;
- futuros conectores de brokers/exchanges.

Pero habrá una separación estricta:

```text
Market Data
    ↓
Strategy Engine
    ↓
Signal
    ↓
Risk Engine
    ↓
Execution Adapter
```

La IA nunca podrá saltar directamente desde:

```text
IA → Broker
```

---

# 8. Risk Engine

El Risk Engine es obligatorio.

Debe validar como mínimo:

1. capital disponible;
2. tamaño de posición;
3. pérdida máxima configurada;
4. pérdida diaria;
5. exposición total;
6. número de posiciones;
7. mercado permitido;
8. estrategia permitida;
9. estado de la cuenta;
10. emergency stop.

Si una dependencia falla:

**FAIL CLOSED.**

No se ejecuta.

---

# 9. Cloudflare

Cloudflare será la puerta de entrada de la web.

Arquitectura recomendada:

```text
Internet
   │
   ▼
Cloudflare
   │
   ├── Pages → TradingSystemBot Web
   │
   └── DNS / TLS / Security
             │
             ▼
       FastAPI Backend
             │
       ┌─────┴─────┐
       ▼           ▼
   Supabase       IA/Brokers
```

No es necesario colocar secretos en Cloudflare Pages.

Las claves privadas deben permanecer en el backend/secret manager.

---

# 10. Aplicación móvil después de la web

Cuando la web esté estable construiremos:

**TradingSystemBot App**

con Expo / React Native.

Pantallas iniciales:

```text
1. Login
2. Dashboard
3. Mercado
4. Bot Factory
5. Bot Detail
6. Backtesting
7. AI Analyst
8. AI Arena
9. Portfolio
10. Risk
11. Alerts
12. Settings
```

La aplicación consumirá la misma API:

```text
Mobile App
     ↓
FastAPI
     ↓
TradingSystemBot Engine
```

Esto evita duplicar la lógica de trading.

La guía interna de Expo recomienda comenzar las pruebas con Expo Go y crear builds personalizados solamente cuando sean necesarios. fileciteturn1file0

---

# 11. Orden correcto de construcción

No vamos a intentar construir todo al mismo tiempo.

### Fase 1 — Web Foundation

- Dashboard.
- Navegación.
- Idiomas.
- Autenticación.
- Conexión API.
- Diseño responsive.

### Fase 2 — Trading Intelligence

- Market Dashboard.
- Strategy Factory.
- Backtesting real.
- Métricas.
- AI Analyst.
- AI Arena.

### Fase 3 — Bots

- Crear bot.
- Configurar estrategia.
- Risk profile.
- Demo Loop.
- Paper Trading.
- Logs.
- Alertas.

### Fase 4 — Datos y usuarios

- Supabase.
- Usuarios.
- Portfolios.
- Historial.
- Auditoría.
- Persistencia de configuraciones.

### Fase 5 — Aplicación móvil

- Expo / React Native.
- Login.
- Dashboard móvil.
- Bots.
- Portfolio.
- IA.
- Alertas.

### Fase 6 — Real Trading

**No se habilita automáticamente.**

Primero deben pasar todas las pruebas de seguridad, auditoría, autenticación, broker connection, risk gates y emergency stop.

---

# 12. Estado actual

El repositorio ya dispone de una base funcional de:

- FastAPI.
- estrategias deterministas;
- backtesting;
- bot profiles;
- risk controls;
- demo trading;
- Alpaca Paper;
- puente MT5 Demo/read-only;
- interfaz web inicial;
- integración preparada con ChatGPT.

La implementación web actual está aislada en la rama `feature/tradingsystembot` para proteger `main` mientras se valida la nueva plataforma.

---

# 13. Principio fundamental

TradingSystemBot no será simplemente un chatbot con botones de trading.

Será un sistema compuesto:

```text
              TradingSystemBot
                     │
       ┌─────────────┼─────────────┐
       ▼             ▼             ▼
       IA        Trading Engine   Data
       │             │             │
       ▼             ▼             ▼
   Analysis       Strategies    Market Data
       │             │             │
       └─────────────┼─────────────┘
                     ▼
                 Risk Engine
                     │
                     ▼
               Execution Layer
```

La IA ayuda a **pensar**.

El motor determinista controla **qué puede hacerse**.

El Risk Engine controla **qué está permitido**.

El usuario mantiene el control final.

---

# 14. Seguridad y responsabilidad

TradingSystemBot no garantiza beneficios.

Los límites de riesgo son controles de diseño, no garantías matemáticas contra pérdidas superiores debido a gaps, slippage, liquidez u otras condiciones de mercado.

En el estado actual, la ejecución con dinero real permanece deshabilitada.
