#!/usr/bin/env python3
"""Audit reconciliation checks for Bitey MT4 CSV exports.

Usage:
  python audit_integrity_check.py Bitey_ClosedTrades_v1_8_0_1.csv Bitey_Ens_NetByAsset_21102027.csv

The MT4 files use semicolon delimiters. This script fails on duplicate closed
trade tickets and on per-symbol/net-total mismatches between the closed-trade
journal and the net-by-asset summary. It does not change EA logic or trading.
"""
import csv
import sys
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation

def rows(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.reader(f, delimiter=";"))

def dec(value):
    try:
        return Decimal(value.strip())
    except (InvalidOperation, AttributeError):
        return Decimal("0")

def main(closed_path, summary_path):
    closed = rows(closed_path)
    summary = rows(summary_path)
    if not closed or not summary:
        raise SystemExit("FAIL: one or both CSV files are empty")
    ch = [x.strip().lower() for x in closed[0]]
    sh = [x.strip().lower() for x in summary[0]]
    required_c = {"ticket", "symbol", "net_profit"}
    if not required_c.issubset(ch):
        raise SystemExit("FAIL: closed CSV missing required columns: " + ", ".join(sorted(required_c-set(ch))))
    ticket_i, symbol_i, net_i = (ch.index("ticket"), ch.index("symbol"), ch.index("net_profit"))
    tickets = []
    by_symbol = defaultdict(Decimal)
    total = Decimal("0")
    for row in closed[1:]:
        if len(row) <= max(ticket_i, symbol_i, net_i) or not row[ticket_i].strip().isdigit():
            continue
        tickets.append(row[ticket_i].strip())
        net = dec(row[net_i])
        by_symbol[row[symbol_i].strip()] += net
        total += net
    duplicates = [t for t, n in Counter(tickets).items() if n > 1]
    if duplicates:
        raise SystemExit("FAIL: duplicate closed tickets: " + ", ".join(duplicates))
    # Summary format is key/value metadata lines, then a table header.
    header_idx = next((i for i, row in enumerate(summary)
                       if [x.strip().lower() for x in row[:2]] == ["symbol", "closed_trades"]), None)
    if header_idx is None:
        raise SystemExit("FAIL: cannot find symbol/closed_trades table header in summary")
    hdr = [x.strip().lower() for x in summary[header_idx]]
    sym_i, net_i_s = hdr.index("symbol"), hdr.index("net_profit")
    summary_by_symbol = {}
    summary_total = None
    for row in summary[header_idx+1:]:
        if len(row) <= max(sym_i, net_i_s):
            continue
        symbol = row[sym_i].strip()
        value = dec(row[net_i_s])
        if symbol == "TOTAL":
            summary_total = value
        elif symbol:
            summary_by_symbol[symbol] = value
    errors = []
    for symbol in sorted(set(by_symbol) | set(summary_by_symbol)):
        a, b = by_symbol.get(symbol, Decimal("0")), summary_by_symbol.get(symbol, Decimal("0"))
        if abs(a-b) > Decimal("0.02"):
            errors.append(f"{symbol}: closed={a} summary={b}")
    if summary_total is not None and abs(total-summary_total) > Decimal("0.02"):
        errors.append(f"TOTAL: closed={total} summary={summary_total}")
    if errors:
        raise SystemExit("FAIL: net reconciliation mismatch:\n" + "\n".join(errors))
    print(f"PASS: {len(tickets)} unique closed tickets; closed net={total}; per-asset and total sums reconcile.")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: audit_integrity_check.py CLOSED_TRADES.csv NET_BY_ASSET.csv")
    main(sys.argv[1], sys.argv[2])
