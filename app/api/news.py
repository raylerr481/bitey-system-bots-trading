from fastapi import APIRouter, Query

from app.news.sources import CATEGORIES, SOURCES, catalog

router = APIRouter(prefix="/api/v1/news", tags=["market-news"])

@router.get("/catalog")
def news_catalog():
    return catalog()

@router.get("/sources")
def news_sources():
    return {"contract": "sbt-news-v1", "sources": SOURCES, "research_only": True, "live": False, "real_money": False, "broker_orders": 0}

@router.get("/impact-categories")
def impact_categories():
    return {"categories": CATEGORIES, "note": "Categories describe possible market impact; they are not predictions or trade signals."}

@router.get("/watchlist")
def news_watchlist(symbol: str = Query(default="", max_length=30)):
    return {
        "contract": "sbt-news-watchlist-v1",
        "symbol": symbol.upper(),
        "sources": SOURCES,
        "focus": ["company-specific", "earnings", "guidance", "regulation", "central-banks", "interest-rates", "inflation", "geopolitics", "commodities"],
        "research_only": True,
        "live": False,
        "real_money": False,
        "broker_orders": 0,
    }
