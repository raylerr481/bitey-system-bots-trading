const json = (data, status = 200, extra = {}) => new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store, no-cache, must-revalidate, max-age=0', 'access-control-allow-origin': '*', ...extra } });

const SYMBOL_MAP = {
  EURUSD: 'EURUSD=X', GBPUSD: 'GBPUSD=X', USDJPY: 'JPY=X', USDCHF: 'CHF=X',
  AUDUSD: 'AUDUSD=X', USDCAD: 'CAD=X', NZDUSD: 'NZDUSD=X',
  XAUUSD: 'GC=F', XAGUSD: 'SI=F', USOIL: 'CL=F', UKOIL: 'BZ=F', NATGAS: 'NG=F',
  BTCUSD: 'BTC-USD', BTCUSDT: 'BTC-USD', ETHUSD: 'ETH-USD', ETHUSDT: 'ETH-USD',
  SOLUSD: 'SOL-USD', SOLUSDT: 'SOL-USD', XRPUSD: 'XRP-USD', XRPUSDT: 'XRP-USD',
  ADAUSD: 'ADA-USD', ADAUSDT: 'ADA-USD', DOGEUSD: 'DOGE-USD', DOGEUSDT: 'DOGE-USD',
  ETCUSD: 'ETC-USD', ETCUSDT: 'ETC-USD', 'ETC/USDT': 'ETC-USD',
  AAPL: 'AAPL', MSFT: 'MSFT', NVDA: 'NVDA', AMZN: 'AMZN', TSLA: 'TSLA', META: 'META', GOOGL: 'GOOGL',
  SPY: 'SPY', QQQ: 'QQQ', IWM: 'IWM', DIA: 'DIA', EWZ: 'EWZ'
};

const intervalFor = (tf) => ({ M1: '1m', M5: '5m', M15: '15m', M30: '30m', H1: '60m', H4: '1h', D1: '1d', W1: '1wk', MN1: '1mo' }[String(tf || 'M5').toUpperCase()] || '5m');
const rangeFor = (tf) => ({ M1: '1d', M5: '5d', M15: '1mo', M30: '1mo', H1: '3mo', H4: '6mo', D1: '1y', W1: '5y', MN1: '10y' }[String(tf || 'M5').toUpperCase()] || '5d');
const yahooSymbol = (symbol) => SYMBOL_MAP[String(symbol || '').toUpperCase()] || String(symbol || '').toUpperCase();

async function yahooChart(symbol, timeframe, limit = 200) {
  const ticker = yahooSymbol(symbol);
  if (!ticker) throw new Error('symbol_required');
  const url = new URL(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}`);
  url.searchParams.set('range', rangeFor(timeframe));
  url.searchParams.set('interval', intervalFor(timeframe));
  url.searchParams.set('includePrePost', 'false');
  url.searchParams.set('events', 'div,splits');
  const r = await fetch(url.toString(), { headers: { 'user-agent': 'Bitey-SBT/1.0' } });
  if (!r.ok) throw new Error(`market_provider_http_${r.status}`);
  const payload = await r.json();
  const result = payload?.chart?.result?.[0];
  if (!result) throw new Error(payload?.chart?.error?.description || 'market_provider_empty');
  const q = result.indicators?.quote?.[0] || {};
  const timestamps = result.timestamp || [];
  const candles = timestamps.map((time, i) => ({
    time,
    open: Number(q.open?.[i]), high: Number(q.high?.[i]), low: Number(q.low?.[i]), close: Number(q.close?.[i]), volume: Number(q.volume?.[i] || 0)
  })).filter(c => [c.open, c.high, c.low, c.close].every(Number.isFinite)).slice(-Math.max(20, Math.min(Number(limit) || 200, 500)));
  const meta = result.meta || {};
  const price = Number(meta.regularMarketPrice ?? candles.at(-1)?.close);
  const prev = Number(meta.previousClose ?? candles.at(-2)?.close);
  const bid = Number(meta.bid ?? price);
  const ask = Number(meta.ask ?? price);
  return { ticker, candles, price, bid: Number.isFinite(bid) ? bid : price, ask: Number.isFinite(ask) ? ask : price, previous: prev, currency: meta.currency || 'USD', exchange: meta.exchangeName || 'Yahoo Finance' };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const BUILD = 'f8-market-feed-same-origin';

    if (url.pathname === '/health') return json({ service: 'bitey-system-bots-trading', status: 'ok', mode: 'research-demo', live: false, real_money: false, broker_orders: 0, web_build: BUILD });

    if (url.pathname === '/api/v1/system') return json({ ok: true, service: 'bitey-system-bots-trading', live_trading_enabled: false, real_money_enabled: false, broker_orders: 0, market_data: 'public-readonly', provider: 'Yahoo Finance public chart endpoint' });

    if (url.pathname === '/api/v1/market/quote') {
      try {
        const symbol = url.searchParams.get('symbol') || 'EURUSD';
        const tf = url.searchParams.get('timeframe') || 'M5';
        const m = await yahooChart(symbol, tf, 50);
        const spread = Math.max(0, m.ask - m.bid);
        return json({ ok: true, symbol, source: 'yahoo-public', provider: 'yahoo-public', price: m.price, last: m.price, bid: m.bid, ask: m.ask, spread, previous_close: m.previous, currency: m.currency, exchange: m.exchange });
      } catch (e) { return json({ ok: false, available: false, error: String(e?.message || e), execution_enabled: false }, 502); }
    }

    if (url.pathname.startsWith('/api/v1/market/candles/')) {
      try {
        const symbol = decodeURIComponent(url.pathname.split('/').pop());
        const timeframe = url.searchParams.get('timeframe') || 'M5';
        const limit = Number(url.searchParams.get('limit') || 200);
        const m = await yahooChart(symbol, timeframe, limit);
        return json({ ok: true, symbol, timeframe, source: 'yahoo-public', provider: 'yahoo-public', candles: m.candles, quote: { last: m.price, bid: m.bid, ask: m.ask, spread: Math.max(0, m.ask - m.bid) }, execution_enabled: false });
      } catch (e) { return json({ ok: false, available: false, candles: [], error: String(e?.message || e), execution_enabled: false }, 502); }
    }

    if (url.pathname === '/api/v1/market-state') {
      try {
        const symbol = url.searchParams.get('symbol') || 'EURUSD';
        const timeframe = url.searchParams.get('timeframe') || 'M5';
        const m = await yahooChart(symbol, timeframe, 50);
        return json({ ok: true, state: m.candles.length >= 20 ? 'HISTORICAL' : 'DEGRADED', symbol, timeframe, provider: 'yahoo-public', source: 'yahoo-public', market_available: m.candles.length >= 20, stream_available: false, quote_available: Number.isFinite(m.price), last_quote: { last: m.price, bid: m.bid, ask: m.ask }, execution_enabled: false, live: false, real_money: false, broker_orders: 0, last_update: Math.floor(Date.now() / 1000) });
      } catch (e) { return json({ ok: true, state: 'ERROR', symbol: url.searchParams.get('symbol') || 'EURUSD', timeframe: url.searchParams.get('timeframe') || 'M5', provider: 'yahoo-public', market_available: false, stream_available: false, quote_available: false, last_quote: { error: String(e?.message || e) }, execution_enabled: false, live: false, real_money: false, broker_orders: 0 }, 502); }
    }

    const response = await env.ASSETS.fetch(request);
    const contentType = response.headers.get('content-type') || '';
    if (!contentType.includes('text/html')) return response;

    return new HTMLRewriter().on('body', {
      element(element) {
        element.append(`<script>
(() => {
  const closeMobileMenu=()=>{const side=document.getElementById('side');if(side)side.classList.remove('open');};
  const getMarketRow=()=>Array.from(document.querySelectorAll('.risk')).find(item=>item.querySelector('span')?.textContent?.trim().toLowerCase()==='market data');
  const canonical=()=>window.BiteySBTMarketState?.canonical||null;
  const sync=()=>{const row=getMarketRow(),c=canonical(),s=window.BiteySBTMarketState;if(!row||!s)return;const b=row.querySelector('b');if(!b)return;const feed=String(c?.state||s.feedState||'OFFLINE').toUpperCase();const ok=['CONNECTING','HISTORICAL','LIVE','DEGRADED'].includes(feed);b.textContent=ok?(feed==='LIVE'?'LIVE':'READY'):'OFFLINE';b.style.color=ok?'var(--accent)':'var(--danger)';const st=document.getElementById('mtFeedStatus');if(st&&c?.state)st.textContent='● '+c.state+' · '+(c.symbol||s.symbol)+' · '+(c.timeframe||s.timeframe);};
  const openTerminal=()=>{closeMobileMenu();const b=document.querySelector('.nav button[data-page="bots"]');if(b){b.click();setTimeout(()=>window.BiteyWebTrader?.drawChart?.(),300);}};
  const wire=()=>{const nav=document.querySelector('.nav'),marker=nav?.querySelector('button[data-page="bots"]');if(nav&&marker&&!nav.querySelector('[data-sbt-terminal-link]')){const a=document.createElement('button');a.type='button';a.dataset.sbtTerminalLink='1';a.textContent='▣ Trading Terminal';a.style.cssText='display:block;width:100%;text-align:left;background:transparent;color:#91a0b1;padding:10px 12px;border-radius:10px;margin:2px 0;border:1px solid transparent;font-size:14px;cursor:pointer;';a.onclick=openTerminal;marker.insertAdjacentElement('afterend',a);}sync();};
  document.addEventListener('click',e=>{const t=e.target.closest('[data-page]');if(t){closeMobileMenu();setTimeout(wire,200);}},true);window.addEventListener('bitesbt:market-state',wire);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',wire,{once:true});else wire();setInterval(wire,1500);
})();
</script>`,{html:true});
      }
    }).transform(new Response(response.body,{status:response.status,statusText:response.statusText,headers:new Headers(response.headers)}));
  }
};