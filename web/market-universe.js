(() => {
  const CATALOG = [
    { group: 'Forex', items: ['EURUSD','GBPUSD','USDJPY','USDCHF','AUDUSD','USDCAD','NZDUSD','EURGBP','EURJPY','GBPJPY'] },
    { group: 'Cripto', items: ['BTCUSD','ETHUSD','SOLUSD','XRPUSD','ADAUSD','DOGEUSD'] },
    { group: 'Índices', items: ['SPX500','NAS100','US30','GER40','UK100','JPN225','US2000','IBOV'] },
    { group: 'Acciones', items: ['AAPL','MSFT','NVDA','AMZN','TSLA','META','GOOGL','BRK.B','VALE3','PETR4','ITUB4'] },
    { group: 'Materias primas', items: ['XAUUSD','XAGUSD','USOIL','UKOIL','NATGAS'] },
    { group: 'ETFs', items: ['SPY','QQQ','IWM','DIA','EWZ'] }
  ];

  function state() { return window.BiteySBTMarketState; }
  function install() {
    const page = document.getElementById('bot-lab-page');
    const s = state();
    if (!page || !s || page.dataset.marketUniverseReady) return;
    page.dataset.marketUniverseReady = '1';

    const anchor = page.querySelector('#mtWatchBody');
    if (!anchor || !anchor.parentElement) return;
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

    select.addEventListener('change', () => {
      s.symbol = select.value;
      s.viewEnd = null;
      s.candles = [];
      const ready = document.getElementById('bot-lab-page');
      if (ready) delete ready.dataset.webTraderReady;
      if (window.BiteyWebTrader && typeof window.BiteyWebTrader.init === 'function') {
        window.BiteyWebTrader.init();
      }
      const status = document.getElementById('sbtMarketUniverseState');
      if (status) status.textContent = `${s.symbol} · solicitando datos reales…`;
    });
  }

  function boot() {
    if (document.getElementById('bot-lab-page')) install();
  }
  window.BiteyMarketUniverse = { catalog: CATALOG, init: install };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => setTimeout(boot, 100));
  else setTimeout(boot, 100);
})();
