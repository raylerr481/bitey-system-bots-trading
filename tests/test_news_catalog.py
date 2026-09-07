from app.news.sources import catalog


def test_news_catalog_has_recognized_sources_and_safety():
    data = catalog()
    assert data["contract"] == "sbt-news-v1"
    assert {s["name"] for s in data["sources"]} >= {
        "Reuters Markets",
        "Associated Press Business",
        "Bloomberg Markets",
        "Financial Times Markets",
        "The Wall Street Journal Markets",
    }
    assert data["research_only"] is True
    assert data["live"] is False
    assert data["real_money"] is False
    assert data["broker_orders"] == 0
