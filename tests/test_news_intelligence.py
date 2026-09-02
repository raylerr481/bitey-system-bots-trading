from app.services.news_intelligence import alert_matches, analyze_event


def test_favorable_event_can_match_alert_rule():
    result = analyze_event(
        event_id="e1",
        headline="Company reports record growth and strong guidance",
        event_type="earnings",
        sector="technology",
        assets=["XYZ"],
    )
    assert result.bias == "favorable"
    assert result.opportunity_score > 0.5
    assert alert_matches(result, min_opportunity=0.5, max_risk=0.8) is True


def test_adverse_event_is_not_opportunity_alert():
    result = analyze_event(
        event_id="e2",
        headline="Company reports loss and weak guidance",
        event_type="earnings",
        sector="technology",
        assets=["XYZ"],
    )
    assert result.bias == "adverse"
    assert alert_matches(result, min_opportunity=0.1, max_risk=1.0) is False


def test_high_impact_event_reports_conflict():
    result = analyze_event(
        event_id="e3",
        headline="Central bank rate decision surprises markets",
        event_type="rate_decision",
        sector="macro",
        assets=["EURUSD", "SPY"],
    )
    assert result.volatility_score >= 0.85
    assert result.conflicts
