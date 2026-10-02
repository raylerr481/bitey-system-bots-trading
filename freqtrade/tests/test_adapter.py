from freqtrade.adapter import FreqtradeReadOnlyClient, FreqtradeSettings


def test_default_connector_is_local_and_read_only():
    settings = FreqtradeSettings()
    client = FreqtradeReadOnlyClient(settings)

    assert settings.base_url.startswith("http://127.0.0.1:")
    assert not hasattr(client, "force_enter")
    assert not hasattr(client, "force_exit")
