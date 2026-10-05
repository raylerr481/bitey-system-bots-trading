create table if not exists public.backtest_evidence (
  id uuid primary key default gen_random_uuid(),
  evidence_key text not null unique,
  source text not null default 'MT4',
  evidence_class text not null default 'BACKTEST',
  strategy_id text,
  strategy_version text,
  bot_id text,
  symbol text not null,
  timeframe text not null,
  test_start timestamptz,
  test_end timestamptz,
  parameters jsonb not null default '{}'::jsonb,
  metrics jsonb not null default '{}'::jsonb,
  costs jsonb not null default '{}'::jsonb,
  validation jsonb not null default '{}'::jsonb,
  market_context jsonb not null default '{}'::jsonb,
  raw_report jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_backtest_evidence_strategy_tf
  on public.backtest_evidence (strategy_id, symbol, timeframe);
create index if not exists idx_backtest_evidence_created_at
  on public.backtest_evidence (created_at desc);

alter table public.backtest_evidence enable row level security;

create policy "service role manages backtest evidence"
  on public.backtest_evidence
  for all
  to service_role
  using (true)
  with check (true);
