alter table public.backtest_evidence add column if not exists chart_timeframe text;
alter table public.backtest_evidence add column if not exists experiment_id text;
create index if not exists idx_backtest_evidence_strategy_tf on public.backtest_evidence(strategy_id, symbol, timeframe);
create index if not exists idx_backtest_evidence_experiment on public.backtest_evidence(experiment_id);
