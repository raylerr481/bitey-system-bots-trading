"""Regression tests for the canonical SBT market-state contract."""

from __future__ import annotations

from app.core.market_state import mark_connecting, mark_live, read_market_state


class _Provider:
    name = "mt5"


def test_market_state_fails_closed_without_provider(monkeypatch) -> None:
    monkeypatch.delenv("SBT_MARKET_PROVIDER", raising=False)
    monkeypatch.delenv("SBT_BIQUOTE_PUBLIC_APPROVED", raising=False)
    monkeypatch.delenv("MT5_BRIDGE_URL", raising=False)

    state = read_market_state("EURUSD", "M1")
    payload = state.as_dict()

    assert payload["contract"] == "sbt-market-state-v1"
    assert payload["state"] == "OFFLINE"
    assert payload["market_available"] is False
    assert payload["quote_available"] is False
    assert payload["candles_available"] is False
    assert payload["stream_available"] is False
    assert payload["execution_enabled"] is False
    assert payload["symbol"] == "EURUSD"
    assert payload["timeframe"] == "M1"


def test_market_state_preserves_provider_selection(monkeypatch) -> None:
    monkeypatch.setenv("SBT_MARKET_PROVIDER", "unknown-provider")
    state = read_market_state()
    assert state.provider == "unknown-provider"
    assert state.state == "OFFLINE"


def test_configured_provider_is_not_reported_live(monkeypatch) -> None:
    monkeypatch.setenv("SBT_MARKET_PROVIDER", "mt5")
    monkeypatch.setenv("MT5_BRIDGE_URL", "http://example.test")
    monkeypatch.setattr("app.core.market_state.build_provider", lambda: _Provider())

    state = read_market_state("EURUSD", "M1")
    payload = state.as_dict()

    assert payload["provider"] == "mt5"
    assert payload["connection"] == "configured"
    assert payload["state"] == "CONNECTING"
    assert payload["market_available"] is False
    assert payload["quote_available"] is False
    assert payload["candles_available"] is False
    assert payload["stream_available"] is False
    assert payload["execution_enabled"] is False


def test_observed_quote_promotes_state_to_live() -> None:
    state = mark_connecting("EURUSD", "M1", "mt5")
    assert state.state == "CONNECTING"
    assert state.quote_available is False
    assert state.stream_available is True

    live = mark_live(
        "EURUSD",
        "M1",
        "mt5",
        {"symbol": "EURUSD", "mid": 1.1, "timestamp": 1000},
        {"timestamp": 960, "open": 1.0, "high": 1.1, "low": 1.0, "close": 1.1},
        latency=0.25,
    )
    payload = live.as_dict()

    assert payload["state"] == "LIVE"
    assert payload["market_available"] is True
    assert payload["quote_available"] is True
    assert payload["candles_available"] is True
    assert payload["stream_available"] is True
    assert payload["last_quote"]["mid"] == 1.1
    assert payload["latency"] == 0.25
    assert payload["execution_enabled"] is False
