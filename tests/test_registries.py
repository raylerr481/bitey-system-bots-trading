from app.registries.ai_provider_registry import validate_ai_connection
from app.registries.platform_connector_registry import get_platform


def test_bitey_supports_api_connection():
    result = validate_ai_connection("bitey", "api")
    assert result["valid"] is True


def test_bitey_rejects_mcp_connection():
    result = validate_ai_connection("bitey", "mcp")
    assert result["valid"] is False


def test_mt5_is_demo_read_only():
    platform = get_platform("mt5")
    assert platform is not None
    assert "demo" in platform.modes
    assert platform.read_only is True
    assert platform.live_enabled is False


def test_unknown_platform_is_rejected():
    assert get_platform("unknown-platform") is None
