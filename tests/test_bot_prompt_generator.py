from app.services.bot_prompt_generator import generate_bot_prompts


def test_news_generates_three_risk_profiles():
    proposals = generate_bot_prompts({
        "event_id": "e1",
        "headline": "Strong earnings and guidance",
        "sector": "technology",
        "assets": ["XYZ"],
        "impact": "high",
        "bias": "favorable",
        "opportunity_score": 0.8,
        "risk_score": 0.3,
        "volatility_score": 0.7,
        "horizon": "short_term",
    })
    assert [p["profile"] for p in proposals] == ["conservative", "balanced", "event-driven"]
    assert all(p["version"] == "1.0.0" for p in proposals)
    assert all("backtest" in " ".join(p["validation_requirements"]).lower() for p in proposals)


def test_prompts_do_not_promise_profit():
    proposals = generate_bot_prompts({"event_id": "e2", "headline": "Rate decision", "assets": ["EURUSD"]})
    text = str(proposals).lower()
    assert "guaranteed profit" not in text
    assert "guarantee gains" not in text
