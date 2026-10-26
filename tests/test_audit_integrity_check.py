import contextlib
import csv
import io
import os
import runpy
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "audit_integrity_check.py")
MODULE = runpy.run_path(SCRIPT, run_name="audit_checker_module")
main = MODULE["main"]

def write_csv(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        csv.writer(f, delimiter=";").writerows(rows)

class AuditIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.closed = os.path.join(self.tmp.name, "closed.csv")
        self.summary = os.path.join(self.tmp.name, "summary.csv")
        write_csv(self.summary, [
            ["updated_server_time", "2026.10.26 12:00:00"],
            ["magic", "21102027", "history_orders_visible_to_MT4", "2"],
            ["symbol", "closed_trades", "wins_net", "losses_net", "gross_profit", "commission", "swap", "net_profit"],
            ["EURUSD", "2", "1", "1", "1.00", "-0.20", "0.00", "0.80"],
            ["TOTAL", "2", "1", "1", "1.00", "-0.20", "0.00", "0.80"],
        ])

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self):
        old_argv = sys.argv
        stdout = io.StringIO()
        try:
            sys.argv = [SCRIPT, self.closed, self.summary]
            with contextlib.redirect_stdout(stdout):
                main(self.closed, self.summary)
        except SystemExit as exc:
            return int(exc.code) if isinstance(exc.code, int) else 1, str(exc.code), stdout.getvalue()
        finally:
            sys.argv = old_argv
        return 0, "", stdout.getvalue()

    def test_unique_tickets_and_net_reconcile(self):
        write_csv(self.closed, [
            ["timestamp", "decision_id", "ea_version", "ticket", "magic", "symbol", "net_profit"],
            ["t1", "EURUSD_1", "1.8.0.1-EXP", "101", "21102027", "EURUSD", "0.50"],
            ["t2", "EURUSD_2", "1.8.0.1-EXP", "102", "21102027", "EURUSD", "0.30"],
        ])
        code, error, output = self.run_check()
        self.assertEqual(code, 0, error)
        self.assertIn("2 unique closed tickets", output)

    def test_duplicate_ticket_fails(self):
        write_csv(self.closed, [
            ["timestamp", "decision_id", "ea_version", "ticket", "magic", "symbol", "net_profit"],
            ["t1", "EURUSD_1", "1.8.0.1-EXP", "101", "21102027", "EURUSD", "0.50"],
            ["t2", "EURUSD_1", "1.8.0.1-EXP", "101", "21102027", "EURUSD", "0.50"],
        ])
        code, error, output = self.run_check()
        self.assertNotEqual(code, 0)
        self.assertIn("duplicate closed tickets", error)

    def test_net_mismatch_fails(self):
        write_csv(self.closed, [
            ["timestamp", "decision_id", "ea_version", "ticket", "magic", "symbol", "net_profit"],
            ["t1", "EURUSD_1", "1.8.0.1-EXP", "101", "21102027", "EURUSD", "0.50"],
        ])
        code, error, output = self.run_check()
        self.assertNotEqual(code, 0)
        self.assertIn("net reconciliation mismatch", error)

if __name__ == "__main__":
    unittest.main()
