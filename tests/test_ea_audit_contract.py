import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(__file__))
EA_PATH = os.path.join(ROOT, "Bitey_Ensemble_Scalper_MultiAsset_v1_8_0_2_AuditIntegrityImprovedExperimental.mq4")


class EA_AuditContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(EA_PATH, encoding="utf-8") as f:
            cls.source = f.read()

    def test_experimental_version_and_position_ceiling(self):
        self.assertIn('#property version   "1.802"', self.source)
        self.assertIn('#define EA_VERSION          "1.8.0.2-EXP"', self.source)
        self.assertIn("#define HARD_MAX_POSITIONS  5", self.source)

    def test_closed_trade_header_matches_writer_and_initializer(self):
        initializer_headers = re.findall(
            r'BiteyCsvOpenAppend\("Bitey_ClosedTrades_v1_8_0_2\.csv","([^"]+)"\)',
            self.source,
        )
        writer_match = re.search(
            r'bool BiteyCsvLogTradeClosed\([\s\S]*?int h = BiteyCsvOpenAppend\(fn,\s*"([^"]+)"',
            self.source,
        )
        self.assertEqual(len(initializer_headers), 1)
        self.assertIsNotNone(writer_match)
        self.assertEqual(initializer_headers[0], writer_match.group(1))
        headers = [initializer_headers[0], writer_match.group(1)]
        expected = (
            "timestamp;decision_id;ea_version;ticket;magic;symbol;direction;lots;"
            "opened_at;closed_at;duration_seconds;open_price;close_price;gross_profit;"
            "commission;swap;net_profit;slippage_points;buy_votes;sell_votes;close_reason"
        )
        self.assertEqual(headers[0], expected)

    def test_new_version_does_not_reuse_v1801_audit_files(self):
        self.assertNotIn("Bitey_ClosedTrades_v1_8_0_1.csv", self.source)
        self.assertNotIn("Bitey_TradeAudit_v1_8_0_1.csv", self.source)
        self.assertIn("Bitey_ClosedTrades_v1_8_0_2.csv", self.source)
        self.assertIn("Bitey_TradeAudit_v1_8_0_2.csv", self.source)

    def test_dry_run_and_order_send_failures_are_audited(self):
        self.assertIn('"DRY_RUN_CANDIDATE"', self.source)
        self.assertIn('"ORDER_FAILED"', self.source)
        self.assertIn('"OrderSend_error="', self.source)
        self.assertIn('GlobalVariableSet(GvKey("REQPX",ticket),entry);', self.source)

    def test_closed_trade_claim_occurs_only_after_successful_audit_write(self):
        self.assertIn("if(WriteTradeRow(ticket)) GlobalVariableSet(kd,1.0);", self.source)
        self.assertNotIn(
            "GlobalVariableSet(kd,1.0);                       // claim first", self.source
        )

    def test_unknown_slippage_is_not_reported_as_zero(self):
        self.assertIn("double entrySlippagePoints=-1.0;", self.source)
        self.assertIn("entrySlippagePoints=MathAbs(OrderOpenPrice()-GlobalVariableGet(requestedPriceKey))/symbolPoint;", self.source)


if __name__ == "__main__":
    unittest.main()
