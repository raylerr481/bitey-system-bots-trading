from services.market_intelligence import Evidence, engine


def test_energy_domino_analysis():
    result = engine.analyze(
        capital=1000,
        language="es",
        evidence=[
            Evidence(
                source="Reuters",
                source_type="news",
                title="Hormuz shipping and oil market update",
                reliability=0.95,
                impact=0.95,
                direction="long",
            )
        ],
    )

    assert result["capital"] == 1000
    assert result["risk"]["max_loss"] == 10
    assert result["risk"]["reward_if_target_hit"] == 20
    assert result["best_opportunity"]["asset"] == "BRENT"
    assert result["scenario"]["probability_score"] == 68
    assert result["scenario"]["invalidation"]


def test_multilingual_output():
    for language in ("es", "pt", "en"):
        result = engine.analyze(capital=500, language=language)
        assert result["language"] == language
        assert result["nodes"]
