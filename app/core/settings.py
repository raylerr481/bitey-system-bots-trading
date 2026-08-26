import os

PAPER_MODE = os.getenv("ALPACA_PAPER", "true").lower() == "true"
ALPACA_API_KEY = os.getenv("ALPACA_API_KEY", "")
ALPACA_SECRET_KEY = os.getenv("ALPACA_SECRET_KEY", "")
WEBHOOK_TOKEN = os.getenv("TRADING_WEBHOOK_TOKEN", "")


def require_paper_mode() -> None:
    if not PAPER_MODE:
        raise RuntimeError("Live trading is disabled. ALPACA_PAPER must remain true in this milestone.")
