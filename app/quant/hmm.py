"""Research-only Gaussian HMM regime detector.

The model maps observable market features to latent regimes. It never trades or
changes a strategy's parameters; consumers decide which already-defined strategy
is allowed to run for a detected regime.
"""
from __future__ import annotations

import math
import numpy as np


def _features(bars: list[dict[str, float]], window: int = 20) -> np.ndarray:
    closes = np.asarray([float(b["close"]) for b in bars], dtype=float)
    volumes = np.asarray([float(b.get("volume", b.get("tick_volume", 0.0))) for b in bars], dtype=float)
    if len(closes) < window + 3:
        raise ValueError("Need more bars than the feature window")
    r = np.diff(np.log(np.maximum(closes, 1e-12)))
    vol = np.zeros_like(r)
    mom = np.zeros_like(r)
    for i in range(len(r)):
        lo = max(0, i - window + 1)
        vol[i] = np.std(r[lo:i + 1])
        mom[i] = np.sum(r[lo:i + 1])
    x = np.column_stack((r, vol, mom))
    if np.any(volumes[1:] > 0):
        x = np.column_stack((x, np.log1p(volumes[1:])))
    mu, sd = x.mean(axis=0), x.std(axis=0)
    sd[sd < 1e-12] = 1.0
    return (x - mu) / sd


def _log_gaussian(x: np.ndarray, means: np.ndarray, stds: np.ndarray) -> np.ndarray:
    z = (x[:, None, :] - means[None, :, :]) / stds[None, :, :]
    return -0.5 * np.sum(z * z + 2.0 * np.log(stds[None, :, :]) + math.log(2.0 * math.pi), axis=2)


def fit_gaussian_hmm(features: np.ndarray, states: int = 3, iterations: int = 60, seed: int = 7) -> dict:
    if states < 2 or states > 6:
        raise ValueError("states must be between 2 and 6")
    if len(features) < states * 10:
        raise ValueError("Insufficient observations for requested states")
    rng = np.random.default_rng(seed)
    n, d = features.shape
    means = features[np.linspace(0, n - 1, states, dtype=int)].copy()
    means += rng.normal(0, 0.05, means.shape)
    stds = np.tile(np.maximum(features.std(axis=0), 0.2), (states, 1))
    trans = np.full((states, states), 1.0 / states)
    init = np.full(states, 1.0 / states)
    for _ in range(iterations):
        loge = _log_gaussian(features, means, stds)
        alpha = np.zeros((n, states)); scale = np.zeros(n)
        alpha[0] = init * np.exp(loge[0] - np.max(loge[0])); scale[0] = alpha[0].sum(); alpha[0] /= scale[0]
        for t in range(1, n):
            alpha[t] = np.exp(loge[t] - np.max(loge[t])) * (alpha[t - 1] @ trans)
            scale[t] = max(alpha[t].sum(), 1e-300); alpha[t] /= scale[t]
        beta = np.zeros((n, states)); beta[-1] = 1.0
        for t in range(n - 2, -1, -1): beta[t] = (trans @ (np.exp(loge[t + 1] - np.max(loge[t + 1])) * beta[t + 1])) / max(scale[t + 1], 1e-300)
        gamma = alpha * beta; gamma /= np.maximum(gamma.sum(axis=1, keepdims=True), 1e-300)
        xi_sum = np.zeros_like(trans)
        for t in range(n - 1):
            e = np.exp(loge[t + 1] - np.max(loge[t + 1]))
            xi = alpha[t, :, None] * trans * e[None, :] * beta[t + 1, None, :]
            xi /= max(xi.sum(), 1e-300); xi_sum += xi
        init = gamma[0]
        trans = xi_sum / np.maximum(xi_sum.sum(axis=1, keepdims=True), 1e-300)
        weights = gamma.sum(axis=0)
        means = (gamma.T @ features) / np.maximum(weights[:, None], 1e-12)
        centered2 = (features[:, None, :] - means[None, :, :]) ** 2
        var = np.einsum("ns,nsd->sd", gamma, centered2) / np.maximum(weights[:, None], 1e-12)
        stds = np.sqrt(np.maximum(var, 1e-5))
    posterior = gamma
    labels = posterior.argmax(axis=1)
    return {"states": states, "means": means, "stds": stds, "transition_matrix": trans, "initial_probabilities": init, "posterior": posterior, "labels": labels}


def analyze_regimes(bars: list[dict[str, float]], states: int | str = "auto", window: int = 20, seed: int = 7) -> dict:
    x = _features(bars, window)
    if states == "auto":
        candidates = [k for k in (2, 3, 4, 5) if len(x) >= k * 15]
        states = min(candidates, key=lambda k: _bic_for_model(x, fit_gaussian_hmm(x, k, 35, seed))) if candidates else 2
    model = fit_gaussian_hmm(x, int(states), 60, seed)
    labels = model["labels"]
    returns = np.diff(np.log(np.maximum(np.asarray([float(b["close"]) for b in bars]), 1e-12)))
    summary = []
    for s in range(model["states"]):
        rr = returns[-len(labels):][labels == s]
        summary.append({"state": s, "observations": int((labels == s).sum()), "share_pct": float((labels == s).mean() * 100), "mean_return": float(rr.mean()) if len(rr) else 0.0, "volatility": float(rr.std()) if len(rr) else 0.0})
    return {"contract": "sbt-hmm-regime-v1", "data_mode": "OHLCV", "feature_set": ["returns", "rolling_volatility", "momentum", "log_volume"], "states": model["states"], "current_state": int(labels[-1]), "regime_summary": summary, "transition_matrix": model["transition_matrix"].round(6).tolist(), "state_labels": labels.tolist(), "safety": {"live": False, "real_money": False, "broker_orders": 0}}


def _bic_for_model(x: np.ndarray, model: dict) -> float:
    loge = _log_gaussian(x, model["means"], model["stds"])
    ll = float(np.max(loge, axis=1).sum())
    p = model["states"] * x.shape[1] * 2 + model["states"] * (model["states"] - 1)
    return -2 * ll + p * math.log(len(x))
