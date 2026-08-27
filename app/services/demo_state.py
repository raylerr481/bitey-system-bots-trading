from app.core.models import DemoPortfolio
from app.risk.engine import RiskEngine
from app.services.demo_engine import DemoEngine
from app.services.demo_loop import DemoTradingLoop

portfolio = DemoPortfolio(initial_capital=10_000, cash=10_000)
risk = RiskEngine()
engine = DemoEngine(portfolio, risk)

loop = DemoTradingLoop.__new__(DemoTradingLoop)
loop.portfolio = portfolio
loop.risk = risk
loop.engine = engine


def get_demo_state() -> DemoTradingLoop:
    return loop
