from pathlib import Path
import ast

STRATEGY = Path("freqtrade/user_data/strategies/BiteyQuantFreqAI_v1.py")

def test_strategy_parses_and_is_versioned():
    source = STRATEGY.read_text(encoding="utf-8")
    ast.parse(source)
    assert "class BiteyQuantFreqAI_v1" in source
    assert 'return "1.0.0"' in source

def test_negative_shifts_are_confined_to_targets():
    source = STRATEGY.read_text(encoding="utf-8")
    tree = ast.parse(source)
    target = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "set_freqai_targets")
    target_nodes = set(ast.walk(target))
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "shift" and node.args:
            if isinstance(node.args[0], ast.UnaryOp) and isinstance(node.args[0].op, ast.USub):
                assert node in target_nodes

def test_entry_exit_use_predictions_not_raw_targets():
    source = STRATEGY.read_text(encoding="utf-8")
    section = source[source.index("def populate_entry_trend"):source.index("def custom_exit")]
    assert "&-future_return_mean" in section
    assert '&-future_return"' not in section
    assert '&-future_max_profit"' not in section
    assert '&-future_max_loss"' not in section
    assert '&-trade_outcome"' not in section

def test_no_iloc_or_expanding():
    source = STRATEGY.read_text(encoding="utf-8")
    assert ".iloc[" not in source
    assert ".expanding(" not in source

def test_risk_controls_present():
    source = STRATEGY.read_text(encoding="utf-8")
    assert "stoploss = -0.025" in source
    assert "MaxDrawdown" in source
    assert "StoplossGuard" in source
