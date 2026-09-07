from app.brokers.alpaca import AlpacaAdapter
from app.brokers.mt5 import MT5Adapter
from app.brokers.registry import catalog, get_adapter


def test_broker_catalog_is_safe_by_default():
    brokers = {item["id"]: item for item in catalog()}
    assert {"alpaca", "mt5"} <= brokers.keys()
    assert brokers["alpaca"]["capabilities"]["paper"] is True
    assert brokers["alpaca"]["capabilities"]["live"] is False
    assert brokers["mt5"]["capabilities"]["demo"] is True
    assert brokers["mt5"]["capabilities"]["live"] is False


def test_registry_returns_expected_adapters():
    assert isinstance(get_adapter("alpaca"), AlpacaAdapter)
    assert isinstance(get_adapter("MT5"), MT5Adapter)


def test_mt5_adapter_never_submits_orders():
    adapter = MT5Adapter(bridge_url="http://127.0.0.1:1")
    assert adapter.capabilities().order_submission is False
    try:
        adapter.submit_order("EURUSD", "buy", 0.01)
    except RuntimeError as exc:
        assert "disabled" in str(exc).lower()
    else:
        raise AssertionError("MT5 adapter must reject order submission in this milestone")
