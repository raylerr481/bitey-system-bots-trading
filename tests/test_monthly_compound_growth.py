from datetime import datetime, timezone

from app.core.monthly_growth import MonthlyCompoundGrowthEngine, net_trade_pnl


TICKET_95745109 = {
    "ticket": 95745109,
    "symbol": "EURUSD",
    "side": "BUY",
    "strategy": "ENSEMBLE",
    "close_time": "2026-10-06T12:00:00+00:00",
    "pnl": 29.00,
    "commission": -2.50,
    "swap": 0.0,
    "cost": 0.0,
}


def test_ticket_95745109_uses_realized_net_pnl():
    assert net_trade_pnl(TICKET_95745109) == 26.50

    result = MonthlyCompoundGrowthEngine().build_month(
        month_start=datetime(2026, 10, 1, tzinfo=timezone.utc),
        trades=[TICKET_95745109],
        environment="DEMO",
    )

    assert result.initial_capital_usd == 500.0
    assert result.opening_capital_usd == 500.0
    assert result.net_pnl_usd == 26.50
    assert result.capital_end_usd == 526.50
    assert result.growth_pct == 5.3
    assert result.q_learning_reward == 0.53
    assert result.trades == 1
    assert result.wins == 1
    assert result.losses == 0
    assert result.max_drawdown_usd == 0.0
    assert result.safety["martingale"] is False
    assert result.safety["new_trade_created_by_engine"] is False


def test_compound_series_reinvests_only_realized_monthly_results():
    series = MonthlyCompoundGrowthEngine().build_compound_series(
        monthly_trades={
            "2026-10": [TICKET_95745109],
            "2026-11": [{
                **TICKET_95745109,
                "ticket": 999,
                "close_time": "2026-11-10T12:00:00+00:00",
                "pnl": 52.65,
                "commission": 0.0,
            }],
        },
        environment="DEMO",
    )

    assert [round(row.opening_capital_usd, 2) for row in series] == [500.00, 526.50]
    assert [round(row.capital_end_usd, 2) for row in series] == [526.50, 579.15]


def test_loss_reduces_compounded_capital_without_martingale():
    result = MonthlyCompoundGrowthEngine().build_month(
        month_start=datetime(2026, 12, 1, tzinfo=timezone.utc),
        trades=[{
            "close_time": "2026-12-05T12:00:00+00:00",
            "pnl": -20.0,
            "commission": -1.0,
        }],
        opening_capital_usd=526.50,
    )
    assert result.capital_end_usd == 505.50
    assert result.q_learning_reward == -0.42
    assert result.safety["martingale"] is False
