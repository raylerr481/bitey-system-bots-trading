from pandas import DataFrame
from freqtrade.strategy import IStrategy


class BiteyFreqAI_v1(IStrategy):
    """Research-only FreqAI strategy for Bitey SBT.

    FreqAI supplies the ML prediction. SBT remains the validation and risk
    boundary. This strategy intentionally has no live-trading policy logic.
    """

    INTERFACE_VERSION = 3
    can_short = False
    timeframe = "1h"
    startup_candle_count = 200

    minimal_roi = {"0": 0.02, "60": 0.01, "180": 0}
    stoploss = -0.03
    trailing_stop = False

    def feature_engineering_expand_all(
        self, dataframe: DataFrame, period: int, metadata: dict, **kwargs
    ) -> DataFrame:
        """Build only causal features; no future candles are referenced."""
        dataframe[f"%-rsi-period_{period}"] = self._rsi(dataframe["close"], period)
        dataframe[f"%-roc-period_{period}"] = dataframe["close"].pct_change(period)
        dataframe[f"%-volume-ratio-period_{period}"] = (
            dataframe["volume"] / dataframe["volume"].rolling(period).mean()
        )
        return dataframe

    def feature_engineering_standard(
        self, dataframe: DataFrame, metadata: dict, **kwargs
    ) -> DataFrame:
        dataframe["%-return-1"] = dataframe["close"].pct_change()
        dataframe["%-range"] = (dataframe["high"] - dataframe["low"]) / dataframe["close"]
        return dataframe

    def set_freqai_targets(
        self, dataframe: DataFrame, metadata: dict, **kwargs
    ) -> DataFrame:
        horizon = int(self.config["freqai"].get("label_period_candles", 12))
        dataframe["&-future_return"] = (
            dataframe["close"].shift(-horizon) / dataframe["close"] - 1.0
        )
        return dataframe

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe = self.freqai.start(dataframe, metadata, self)
        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        prediction = dataframe["&-future_return"]
        do_predict = dataframe.get("do_predict", 1)
        dataframe.loc[
            (
                (do_predict == 1)
                & (prediction > 0.002)
                & (dataframe["volume"] > 0)
            ),
            ["enter_long", "enter_tag"],
        ] = (1, "freqai_positive_forecast")
        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        prediction = dataframe["&-future_return"]
        do_predict = dataframe.get("do_predict", 1)
        dataframe.loc[
            (do_predict == 1) & (prediction < -0.001),
            ["exit_long", "exit_tag"],
        ] = (1, "freqai_negative_forecast")
        return dataframe

    @staticmethod
    def _rsi(series, period):
        delta = series.diff()
        gain = delta.clip(lower=0).rolling(period).mean()
        loss = (-delta.clip(upper=0)).rolling(period).mean()
        rs = gain / loss.replace(0, float("nan"))
        return 100 - (100 / (1 + rs))
