# Bitey SBT — AI and Trading Tool Integration

## AI choice

Bitey SBT is a free, model-agnostic platform. A user can select Bitey Trading Intelligence, ChatGPT/OpenAI, Claude/Anthropic, Gemini/Google, DeepSeek, or another supported provider.

The selected provider can be exclusive. Exclusive mode means no silent fallback to another AI.

## How AI connects to trading platforms

The generic mechanisms are:

- REST/HTTP APIs
- official broker/exchange SDKs
- Model Context Protocol (MCP) tool servers
- function/tool calling
- webhooks
- local CLI/terminal bridges when explicitly authorized

The AI does not receive unrestricted trading access. It proposes a structured tool call. SBT validates the tool, parameters, account/mode, strategy status and risk limits before an execution-capable action is allowed.

## Existing strategies and bots

SBT may contain a registry of community, third-party or previously published strategies. A strategy is never presented as guaranteed profitable. Before use, SBT records provenance, version, test period, costs/slippage assumptions, drawdown, out-of-sample evidence, robustness, validation freshness and execution mode.

A free or paid third-party strategy may be available to users. Any external purchase, subscription, broker/data fee or AI-provider fee belongs to the user unless Bitey explicitly states otherwise.

## User registration

User accounts are implemented through Supabase Auth. The backend exposes email/password registration and sign-in endpoints while keeping the Supabase anonymous/public key boundary separate from service-role credentials. Supabase Auth provides JWT-based authentication and can be combined with database Row Level Security.

Required production configuration:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- Supabase Auth email confirmation/redirect settings
- RLS policies for user-owned SBT data

No provider API secret belongs in the browser, Git repository or logs.

## Trading safety

AI selection and AI billing controls are separate from trading risk controls.

`AI Cost Guard` protects the user's external AI-provider spending.

`SBT Risk Gate` protects the trading account and can block orders regardless of which AI proposed them.

Current backend live trading remains disabled. Demo and paper modes are the safe integration baseline.
