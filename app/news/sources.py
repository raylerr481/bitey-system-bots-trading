from __future__ import annotations

SOURCES = [
    {"id": "reuters-markets", "name": "Reuters Markets", "url": "https://www.reuters.com/markets/", "type": "wire", "regions": ["global"], "recognized": True},
    {"id": "ap-business", "name": "Associated Press Business", "url": "https://apnews.com/hub/business", "type": "wire", "regions": ["global"], "recognized": True},
    {"id": "bloomberg-markets", "name": "Bloomberg Markets", "url": "https://www.bloomberg.com/markets", "type": "financial", "regions": ["global"], "recognized": True},
    {"id": "ft-markets", "name": "Financial Times Markets", "url": "https://www.ft.com/markets", "type": "financial", "regions": ["global"], "recognized": True},
    {"id": "wsj-markets", "name": "The Wall Street Journal Markets", "url": "https://www.wsj.com/news/markets", "type": "financial", "regions": ["global"], "recognized": True},
]

CATEGORIES = [
    "earnings", "guidance", "mergers", "regulation", "interest-rates", "inflation",
    "employment", "central-banks", "geopolitics", "commodities", "fx", "technology",
    "credit", "fiscal-policy", "company-specific", "market-structure",
]

def catalog() -> dict:
    return {"contract": "sbt-news-v1", "sources": SOURCES, "categories": CATEGORIES, "research_only": True, "live": False, "real_money": False, "broker_orders": 0}
