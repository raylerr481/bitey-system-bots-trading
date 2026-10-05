create table if not exists public.research_experiments (
  id uuid primary key default gen_random_uuid(),
  experiment_id text not null unique,
  parent_experiment_id text,
  symbol text not null,
  strategy text not null,
  strategy_timeframe text not null,
  chart_timeframe text,
  stage text not null default 'DISCOVERED',
  source text not null default 'BITEY_SBT',
  hypothesis jsonb not null default '{}'::jsonb,
  feature_candidates jsonb not null default '[]'::jsonb,
  baseline_evidence jsonb not null default '{}'::jsonb,
  enhanced_evidence jsonb not null default '{}'::jsonb,
  validation jsonb not null default '{}'::jsonb,
  evolution_status jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_research_experiments_experiment on public.research_experiments(experiment_id);
create index if not exists idx_research_experiments_stage on public.research_experiments(stage);
alter table public.research_experiments enable row level security;
drop policy if exists "service role full access research experiments" on public.research_experiments;
create policy "service role full access research experiments" on public.research_experiments for all to service_role using (true) with check (true);
alter table public.backtest_evidence add column if not exists experiment_id text;
create index if not exists idx_backtest_evidence_experiment on public.backtest_evidence(experiment_id);