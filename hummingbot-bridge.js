const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store, no-cache, must-revalidate, max-age=0",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-allow-headers": "content-type"
  }
});

function configuredBase(env) {
  const raw = String(env.HUMMINGBOT_API_URL || "").trim();
  if (!raw) return { error: "hummingbot_not_configured" };
  let url;
  try { url = new URL(raw); } catch { return { error: "invalid_hummingbot_api_url" }; }
  // Cloudflare Worker should connect to a private HTTPS/Tailscale endpoint, never a public plaintext API.
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    return { error: "hummingbot_api_url_must_be_https_without_embedded_credentials" };
  }
  url.pathname = url.pathname.replace(/\/+$/, "");
  return { url };
}

function authHeader(env) {
  const username = String(env.HUMMINGBOT_API_USERNAME || "");
  const password = String(env.HUMMINGBOT_API_PASSWORD || "");
  if (!username || !password) return null;
  return "Basic " + btoa(unescape(encodeURIComponent(username + ":" + password)));
}

async function requestHummingbot(env, path, authenticated = false) {
  const config = configuredBase(env);
  if (config.error) return { ok: false, status: 503, error: config.error };
  const headers = { accept: "application/json" };
  if (authenticated) {
    const auth = authHeader(env);
    if (!auth) return { ok: false, status: 503, error: "hummingbot_credentials_not_configured" };
    headers.authorization = auth;
  }
  try {
    const target = new URL(path, config.url.toString().replace(/\/$/, "") + "/");
    const response = await fetch(target.toString(), {
      method: "GET",
      headers,
      redirect: "manual",
      signal: AbortSignal.timeout(8000)
    });
    const text = await response.text();
    let payload = null;
    try { payload = text ? JSON.parse(text) : null; } catch { payload = { message: "non_json_response" }; }
    if (response.status >= 300 && response.status < 400) {
      return { ok: false, status: 502, error: "hummingbot_redirect_blocked" };
    }
    if (!response.ok) {
      return {
        ok: false,
        status: response.status === 401 || response.status === 403 ? 502 : 503,
        error: response.status === 401 || response.status === 403 ? "hummingbot_auth_failed" : "hummingbot_api_error",
        upstream_status: response.status
      };
    }
    return { ok: true, status: response.status, data: payload };
  } catch (error) {
    return { ok: false, status: 503, error: error?.name === "TimeoutError" ? "hummingbot_timeout" : "hummingbot_unreachable" };
  }
}

export async function handleHummingbotProxy(request, env, pathname) {
  if (request.method === "OPTIONS") return json({ ok: true }, 204);
  if (request.method !== "GET") return json({ ok: false, error: "method_not_allowed", execution_enabled: false }, 405);

  if (pathname === "/api/v1/hummingbot/health") {
    const result = await requestHummingbot(env, "/");
    return json({
      ok: result.ok,
      connected: result.ok && String(result.data?.status || "").toLowerCase() === "running",
      service: "bitey-sbt-hummingbot-bridge",
      integration: "hummingbot-api",
      configured: !configuredBase(env).error,
      upstream: result.ok ? {
        name: result.data?.name || "Hummingbot API",
        version: result.data?.version || null,
        status: result.data?.status || "reachable"
      } : { error: result.error, upstream_status: result.upstream_status || null },
      mode: "read-only",
      execution_enabled: false,
      real_money_enabled: false,
      broker_orders: 0
    }, result.ok ? 200 : result.status);
  }

  if (pathname === "/api/v1/hummingbot/status") {
    const result = await requestHummingbot(env, "/bot-orchestration/status", true);
    return json({
      ok: result.ok,
      service: "bitey-sbt-hummingbot-bridge",
      data: result.ok ? result.data : undefined,
      error: result.ok ? undefined : result.error,
      upstream_status: result.ok ? undefined : result.upstream_status || null,
      mode: "read-only",
      execution_enabled: false,
      real_money_enabled: false,
      broker_orders: 0
    }, result.ok ? 200 : result.status);
  }

  return json({ ok: false, error: "not_found", available: ["/api/v1/hummingbot/health", "/api/v1/hummingbot/status"], execution_enabled: false }, 404);
}
