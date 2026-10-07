from app.api import adaptive_cycle


def test_adaptive_cycle_empty_state(monkeypatch):
    monkeypatch.setattr(adaptive_cycle.live_trades, "list_recent", lambda limit: [])
    body = adaptive_cycle.build_cycle("EURUSD", 200)
    assert body["current_state"]["operational_capital_usd"] == 500.0
    assert body["evidence"]["closed_trades"] == 0
    assert body["next_research_state"] == "WAITING_FOR_MT4_CLOSE"
    assert body["parameter_study"]["candidates"] == []


def test_adaptive_cycle_positive_r_evidence(monkeypatch):
    monkeypatch.setattr(
        adaptive_cycle.live_trades,
        "list_recent",
        lambda limit: [
            {"symbol": "EURUSD", "timeframe": "H1", "pnl": 20, "r_multiple": 1.0},
            {"symbol": "EURUSD", "timeframe": "H1", "pnl": -5, "r_multiple": -0.25},
        ],
    )
    body = adaptive_cycle.build_cycle("EURUSD", 200)
    assert body["evidence"]["r_multiple_observations"] == 2
    assert body["evidence"]["expected_value_r"] == 0.375
    assert body["evidence"]["positive_observed_ev"] is True
    assert body["next_research_state"] == "BOUNDED_PARAMETER_STUDY"
    assert all(x["status"] == "PROPOSAL_ONLY" for x in body["parameter_study"]["candidates"])
    assert body["safety"]["sbt_operational_capital_usd"] == 500.0
    assert body["safety"]["q_learning_execution"] is False
