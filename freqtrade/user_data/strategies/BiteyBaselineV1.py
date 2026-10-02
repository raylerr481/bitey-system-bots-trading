from pandas import DataFrame
import talib.abstract as ta

from freqtrade.strategy import IStrategy


class BiteyBaselineV1(IStrategy):
    """
    Deterministic baseline used to validate the Bitey SBT <-> Freqtrade
    integration before adding AI/ML decisions.

    This is a research baseline, not a production strategy.
    """

    INTERFACE_VERSION = 3

    can_short = False
    timeframe = "1h"
    startup_candle_count = 200

    minimal_roi = {
        "0": 0.02,
        "60": 0.01,
        "180": 0
    }

    stoploss = -0.03

    trailing_stop = False

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe["ema_fast"] = ta.EMA(dataframe, timeperiod=21)
        dataframe["ema_slow"] = ta.EMA(dataframe, timeperiod=200)
        dataframe["rsi"] = ta.RSI(dataframe, timeperiod=14)
        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (dataframe["ema_fast"] > dataframe["ema_slow"])
                & (dataframe["rsi"] > 50)
                & (dataframe["rsi"] < 70)
                & (dataframe["volume"] > 0)
            ),
            ["enter_long", "enter_tag"],
        ] = (1, "baseline_trend")

        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (dataframe["ema_fast"] < dataframe["ema_slow"])
                | (dataframe["rsi"] < 45)
            ),
            ["exit_long", "exit_tag"],
        ] = (1, "baseline_exit")

        return dataframe
