#!/usr/bin/env python3
"""Build a Bitey SBT Validation Passport from exported Freqtrade/FreqAI artifacts."""

from __future__ import annotations

import argparse
import json

from app.services.freqai_artifact_adapter import build_evidence_from_artifacts, load_json_artifact
from app.services.freqai_validation_passport import build_freqai_validation_passport


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--backtest", required=True, help="Freqtrade backtest JSON export")
    parser.add_argument("--predictions", help="JSON summary exported from FreqAI predictions")
    parser.add_argument("--lookahead", help="JSON output/summary from lookahead-analysis")
    parser.add_argument("--identifier")
    parser.add_argument("--strategy")
    parser.add_argument("--model")
    parser.add_argument("--timerange")
    parser.add_argument("--dry-run", action=argparse.BooleanOptionalAction, default=True)
    args = parser.parse_args()

    evidence = build_evidence_from_artifacts(
        load_json_artifact(args.backtest),
        prediction_artifact=load_json_artifact(args.predictions) if args.predictions else None,
        lookahead_artifact=load_json_artifact(args.lookahead) if args.lookahead else None,
        dry_run=args.dry_run,
        identifier=args.identifier,
        strategy=args.strategy,
        model=args.model,
        timerange=args.timerange,
    )
    print(json.dumps(build_freqai_validation_passport(evidence), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
