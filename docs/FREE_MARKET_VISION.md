# Bitey SBT — Free Universal Quant Vision

Bitey SBT will provide a free research and simulation environment for everyone. The product architecture is inspired by useful capabilities observed in professional algorithmic-trading platforms, but implementation, UX, code and terminology remain original to Bitey.

## Free core

The SBT core is designed to remain free: market/instrument abstraction, chart engine, Bot Lab, deterministic strategy specifications, backtesting, Expected Value, robustness research, risk controls, strategy registry, trade visualization, demo/paper workflows and audit contracts.

External market-data providers, brokers, exchanges and optional AI services may have their own restrictions or costs. SBT must never silently create paid usage or claim that unavailable data is free.

## Quant workflow

Research → Strategy Design → Multi-Market/Timeframe → Backtest → Out-of-Sample → Robustness → Monte Carlo → Walk-Forward → Expected Value → Risk Gate → Demo/Paper → Monitor → Revalidate.

## Market universe

The architecture targets Forex, crypto, indices, commodities, stocks and ETFs. An instrument is only presented as available when its source/provider actually exposes or confirms it. SBT must not fabricate prices, candles or provider availability.

## Strategy research

SBT should progressively support manual/no-code rules and AI-assisted proposals, deterministic strategy generation, parameter sweeps, multiple OOS periods, robustness checks, Monte Carlo simulations, Walk-Forward analysis, portfolio analysis, MAE/MFE, drawdown and trade-level visualization.

AI proposes; deterministic SBT engines and the Risk Gate decide what is technically permitted.

## Execution boundary

The current implementation remains market-data/demo/paper oriented. Real-money execution stays locked and broker orders remain zero until the required technical, security, operational, legal and user-confirmation gates are explicitly implemented.

## Originality

Bitey SBT may solve the same general problems as other quantitative trading tools, but it must not copy competitor source code, branding, artwork, text, screenshots or distinctive implementation details.
