# TradingSystemBot / Bitey System Bots Trading

**TradingSystemBot** is the product-facing name of this algorithmic-trading suite. The repository remains `bitey-system-bots-trading` so existing integrations are preserved.

## Product objective

Research, test and operate algorithmic trading systems through:

**Research → Backtest → Demo → Paper Trading → Micro-capital → Controlled scaling**

The system is designed as an original implementation of the workflow patterns users expect from modern AI trading suites: AI research, backtesting, bot profiles, strategy comparison, risk controls and a central dashboard. It does **not** copy proprietary source code, private APIs, text, trademarks or assets from third-party sites.

## TradingSystemBot web suite

The Cloudflare-ready frontend lives in `web/` and provides:

- Spanish-first interface.
- Language selector: **Español / Português / English**.
- AI analyst chat connected to the backend.
- Strategy/backtesting laboratory entry point.
- Bot Factory with beginner/professional risk views.
- AI Arena for future strategy-vs-strategy comparison.
- Risk and safety dashboard.
- Responsive dark interface.

The frontend can be deployed as a Cloudflare Pages site with `web/` as the published directory. Set `window.TRADINGSYSTEMBOT_API` in `web/config.js` to the public FastAPI backend URL when frontend and backend are deployed separately.

## ChatGPT integration

The backend exposes `POST /api/v1/ai/chat` and `GET /api/v1/ai/status`. It uses the OpenAI **Responses API** server-side, so the API key is never placed in browser JavaScript. Configure:

```text
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-5.6-luna
```

The AI is an advisory/research layer. It cannot bypass deterministic risk controls and has no authority to place real orders. The OpenAI Responses API supports text generation and tool/function integrations; TradingSystemBot can later add read-only market-data tools without giving the model direct execution authority.

## Existing trading engine preserved

The existing engine remains intact: Alpaca paper integration, MetaTrader 5 demo/read-only bridge, deterministic strategies, backtesting, demo loop, bot profiles and risk controls. Real-money execution remains disabled until the safety architecture is fully validated.

## Safety

No bot, strategy or AI system guarantees profits. Configured loss limits are controls, not promises; gaps, slippage, liquidity and execution conditions can produce larger losses. Real-money trading remains fail-closed.
