"""Command line entry point.

``snake.exe``              plays the game normally
``snake.exe --selftest``   plays itself for a while and reports in the logs
"""

from __future__ import annotations

import argparse
import logging
import sys

from . import __version__
from .logging_setup import get_logger, log_environment, setup_logging


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="snake", description="Snake")
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run an automated game (no human input) and exit with its status",
    )
    parser.add_argument(
        "--ticks",
        type=int,
        default=300,
        help="tick budget for --selftest (default: 300)",
    )
    parser.add_argument("--seed", type=int, default=None, help="seed the food RNG")
    parser.add_argument("--debug", action="store_true", help="verbose logging")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    setup_logging(logging.DEBUG if args.debug else logging.INFO)
    log_environment(sys.argv)
    log = get_logger("app")

    # Imported late so that a pygame failure is captured by our logging.
    from .game import SnakeGame

    if args.selftest:
        from .agents import GreedyAgent

        log.info("SELFTEST start (ticks=%s, seed=%s)", args.ticks, args.seed)
        result = SnakeGame(agent=GreedyAgent(), max_ticks=args.ticks, seed=args.seed).run()
        passed = result.ok and result.score > 0
        log.info(
            "SELFTEST %s: score=%s ticks=%s reason=%s errors=%s",
            "PASS" if passed else "FAIL",
            result.score,
            result.ticks,
            result.reason,
            result.errors or "none",
        )
        return 0 if passed else 1

    SnakeGame(seed=args.seed).run()
    log.info("Exit normally")
    return 0
