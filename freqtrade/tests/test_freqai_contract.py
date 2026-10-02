from pathlib import Path
import json


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "user_data" / "config.freqai.dryrun.json"
STRATEGY = ROOT / "user_data" / "strategies" / "BiteyFreqAI_v1.py"


def test_freqai_config_is_dry_run_and_has_no_credentials():
    data = json.loads(CONFIG.read_text(encoding="utf-8"))
    assert data["dry_run"] is True
    assert data["freqai"]["enabled"] is True
    assert data["exchange"]["key"] == ""
    assert data["exchange"]["secret"] == ""


def test_freqai_strategy_is_present_and_research_only():
    source = STRATEGY.read_text(encoding="utf-8")
    assert "class BiteyFreqAI_v1" in source
    assert "set_freqai_targets" in source
    assert "populate_entry_trend" in source
    assert "freqai_positive_forecast" in source
