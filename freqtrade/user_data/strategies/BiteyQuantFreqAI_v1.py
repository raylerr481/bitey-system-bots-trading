from __future__ import annotations

from pandas import DataFrame
from freqtrade.persistence import Trade
from freqtrade.strategy import IStrategy
import talib.abstract as ta


class BiteyQuantFreqAI_v1(IStrategy):
    """Causal, research-only FreqAI strategy. Long-only BTC/USDT spot, 1h.
    Future targets are labels only; entries/exits consume FreqAI predictions.
    """

    INTERFACE_VERSION = 3
    can_short = False
    timeframe = "1h"
    startup_candle_count = 250
    minimal_roi = {"0": 0.030, "60": 0.018, "180": 0.008, "360": 0.0}
    stoploss = -0.025
    trailing_stop = False
    process_only_new_candles = True

    LABEL_HORIZON = 12
    MAX_HOLD_CANDLES = 24
    MIN_PREDICTION = 0.0025
    MAX_PREDICTION_STD = 0.010
    MIN_TREND_SCORE = 0.20
    MAX_VOL_REGIME = 2.50
    MIN_VOLUME_RATIO = 0.70

    def version(self) -> str:
        return "1.0.0"

    def feature_engineering_expand_all(self, dataframe: DataFrame, period: int, metadata: dict, **kwargs) -> DataFrame:
        close = dataframe["close"]
        high = dataframe["high"]
        low = dataframe["low"]
        volume = dataframe["volume"]
        dataframe[f"%-rsi_{period}"] = ta.RSI(dataframe, timeperiod=period)
        dataframe[f"%-roc_{period}"] = ta.ROC(dataframe, timeperiod=period)
        dataframe[f"%-atr_pct_{period}"] = ta.ATR(dataframe, timeperiod=period) / close
        dataframe[f"%-range_pct_{period}"] = (high - low) / close
        dataframe[f"%-volume_ratio_{period}"] = volume / volume.rolling(period, min_periods=period).mean()
        dataframe[f"%-return_std_{period}"] = close.pct_change().rolling(period, min_periods=period).std()
        return dataframe

    def feature_engineering_standard(self, dataframe: DataFrame, metadata: dict, **kwargs) -> DataFrame:
        close, high, low, volume = dataframe["close"], dataframe["high"], dataframe["low"], dataframe["volume"]
        ema20 = ta.EMA(dataframe, timeperiod=20)
        ema50 = ta.EMA(dataframe, timeperiod=50)
        ema200 = ta.EMA(dataframe, timeperiod=200)
        atr14 = ta.ATR(dataframe, timeperiod=14)

        dataframe["%-return_1"] = close.pct_change(1)
        dataframe["%-return_3"] = close.pct_change(3)
        dataframe["%-return_12"] = close.pct_change(12)
        dataframe["%-return_acceleration"] = dataframe["%-return_3"] - dataframe["%-return_12"] / 4.0
        dataframe["%-ema20_distance"] = close / ema20 - 1.0
        dataframe["%-ema50_distance"] = close / ema50 - 1.0
        dataframe["%-ema200_distance"] = close / ema200 - 1.0
        dataframe["%-ema20_slope_12"] = ema20.pct_change(12)
        dataframe["%-ema50_slope_24"] = ema50.pct_change(24)
        dataframe["%-adx_14"] = ta.ADX(dataframe, timeperiod=14)
        dataframe["%-rsi_14"] = ta.RSI(dataframe, timeperiod=14)
        dataframe["%-atr_pct_14"] = atr14 / close

        realized_vol = close.pct_change().rolling(24, min_periods=24).std()
        vol_base = realized_vol.rolling(120, min_periods=120).mean()
        dataframe["%-realized_vol_24"] = realized_vol
        dataframe["%-vol_regime_ratio"] = realized_vol / vol_base.replace(0, float("nan"))

        range_pct = (high - low) / close
        dataframe["%-range_expansion"] = range_pct / range_pct.rolling(24, min_periods=24).mean()
        volume_mean = volume.rolling(24, min_periods=24).mean()
        dataframe["%-volume_ratio_24"] = volume / volume_mean.replace(0, float("nan"))

        dataframe["%-trend_score"] = (
            0.35 * (ema20 > ema50).astype(float)
            + 0.35 * (ema50 > ema200).astype(float)
            + 0.30 * (dataframe["%-ema20_slope_12"] > 0).astype(float)
        )
        if "spread" in dataframe.columns:
            dataframe["%-spread_relative"] = dataframe["spread"] / close
        return dataframe

    def set_freqai_targets(self, dataframe: DataFrame, metadata: dict, **kwargs) -> DataFrame:
        """Future labels only. Never use target columns as features."""
        horizon = int(self.config.get("freqai", {}).get("label_period_candles", self.LABEL_HORIZON))
        future_close = dataframe["close"].shift(-horizon)
        future_high = dataframe["high"].shift(-1).rolling(horizon, min_periods=horizon).max().shift(-(horizon - 1))
        future_low = dataframe["low"].shift(-1).rolling(horizon, min_periods=horizon).min().shift(-(horizon - 1))
        dataframe["&-future_return"] = future_close / dataframe["close"] - 1.0
        dataframe["&-future_max_profit"] = future_high / dataframe["close"] - 1.0
        dataframe["&-future_max_loss"] = future_low / dataframe["close"] - 1.0
        dataframe["&-trade_outcome"] = dataframe["&-future_return"] - 0.0015
        return dataframe

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        return self.freqai.start(dataframe, metadata, self)

    @staticmethod
    def _prediction(dataframe: DataFrame, target: str):
        column = f"&-{target}_mean"
        return dataframe[column] if column in dataframe.columns else None

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        prediction = self._prediction(dataframe, "future_return")
        prediction_std = dataframe.get("&-future_return_std")
        if prediction is None:
            dataframe["enter_long"] = 0
            return dataframe
        if prediction_std is None:
            prediction_std = prediction.abs() * 0.0
        do_predict = dataframe.get("do_predict", 0)
        signal = (
            (do_predict == 1)
            & prediction.notna()
            & prediction.gt(self.MIN_PREDICTION)
            & prediction_std.notna()
            & prediction_std.le(self.MAX_PREDICTION_STD)
            & (dataframe["%-trend_score"] >= self.MIN_TREND_SCORE)
            & (dataframe["%-volume_ratio_24"] >= self.MIN_VOLUME_RATIO)
            & (dataframe["%-vol_regime_ratio"] <= self.MAX_VOL_REGIME)
            & dataframe["%-rsi_14"].between(48, 72)
            & (dataframe["volume"] > 0)
        )
        dataframe.loc[signal, ["enter_long", "enter_tag"]] = (1, "fq1_trend_prediction")
        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        prediction = self._prediction(dataframe, "future_return")
        if prediction is None:
            dataframe["exit_long"] = 0
            return dataframe
        do_predict = dataframe.get("do_predict", 0)
        signal = (
            (do_predict == 1)
            & prediction.notna()
            & ((prediction < 0.0) | (dataframe["%-trend_score"] < 0.20))
        )
        dataframe.loc[signal, ["exit_long", "exit_tag"]] = (1, "fq1_prediction_or_regime_exit")
        return dataframe

    def custom_exit(self, pair: str, trade: Trade, current_time, current_rate: float, current_profit: float, **kwargs):
        age_seconds = (current_time - trade.open_date_utc).total_seconds()
        if age_seconds >= self.MAX_HOLD_CANDLES * 60 * 60:
            return "fq1_max_hold"
        return None

    @property
    def protections(self):
        return [
            {"method": "CooldownPeriod", "stop_duration_candles": 2},
            {"method": "StoplossGuard", "lookback_period_candles": 24, "trade_limit": 2, "stop_duration_candles": 12, "only_per_pair": False},
            {"method": "MaxDrawdown", "lookback_period_candles": 72, "trade_limit": 10, "stop_duration_candles": 24, "max_allowed_drawdown": 0.08},
        ]
