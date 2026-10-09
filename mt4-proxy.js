const DEFAULT_API_BASE = "https://bitey-system-bots-trading-api.onrender.com";
const MAX_BODY_BYTES = 1024 * 1024;

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "Content-Type, X-MT4-Token, Authorization",
  "cache-control": "no-store",
};

function json(data, status = 200, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...corsHeaders, ...extra },
  });
}

function apiBase(env) {
  return String(env.SBT_API_BASE || DEFAULT_API_BASE).replace(/\/+$/, "");
}

async function forward(request, env, path) {
  const target = apiBase(env) + path;
  const headers = new Headers({ accept: "application/json" });
  const token = request.headers.get("x-mt4-token");
  if (token) headers.set("x-mt4-token", token);

  const init = { method: request.method, headers };
  if (request.method === "POST") {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
      return json({ ok: false, error: "payload_too_large", max_bytes: MAX_BODY_BYTES }, 413);
    }
    let payload;
    try { payload = JSON.parse(raw); }
    catch { return json({ ok: false, error: "invalid_json" }, 400); }

    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return json({ ok: false, error: "json_object_required" }, 400);
    }
    if (!String(payload.symbol || "").trim() || !String(payload.timeframe || "").trim()) {
      return json({ ok: false, error: "symbol_and_timeframe_required" }, 422);
    }
    if (path.endsWith("/trade-closed")) {
      if (!Number.isInteger(Number(payload.ticket)) ||
          !["BUY", "SELL"].includes(String(payload.side || "").toUpperCase()) ||
          !Number.isFinite(Number(payload.open_price)) ||
          !Number.isFinite(Number(payload.close_price)) ||
          !String(payload.open_time || "").trim() ||
          !String(payload.close_time || "").trim()) {
        return json({ ok: false, error: "invalid_closed_trade_contract" }, 422);
      }
    }
    headers.set("content-type", "application/json; charset=utf-8");
    init.body = JSON.stringify(payload);
  }

  let upstream;
  try {
    upstream = await fetch(target, init);
  } catch (error) {
    return json({
      ok: false,
      error: "sbt_backend_unreachable",
      detail: String(error && error.message || error),
      upstream: apiBase(env),
    }, 502);
  }

  const body = await upstream.text();
  const outHeaders = new Headers(corsHeaders);
  outHeaders.set("content-type", upstream.headers.get("content-type") || "application/json; charset=utf-8");
  return new Response(body, { status: upstream.status, headers: outHeaders });
}

export async function handleMt4Proxy(request, env, pathname) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });

  if (pathname === "/api/v1/mt4/health") {
    try {
      const response = await fetch(apiBase(env) + "/api/v1/mt4/active-bot", {
        headers: { accept: "application/json" },
      });
      if (!response.ok) {
        return json({ ok: false, connected: false, backend_status: response.status, error: "mt4_status_unavailable" }, 502);
      }
      const data = await response.json();
      return json({
        ok: true,
        connected: Boolean(data.connected),
        source: data.source || "MT4_DESKTOP",
        last_seen: data.last_seen || null,
        bot: data.bot || null,
        account: data.account ? {
          mode: data.account.mode || data.account.reported_mode || "UNKNOWN",
          position_count: data.account.position_count ?? null,
        } : null,
        upstream: "sbt-api",
      });
    } catch (error) {
      return json({ ok: false, connected: false, error: "sbt_backend_unreachable", detail: String(error && error.message || error) }, 502);
    }
  }

  const allowed = new Map([
    ["/api/v1/mt4/bitey-report", { method: "POST", upstream: "/api/v1/mt4/bitey-report" }],
    ["/api/v1/mt4/trade-closed", { method: "POST", upstream: "/api/v1/mt4/trade-closed" }],
    ["/api/v1/mt4/active-bot", { method: "GET", upstream: "/api/v1/mt4/active-bot" }],
    ["/api/v1/mt4/trades", { method: "GET", upstream: "/api/v1/mt4/trades" }],
  ]);
  const route = allowed.get(pathname);
  if (!route) return json({ ok: false, error: "mt4_route_not_found" }, 404);
  if (request.method !== route.method) {
    return json({ ok: false, error: "method_not_allowed", allowed_method: route.method }, 405, { allow: route.method });
  }
  return forward(request, env, route.upstream);
}
