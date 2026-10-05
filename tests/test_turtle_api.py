from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_turtle_status_endpoint():
    response = client.get("/api/v1/turtle/status")
    assert response.status_code == 200
    body = response.json()
    assert body["controller"] == "Turtle Controller"
    assert body["risk_gate_authoritative"] is True


def test_mt4_snapshot_updates_turtle_controller():
    response = client.post(
        "/api/v1/mt4/bitey-report",
        json={
            "symbol": "EURUSD",
            "timeframe": "H1",
            "mode": "DEMO",
            "execution_enabled": False,
            "regime": "TREND",
            "metrics": {"signal": "BUY"},
            "account": {"position_count": 0, "risk_pct": 0.25, "drawdown_pct": 1.2},
            "market": {},
            "report_type": "live_snapshot",
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["turtle_controller"]["symbol"] == "EURUSD"
    assert body["turtle_controller"]["next_action"] == "CHECK_RISK_GATE"
