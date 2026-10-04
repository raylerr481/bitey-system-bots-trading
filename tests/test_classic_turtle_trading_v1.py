from strategies.classic_turtle_trading_v1 import Bar, TurtleConfig, add_unit_price, breakout_levels

def test_breakout_excludes_current_bar():
    bars = [Bar(i, 1.0, 1.0 + i * 0.01, 0.99, 1.0 + i * 0.01) for i in range(22)]
    high, low = breakout_levels(bars, 20)
    assert high == max(b.high for b in bars[-21:-1])
    assert low == min(b.low for b in bars[-21:-1])

def test_pyramiding_moves_half_n():
    cfg = TurtleConfig(add_n=0.5, max_units=4)
    assert add_unit_price(100.0, 'long', 2.0, 1, cfg) == 101.0
    assert add_unit_price(100.0, 'short', 2.0, 1, cfg) == 99.0
    assert add_unit_price(100.0, 'long', 2.0, 4, cfg) is None