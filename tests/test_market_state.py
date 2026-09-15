"""Regression tests for the canonical SBT market-state contract."""

from __future__ import annotations

from app.core.market_state import read_market_state


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
