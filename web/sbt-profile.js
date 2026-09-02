(() => {
  'use strict';

  const state = {
    ai_provider: 'bitey', ai_connection_mode: 'api', platform: 'mt5', execution_mode: 'demo',
    permissions: ['read_market', 'research'], automation_enabled: false,
    risk_limits: { max_position_pct: 0.02, max_daily_loss_pct: 0.01 }, status: 'draft'
  };
  const $ = (id) => document.getElementById(id);
  const apiBase = () => (window.SBT_API_URL || localStorage.getItem('sbt_api_base') || '').replace(/\/$/, '');

  function accessToken() {
    const direct = localStorage.getItem('sbt_access_token') || localStorage.getItem('access_token');
    if (direct) return direct;
    for (let i = 0; i < localStorage.length; i += 1) {
      const key = localStorage.key(i) || '';
      if (!key.startsWith('sb-') || !key.endsWith('-auth-token')) continue;
      try { const raw = JSON.parse(localStorage.getItem(key)); if (raw?.access_token) return raw.access_token; } catch (_) {}
    }
    return '';
  }

  async function api(path, options = {}) {
    const headers = Object.assign({ 'Content-Type': 'application/json' }, options.headers || {});
    const token = accessToken();
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await fetch(`${apiBase()}${path}`, Object.assign({}, options, { headers }));
    let body = null; try { body = await response.json(); } catch (_) {}
    if (!response.ok) throw new Error(body?.detail || body?.message || `HTTP ${response.status}`);
    return body;
  }

  function setStatus(text) { if ($('apiStatus')) $('apiStatus').textContent = text; }
  function updateDashboard() {
    if ($('dashAI')) $('dashAI').textContent = state.ai_provider;
    if ($('dashPlatform')) $('dashPlatform').textContent = state.platform ? state.platform.toUpperCase() : '—';
    if ($('dashAutomation')) $('dashAutomation').textContent = state.automation_enabled ? 'Activa' : 'Manual';
    if ($('userState') && accessToken()) $('userState').textContent = 'Autenticado';
  }

  function applyProfile(profile) {
    if (!profile) return;
    Object.assign(state, profile);
    state.permissions = Array.isArray(profile.permissions) ? profile.permissions : state.permissions;
    state.risk_limits = profile.risk_limits || state.risk_limits;
    document.querySelectorAll('#aiChoices button[data-ai]').forEach(b => b.classList.toggle('selected', b.dataset.ai === state.ai_provider));
    document.querySelectorAll('#platformChoices button[data-platform]').forEach(b => b.classList.toggle('selected', b.dataset.platform === state.platform));
    document.querySelectorAll('#permissionChoices button[data-permission]').forEach(b => b.classList.toggle('selected', state.permissions.includes(b.dataset.permission)));
    if ($('automation')) $('automation').checked = !!state.automation_enabled;
    updateDashboard();
  }

  async function loadRegistries() {
    const [aiResponse, platformResponse] = await Promise.all([
      api('/api/v1/registry/ai/providers'), api('/api/v1/registry/platforms')
    ]);
    const ais = Array.isArray(aiResponse) ? aiResponse : (aiResponse?.providers || []);
    const platforms = Array.isArray(platformResponse) ? platformResponse : (platformResponse?.platforms || []);
    const allowedAI = new Set(ais.filter(x => x.enabled !== false).map(x => x.id));
    document.querySelectorAll('#aiChoices button[data-ai]').forEach(b => {
      const enabled = allowedAI.has(b.dataset.ai); b.disabled = !enabled; b.style.opacity = enabled ? '' : '.45';
    });
    const allowedPlatforms = new Set(platforms.map(x => x.id));
    document.querySelectorAll('#platformChoices button[data-platform]').forEach(b => {
      const enabled = allowedPlatforms.has(b.dataset.platform); b.disabled = !enabled; b.style.opacity = enabled ? '' : '.45';
    });
  }

  async function loadProfile() {
    if (!accessToken()) { setStatus('Regístrate para guardar tu entorno'); return; }
    try { applyProfile(await api('/api/v1/user/trading-profile')); setStatus('Entorno cargado'); }
    catch (error) { setStatus(`Perfil: ${error.message}`); }
  }

  async function saveProfile() {
    if (!accessToken()) throw new Error('Debes iniciar sesión para guardar la configuración.');
    const payload = {
      ai_provider: state.ai_provider, ai_connection_mode: state.ai_connection_mode, platform: state.platform,
      execution_mode: state.execution_mode, permissions: state.permissions, risk_limits: state.risk_limits,
      bot_id: state.bot_id || null, strategy_id: state.strategy_id || null,
      automation_enabled: state.automation_enabled, status: 'configured', metadata: { source: 'sbt-web', version: 'registry-v1' }
    };
    const saved = await api('/api/v1/user/trading-profile', { method: 'PUT', body: JSON.stringify(payload) });
    applyProfile(saved); return saved;
  }

  function wireChoices() {
    document.querySelectorAll('#aiChoices button[data-ai]').forEach(button => button.addEventListener('click', () => {
      state.ai_provider = button.dataset.ai;
      state.ai_connection_mode = state.ai_provider === 'bitey' ? 'api' : (state.ai_provider === 'codex' ? 'mcp' : 'api');
      document.querySelectorAll('#aiChoices button[data-ai]').forEach(b => b.classList.toggle('selected', b === button)); updateDashboard();
    }));
    document.querySelectorAll('#platformChoices button[data-platform]').forEach(button => button.addEventListener('click', () => {
      state.platform = button.dataset.platform; state.execution_mode = state.platform === 'mt5' ? 'demo' : 'paper';
      document.querySelectorAll('#platformChoices button[data-platform]').forEach(b => b.classList.toggle('selected', b === button)); updateDashboard();
    }));
    document.querySelectorAll('#permissionChoices button[data-permission]').forEach(button => button.addEventListener('click', () => {
      const p = button.dataset.permission;
      state.permissions = state.permissions.includes(p) ? state.permissions.filter(x => x !== p) : [...state.permissions, p];
      button.classList.toggle('selected', state.permissions.includes(p));
    }));
    if ($('automation')) $('automation').addEventListener('change', e => { state.automation_enabled = e.target.checked; updateDashboard(); });
  }

  function wireSave() {
    const button = $('buildPlan'); if (!button) return;
    button.addEventListener('click', async () => {
      const result = $('planResult');
      try {
        button.disabled = true; button.textContent = 'Validando y guardando…';
        const saved = await saveProfile();
        if (result) { result.style.display = 'block'; result.innerHTML = `<strong>Configuración guardada.</strong><br>IA: ${saved.ai_provider} · Plataforma: ${saved.platform || 'sin seleccionar'} · Modo: ${saved.execution_mode}.<br>Risk Gate: obligatorio · Live trading: BLOQUEADO.`; }
        setStatus('Configuración validada');
      } catch (error) {
        if (result) { result.style.display = 'block'; result.style.background = '#2a1414'; result.style.borderColor = '#673131'; result.style.color = '#ffb1b1'; result.textContent = `No se guardó: ${error.message}`; }
        setStatus('Validación pendiente');
      } finally { button.disabled = false; button.textContent = 'Generar plan de implementación'; }
    });
  }

  async function init() {
    if (!apiBase()) return;
    try { await loadRegistries(); await loadProfile(); } catch (error) { setStatus(`API no disponible: ${error.message}`); }
    wireChoices(); wireSave(); updateDashboard();
  }
  window.SBTProfile = { state, saveProfile, loadProfile };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
