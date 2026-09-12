(() => {
  const CATALOG = [
    { group: 'Forex', items: ['EURUSD','GBPUSD','USDJPY','USDCHF','AUDUSD','USDCAD','NZDUSD','EURGBP','EURJPY','GBPJPY'] },
    { group: 'Cripto', items: ['BTCUSD','ETHUSD','SOLUSD','XRPUSD','ADAUSD','DOGEUSD'] },
    { group: 'Índices', items: ['SPX500','NAS100','US30','GER40','UK100','JPN225','US2000','IBOV'] },
    { group: 'Acciones', items: ['AAPL','MSFT','NVDA','AMZN','TSLA','META','GOOGL','BRK.B','VALE3','PETR4','ITUB4'] },
    { group: 'Materias primas', items: ['XAUUSD','XAGUSD','USOIL','UKOIL','NATGAS'] },
    { group: 'ETFs', items: ['SPY','QQQ','IWM','DIA','EWZ'] }
  ];
  const ALL = CATALOG.flatMap(x => x.items);

  function state() { return window.BiteySBTMarketState; }
  function setStatus(text) { const el = document.getElementById('sbtMarketUniverseState'); if (el) el.textContent = text; }

  function renderWatchlist() {
    const s = state();
    const body = document.getElementById('mtWatchBody');
    if (!s || !body) return false;
    body.innerHTML = '';
    ALL.forEach(symbol => {
      const row = document.createElement('tr');
      row.dataset.symbol = symbol;
      row.style.cursor = 'pointer';
      row.innerHTML = `<td>${symbol}</td><td>—</td><td>—</td>`;
      row.addEventListener('click', () => selectSymbol(symbol));
      body.appendChild(row);
    });
    refreshSelection();
    return true;
  }

  function refreshSelection() {
    const s = state();
    document.querySelectorAll('#mtWatchBody tr[data-symbol]').forEach(row => {
      row.classList.toggle('active', !!s && row.dataset.symbol === s.symbol);
    });
  }

  function selectSymbol(symbol) {
    const s = state();
    if (!s) return;
    s.symbol = symbol;
    s.viewEnd = null;
    s.candles = [];
    s.quote = null;
    const page = document.getElementById('bot-lab-page');
    if (page) delete page.dataset.webTraderReady;
    setStatus(`${symbol} · solicitando datos reales…`);
    if (window.BiteyWebTrader && typeof window.BiteyWebTrader.init === 'function') window.BiteyWebTrader.init();
    setTimeout(() => { renderWatchlist(); refreshSelection(); }, 250);
  }

  function install() {
    const page = document.getElementById('bot-lab-page');
    const s = state();
    if (!page || !s) return false;

    if (!page.dataset.marketUniverseReady) {
      const anchor = page.querySelector('#mtWatchBody');
      if (!anchor || !anchor.parentElement || !anchor.parentElement.parentElement) return false;
      const wrap = document.createElement('div');
      wrap.className = 'card';
      wrap.style.margin = '0 0 12px';
      wrap.innerHTML = '<div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap"><strong>Instrumento</strong><select id="sbtMarketUniverse" style="min-width:240px;background:#080d13;border:1px solid #1e2936;color:#fff;border-radius:9px;padding:9px"></select><span id="sbtMarketUniverseState" class="small">La fuente determina la disponibilidad real.</span></div>';
      anchor.parentElement.parentElement.insertBefore(wrap, anchor.parentElement);
      const select = wrap.querySelector('#sbtMarketUniverse');
      CATALOG.forEach(section => {
        const group = document.createElement('optgroup');
        group.label = section.group;
        section.items.forEach(symbol => {
          const option = document.createElement('option');
          option.value = symbol;
          option.textContent = symbol;
          group.appendChild(option);
        });
        select.appendChild(group);
      });
      select.value = s.symbol;
      select.addEventListener('change', () => selectSymbol(select.value));
      page.dataset.marketUniverseReady = '1';
    }

    const select = document.getElementById('sbtMarketUniverse');
    if (select && state().symbol && ALL.includes(state().symbol)) select.value = state().symbol;
    renderWatchlist();
    return true;
  }

  function boot() {
    if (!document.getElementById('bot-lab-page')) return;
    if (!install()) setTimeout(boot, 150);
  }

  window.BiteyMarketUniverse = { catalog: CATALOG, init: install, selectSymbol };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => setTimeout(boot, 100));
  else setTimeout(boot, 100);
})();
