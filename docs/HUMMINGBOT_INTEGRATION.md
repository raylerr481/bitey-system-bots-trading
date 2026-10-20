# Bitey SBT ↔ Hummingbot (read-only integration)

This bridge adds a **read-only** connection from the Bitey SBT Cloudflare Worker to a separately deployed Hummingbot API. It does not install or host Hummingbot and does not place, cancel, or modify orders.

## Endpoints

- `GET /api/v1/hummingbot/health` — checks the Hummingbot API root endpoint.
- `GET /api/v1/hummingbot/status` — reads `GET /bot-orchestration/status` using HTTP Basic Auth.
- All non-GET requests are rejected. This integration reports `execution_enabled: false`.

## Cloudflare Worker secrets / variables

Configure these in the Worker settings (do not commit credentials):

- `HUMMINGBOT_API_URL`: HTTPS base URL reachable from the Worker, preferably a private HTTPS/Tailscale-accessible endpoint.
- `HUMMINGBOT_API_USERNAME`: Hummingbot API username.
- `HUMMINGBOT_API_PASSWORD`: Hummingbot API password, stored as a secret.

Do not expose port 8000 publicly. The official Hummingbot API documentation recommends keeping the API on a private network and using Tailscale for remote access. Cloudflare Workers cannot access a service bound only to `localhost` on a personal computer; the Hummingbot API must be deployed somewhere reachable over the configured HTTPS endpoint.

## Verification

After deployment, test:

```sh
curl -i https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/hummingbot/health
curl -i https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/hummingbot/status
```

Expected before configuration: HTTP 503 and `hummingbot_not_configured`. After configuration, health should report the upstream API's version/status, and status should return the authenticated bot-orchestration status. A successful API health check does not mean a bot is trading or profitable.

## Safety boundary

- Hummingbot and MT4 remain separate execution systems.
- This bridge does not translate Bitey signals into orders.
- It does not change the USD 500 SBT operating capital, the per-trade risk limit, MT4 manual authority, or existing EA order logic.
- Do not add live order forwarding until symbol mapping, venue compatibility, idempotency, position reconciliation, limits, and a paper-trading test are implemented and reviewed.
