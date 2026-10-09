from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def test_frontend_html_has_one_balanced_document_shell():
    html = (ROOT / "web" / "index.html").read_text(encoding="utf-8")
    assert len(re.findall(r"<body\\b", html, re.I)) == 1
    assert len(re.findall(r"</body\\s*>", html, re.I)) == 1
    assert len(re.findall(r"<html\\b", html, re.I)) == 1
    assert len(re.findall(r"</html\\s*>", html, re.I)) == 1
    assert len(re.findall(r"<script\\b", html, re.I)) == len(
        re.findall(r"</script\\s*>", html, re.I)
    )
    assert html.rstrip().lower().endswith("</body>\n</html>")


def test_runtime_has_one_loading_owner():
    html = (ROOT / "web" / "index.html").read_text(encoding="utf-8")
    worker = (ROOT / "worker.js").read_text(encoding="utf-8")
    assert 'src="/runtime.js"' not in html
    assert 'element.append(`<script src="/runtime.js?' in worker


def test_market_analysis_uses_operating_capital_not_a_hardcoded_10000():
    trader = (ROOT / "web" / "web-trader.js").read_text(encoding="utf-8")
    assert "capital: operatingCapitalUsd()" in trader
    assert "function operatingCapitalUsd()" in trader
    assert "capital:10000" not in trader
    assert "sbt_operating_capital_usd" in trader


def test_terminal_dom_sync_is_not_polled_every_1_5_seconds():
    worker = (ROOT / "worker.js").read_text(encoding="utf-8")
    assert "setInterval(wire,10000)" in worker
    assert "setInterval(wire,1500)" not in worker


def test_real_money_and_automatic_execution_remain_disabled():
    worker = (ROOT / "worker.js").read_text(encoding="utf-8")
    trader = (ROOT / "web" / "web-trader.js").read_text(encoding="utf-8")
    assert "live_trading_enabled: false" in worker
    assert "execution_enabled: false" in worker
    assert "real_money_enabled: false" in worker
    assert "execution_enabled:false" in trader
    assert "real_money:false" in trader
