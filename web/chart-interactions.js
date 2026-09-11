(() => {
  function install() {
    const canvas = document.getElementById('mtChart');
    const trader = window.BiteyWebTrader;
    if (!canvas || !trader || canvas.dataset.interactionsReady) return false;
    canvas.dataset.interactionsReady = '1';
    const host = canvas.parentElement;
    if (!host) return false;
    if (getComputedStyle(host).position === 'static') host.style.position = 'relative';

    const overlay = document.createElement('canvas');
    overlay.id = 'mtChartInteractionOverlay';
    overlay.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:auto;touch-action:none;cursor:crosshair;z-index:5';
    host.appendChild(overlay);

    const tooltip = document.createElement('div');
    tooltip.id = 'mtChartCrosshairTooltip';
    tooltip.style.cssText = 'position:absolute;display:none;pointer-events:none;z-index:6;padding:5px 7px;border:1px solid #334150;border-radius:5px;background:#0d141c;color:#e8eef5;font:11px system-ui;white-space:nowrap;box-shadow:0 4px 16px rgba(0,0,0,.35)';
    host.appendChild(tooltip);

    function metrics() {
      const rect = canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
      overlay.width = Math.max(1, Math.floor(rect.width * dpr)); overlay.height = Math.max(1, Math.floor(rect.height * dpr));
      const left = 58, right = 70;
      return { rect, dpr, w: rect.width, h: rect.height, left, right, plotW: Math.max(1, rect.width - left - right), candles: trader.visibleCandles().candles };
    }
    function clear() { const m = metrics(), ctx = overlay.getContext('2d'); ctx.setTransform(m.dpr,0,0,m.dpr,0,0); ctx.clearRect(0,0,m.w,m.h); tooltip.style.display = 'none'; }
    function crosshair(clientX, clientY) {
      const m = metrics(), x = clientX - m.rect.left, y = clientY - m.rect.top, ctx = overlay.getContext('2d');
      ctx.setTransform(m.dpr,0,0,m.dpr,0,0); ctx.clearRect(0,0,m.w,m.h); ctx.strokeStyle = 'rgba(210,220,232,.55)'; ctx.setLineDash([4,4]); ctx.beginPath(); ctx.moveTo(x,28); ctx.lineTo(x,m.h-30); ctx.moveTo(m.left,y); ctx.lineTo(m.w-m.right,y); ctx.stroke(); ctx.setLineDash([]);
      const candles = m.candles; if (!candles.length) return;
      const index = Math.max(0, Math.min(candles.length - 1, Math.round((x - m.left) / (m.plotW / candles.length) - .5))); const c = candles[index]; if (!c) return;
      tooltip.textContent = `${new Date(c.time * 1000).toLocaleString()} · O ${c.open.toFixed(5)} H ${c.high.toFixed(5)} L ${c.low.toFixed(5)} C ${c.close.toFixed(5)}`;
      tooltip.style.display = 'block'; tooltip.style.left = `${Math.min(Math.max(4, x + 10), m.w - 275)}px`; tooltip.style.top = `${Math.max(4, y - 34)}px`;
    }

    let dragging = false, dragX = 0, dragEnd = null;
    overlay.addEventListener('pointerdown', e => { dragging = true; dragX = e.clientX; dragEnd = trader.state.viewEnd == null ? trader.state.candles.length : trader.state.viewEnd; overlay.setPointerCapture?.(e.pointerId); overlay.style.cursor = 'grabbing'; });
    overlay.addEventListener('pointermove', e => {
      if (dragging) { const m = metrics(), step = m.plotW / Math.max(1, m.candles.length), delta = Math.round((e.clientX - dragX) / Math.max(2, step)); trader.state.viewEnd = Math.max(trader.state.viewCount, Math.min(dragEnd - delta, trader.state.candles.length)); trader.clampView(); trader.drawChart(); }
      crosshair(e.clientX, e.clientY);
    });
    const stop = e => { if (dragging) { dragging = false; overlay.style.cursor = 'crosshair'; if (trader.state.viewEnd >= trader.state.candles.length) trader.state.viewEnd = null; trader.drawChart(); } if (e?.type === 'pointerleave') clear(); };
    overlay.addEventListener('pointerup', stop); overlay.addEventListener('pointercancel', stop); overlay.addEventListener('pointerleave', stop);
    overlay.addEventListener('wheel', e => { e.preventDefault(); const old = trader.state.viewCount || 120; const factor = e.deltaY < 0 ? .82 : 1.22; trader.state.viewCount = Math.max(20, Math.min(trader.state.candles.length || 20, Math.round(old * factor))); trader.clampView(); trader.drawChart(); crosshair(e.clientX, e.clientY); }, { passive: false });
    window.addEventListener('resize', () => { clear(); trader.drawChart(); });
    window.BiteyChartInteractionState = { overlay, tooltip };
    return true;
  }
  const boot = () => { if (window.BiteyWebTrader) { if (install()) return; } setTimeout(boot, 100); };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
