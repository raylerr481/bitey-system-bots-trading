from app.services.mt4_research_dataset import (
    DatasetBuildConfig,
    SCHEMA_VERSION,
    TARGET_COLUMNS,
    build_dataset,
)


def _rows():
    return [
        {"timestamp": "2026-01-01T00:00:00", "open": "100", "high": "101", "low": "99", "close": "100", "signal": "BUY"},
        {"timestamp": "2026-01-01T01:00:00", "open": "100", "high": "102", "low": "99", "close": "101", "signal": "BUY"},
        {"timestamp": "2026-01-01T02:00:00", "open": "101", "high": "103", "low": "100", "close": "102", "signal": "BUY"},
        {"timestamp": "2026-01-01T03:00:00", "open": "102", "high": "104", "low": "101", "close": "103", "signal": "BUY"},
    ]


def test_dataset_is_versioned_and_targets_are_separate():
    dataset = build_dataset(_rows(), DatasetBuildConfig(horizon_candles=1))
    assert dataset["schema_version"] == SCHEMA_VERSION
    assert "future_return" not in dataset["feature_columns"]
    assert TARGET_COLUMNS.issuperset(dataset["target_columns"])
    assert "future_return" in dataset["rows"][0]["targets"]


def test_rows_are_chronological_and_last_target_is_unavailable():
    rows = list(reversed(_rows()))
    dataset = build_dataset(rows, DatasetBuildConfig(horizon_candles=1))
    timestamps = [r["timestamp"] for r in dataset["rows"]]
    assert timestamps == sorted(timestamps)
    assert dataset["rows"][-1]["targets"]["future_return"] is None


def test_targets_use_future_candles_but_features_do_not():
    dataset = build_dataset(_rows(), DatasetBuildConfig(horizon_candles=1))
    first = dataset["rows"][0]
    assert first["targets"]["future_return"] == 0.01
    assert all(not key.startswith("future_") for key in first["features"])


def test_missing_ohlc_is_rejected():
    rows = _rows()
    rows[0]["close"] = ""
    try:
        build_dataset(rows)
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "missing required market fields" in str(exc)
