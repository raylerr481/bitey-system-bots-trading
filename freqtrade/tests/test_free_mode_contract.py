from pathlib import Path
import json


ROOT = Path(__file__).resolve().parents[1]
DRYRUN_CONFIG = ROOT / "user_data" / "config.freqai.dryrun.json"
API_EXAMPLE = ROOT / "user_data" / "config.freqai.dryrun.api.example.json"
ENV_EXAMPLE = ROOT / ".env.example"


def test_free_research_config_has_no_exchange_credentials():
    data = json.loads(DRYRUN_CONFIG.read_text(encoding="utf-8"))
    assert data["dry_run"] is True
    assert data["exchange"]["key"] == ""
    assert data["exchange"]["secret"] == ""
    assert data["freqai"]["enabled"] is True


def test_api_example_is_local_dry_run_only():
    data = json.loads(API_EXAMPLE.read_text(encoding="utf-8"))
    assert data["dry_run"] is True
    assert data["api_server"]["enabled"] is True
    assert data["api_server"]["listen_ip_address"] == "127.0.0.1"
    assert data["exchange"]["key"] == ""
    assert data["exchange"]["secret"] == ""
    assert "REPLACE_WITH" in data["api_server"]["jwt_secret_key"]


def test_env_example_contains_no_real_secret():
    text = ENV_EXAMPLE.read_text(encoding="utf-8")
    assert "replace_me" in text
    assert "REPLACE_WITH" not in text
    assert "sk-" not in text.lower()
