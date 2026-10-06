create table if not exists public.trading_monthly_growth (
  id uuid primary key default gen_random_uuid(),
  scope_key text not null,
  month_start date not null,
  month_end date not null,
  environment text not null default 'DEMO' check (environment in ('DEMO', 'REAL', 'PAPER')),
  initial_capital_usd numeric not null check (initial_capital_usd > 0),
  opening_capital_usd numeric not null check (opening_capital_usd > 0),
  net_pnl_usd numeric not null default 0,
  capital_end_usd numeric not null check (capital_end_usd >= 0),
  growth_pct numeric not null default 0,
  gross_profit_usd numeric not null default 0,
  gross_loss_usd numeric not null default 0,
  trades integer not null default 0 check (trades >= 0),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  win_rate_pct numeric not null default 0 check (win_rate_pct >= 0 and win_rate_pct <= 100),
  max_drawdown_usd numeric not null default 0 check (max_drawdown_usd >= 0),
  max_drawdown_pct numeric not null default 0 check (max_drawdown_pct >= 0),
  q_learning_reward numeric not null default 0 check (q_learning_reward >= -1 and q_learning_reward <= 1),
  risk_gate jsonb not null default '{}'::jsonb,
  safety jsonb not null default '{}'::jsonb,
  report jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (scope_key, month_start)
);

alter table public.trading_monthly_growth enable row level security;
revoke all on public.trading_monthly_growth from anon, authenticated;
grant all on public.trading_monthly_growth to service_role;
