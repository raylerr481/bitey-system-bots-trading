import pytest

from app.integrations.mt4_gateway import MT4GatewayClient


@pytest.mark.asyncio
async def test_mt4_gateway_defaults_to_localhost():
    client = MT4GatewayClient()
    assert client.base_url == "http://127.0.0.1:22346"
