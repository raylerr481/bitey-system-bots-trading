#!/usr/bin/env python3
"""Analyze Bitey v1.8.3.1 Scratch audit exports (standard library only)."""
import argparse
import csv
import os
from collections import defaultdict


def read_csv(path):
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    with open(path, "r", newline="", encoding="utf-8-sig") as f:
        sample = f.read(4096)
        f.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=";,")
        except csv.Error:
            dialect = csv.excel
            dialect.delimiter = ";"
        return list(csv.DictReader(f, dialect=dialect))


def number(row, key, default=0.0):
    try:
        return float(row.get(key, default) or default)
    except (TypeError, ValueError):
        return default


def money(value):
    return f"\${value:,.2f}"


def analyze(trades_path, samples_path, window_sec):
    trades = read_csv(trades_path)
    samples = read_csv(samples_path)
    if not trades or not samples:
        raise ValueError("Uno de los CSV está vacío; todavía no hay muestra suficiente.")

    sample_by_ticket = defaultdict(list)
    for row in samples:
        ticket = str(row.get("ticket", "")).strip()
        if ticket:
            sample_by_ticket[ticket].append(row)

    groups = defaultdict(list)
    all_rows = []
    for trade in trades:
        ticket = str(trade.get("ticket", "")).strip()
        symbol = (trade.get("symbol") or "UNKNOWN").strip()
        close_net = number(trade, "close_net_usd")
        exit_class = (trade.get("exit_class") or "").strip().upper()
        if not exit_class:
            exit_class = "LOSS" if close_net < 0 else "PROFIT_OR_FLAT"

        ticket_samples = sample_by_ticket.get(ticket, [])
        reached = False
        max_first_window = None
        for row in ticket_samples:
            required = number(row, "target_net_usd", 0.10) + number(row, "safety_usd", 0.02)
            net = number(row, "net_after_close_costs_usd", float("-inf"))
            elapsed = number(row, "elapsed_sec", 10**9)
            if elapsed <= window_sec:
                max_first_window = net if max_first_window is None else max(max_first_window, net)
                if net >= required:
                    reached = True

        item = {
            "ticket": ticket, "symbol": symbol, "net": close_net,
            "exit_class": exit_class, "hit_20m": reached,
            "max_20m": max_first_window, "has_samples": bool(ticket_samples),
        }
        groups[symbol].append(item)
        all_rows.append(item)

    def stats(rows):
        n = len(rows)
        wins = [r["net"] for r in rows if r["net"] > 0]
        losses = [r["net"] for r in rows if r["net"] < 0]
        gross_win = sum(wins)
        gross_loss = abs(sum(losses))
        avg_win = gross_win / len(wins) if wins else 0.0
        avg_loss = gross_loss / len(losses) if losses else 0.0
        be = avg_loss / (avg_win + avg_loss) if avg_win + avg_loss else 0.0
        return {
            "n": n, "wins": len(wins), "losses": len(losses),
            "wr": len(wins) / n if n else 0.0,
            "net": sum(r["net"] for r in rows),
            "pf": gross_win / gross_loss if gross_loss else float("inf"),
            "be_wr": be, "hit": sum(r["hit_20m"] for r in rows),
            "sampled": sum(r["has_samples"] for r in rows),
        }

    print(f"Scratch threshold: target + safety (default $0.10 + $0.02); window: {window_sec}s")
    print("Hit rate uses sampled net-after-close-costs, not statement close outcomes.")
    print()
    header = (
        f"{'SYMBOL':<14} {'N':>5} {'WR':>7} {'BE-WR':>7} {'PF':>7} "
        f"{'NET':>11} {'HIT20':>7} {'LOS-HIT':>9} {'SL':>5} {'SAMPLED':>9}"
    )
    print(header)
    print("-" * len(header))

    for symbol in sorted(groups):
        rows = groups[symbol]
        st = stats(rows)
        losers = [r for r in rows if r["net"] < 0]
        sl_rows = [r for r in rows if r["exit_class"] == "SL"]
        sl_hits = sum(r["hit_20m"] for r in sl_rows)
        pf = "inf" if st["pf"] == float("inf") else f"{st['pf']:.2f}"
        print(
            f"{symbol:<14} {st['n']:>5} {st['wr']*100:>6.1f}% {st['be_wr']*100:>6.1f}% "
            f"{pf:>7} {money(st['net']):>11} {st['hit']:>7} "
            f"{sum(r['hit_20m'] for r in losers):>4}/{len(losers):<4} "
            f"{len(sl_rows):>5} {st['sampled']:>5}/{st['n']:<3}"
        )
        if sl_rows:
            print(f"  SL {symbol}: {sl_hits}/{len(sl_rows)} reached target in first {window_sec//60} min")

    overall = stats(all_rows)
    losers = [r for r in all_rows if r["net"] < 0]
    sl_rows = [r for r in all_rows if r["exit_class"] == "SL"]
    print()
    print("OVERALL")
    print(f"Trades: {overall['n']} | sampled: {overall['sampled']} | net: {money(overall['net'])}")
    print(f"Observed WR: {overall['wr']*100:.1f}% | net breakeven WR: {overall['be_wr']*100:.1f}% | PF: {overall['pf']:.2f}")
    print(f"All trades reaching target in first 20 min: {overall['hit']}/{overall['n']}")
    print(f"Losing trades reaching target in first 20 min: {sum(r['hit_20m'] for r in losers)}/{len(losers)}")
    print(f"SL-classified trades reaching target in first 20 min: {sum(r['hit_20m'] for r in sl_rows)}/{len(sl_rows)}")
    print()
    print("Caveats:")
    print("- SL/TP classification is inferred from close price versus the recorded stop/target within a small tolerance.")
    print("- Periodic sampling can miss a brief threshold touch between samples.")
    print("- Net-after-close-costs depends on correct InpEstimatedCloseCommissionPerLot and slippage reserve.")
    print("- Breakeven WR uses realized average net win/loss; it is not a forecast.")
    print("- Require adequate samples and out-of-sample confirmation before changing the symbol universe.")


def main():
    parser = argparse.ArgumentParser(description="Analyze Bitey Scratch trade and sample CSV files.")
    parser.add_argument("--trades", default="Bitey_Scratch_Trades.csv")
    parser.add_argument("--samples", default="Bitey_Scratch_Samples.csv")
    parser.add_argument("--window-sec", type=int, default=1200, help="Default 1200 seconds (20 minutes).")
    args = parser.parse_args()
    analyze(args.trades, args.samples, max(1, args.window_sec))


if __name__ == "__main__":
    main()
