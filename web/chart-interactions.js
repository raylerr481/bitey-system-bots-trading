(() => {
  const state = { zoom: 120, pan: 0 };

  function install() {
    const canvas = document.getElementById('mtChart');
    if (!canvas || canvas.dataset.interactionsReady) return false;
    canvas.dataset.interactionsReady = '1';
    canvas.style.touchAction = 'none';

    const overlay = document.createElement('canvas');
    overlay.id = 'mtChartInteractionOverlay';
    overlay.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:none;z-index:5;';
    canvas.parentElement.appendChild(overlay);

    const tooltip = document.createElement('div');
    tooltip.id = 'mtChartCrosshairTooltip';
    tooltip.style.cssText = 'position:absolute;display:none;z-index:6;pointer-events:none;padding:6px 8px;border:1px solid #303844;border-radius:6px;background:#0d1117;color:#d9dee7;font:10px ui-monospace,SFMono-Regular,Consolas,monospace;white-space:nowrap;box-shadow:0 6px 18px rgba(0,0,0,.35);';
    canvas.parentElement.appendChild(tooltip);

    function size() {
      const r = canvas.getBoundingClientRect(), d = window.devicePixelRatio || 1;
      overlay.width = Math.max(1, Math.floor(r.width * d));
      overlay.height = Math.max(1, Math.floor(r.height * d));
      return { w: r.width, h: r.height, d };
    }

    function visibleCandles() {
      const all = window.BiteyWebTrader?.state?.candles || [];
      if (!all.length) return [];
      const count = Math.max(30, Math.min(state.zoom, all.length));
      const end = Math.max(count, all.length - state.pan);
      return all.slice(Math.max(0, end - count), end);
    }

    function clear() {
      const { w, h, d } = size();
      const ctx = overlay.getContext('2d');
      ctx.setTransform(d,0,0,d,0,0);
      ctx.clearRect(0,0,w,h);
      return { ctx, w, h };
    }

    function drawCrosshair(x, y) {
      const { ctx, w, h } = clear();
      ctx.strokeStyle = 'rgba(210,220,232,.42)';
      ctx.lineWidth = 1;
      ctx.setLineDash([4,4]);
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
      ctx.setLineDash([]);
    }

    canvas.addEventListener('pointermove', event => {
      const r = canvas.getBoundingClientRect();
      const x = event.clientX - r.left, y = event.clientY - r.top;
      drawCrosshair(x, y);
      const candles = visibleCandles();
      if (!candles.length) return;
      const left = 58, right = 70;
      const usable = Math.max(1, r.width - left - right);
      const index = Math.max(0, Math.min(candles.length - 1, Math.round((x - left) / (usable / candles.length) - .5)));
      const c = candles[index];
      if (!c) return;
      tooltip.style.display = 'block';
      tooltip.style.left = `${Math.min(Math.max(6, x + 12), r.width - 190)}px`;
      tooltip.style.top = `${Math.min(Math.max(6, y + 12), r.height - 48)}px`;
      tooltip.textContent = `O ${c.open.toFixed(5)} · H ${c.high.toFixed(5)} · L ${c.low.toFixed(5)} · C ${c.close.toFixed(5)}`;
    });

    canvas.addEventListener('pointerleave', () => { clear(); tooltip.style.display = 'none'; });

    canvas.addEventListener('wheel', event => {
      event.preventDefault();
      const candles = window.BiteyWebTrader?.state?.candles || [];
      if (!candles.length) return;
      state.zoom = Math.max(30, Math.min(candles.length, state.zoom + (event.deltaY > 0 ? 10 : -10)));
      clear();
      // Current renderer remains authoritative; zoom state is exposed for the next chart-engine pass.
      window.BiteyChartInteractionState = state;
    }, { passive: false });

    window.addEventListener('resize', () => clear());
    window.BiteyChartInteractionState = state;
    return true;
  }

  function boot() {
    if (install()) return;
    setTimeout(boot, 250);
  }
  boot();
})();
