"""Command line entry point.

``snake.exe``              plays the game normally
``snake.exe --selftest``   plays itself through every scene and reports in the logs
"""

from __future__ import annotations

import argparse
import logging
import sys

from . import __version__, config
from .logging_setup import get_logger, log_environment, setup_logging


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="snake", description="Snake")
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run an automated end-to-end game (no human input) and exit with its status",
    )
    parser.add_argument(
        "--steps",
        type=int,
        default=400,
        help="safety budget of world steps for --selftest (default: 400)",
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
    from .engine import Engine
    from .scenes import MenuScene

    if args.selftest:
        return _run_selftest(args, log)

    engine = Engine(seed=args.seed)
    engine.push(MenuScene(engine))
    engine.run()
    log.info("Exit normally")
    return 0


def _run_selftest(args, log) -> int:
    from .agents import GreedyAgent
    from .engine import Engine
    from .scenes import MenuScene
    from .selftest import SelfTestDriver

    log.info("SELFTEST start (step budget=%s, seed=%s)", args.steps, args.seed)
    driver = SelfTestDriver()
    engine = Engine(
        seed=args.seed,
        agent=GreedyAgent(),
        driver=driver,
        max_steps=args.steps,
        # keep the player profile untouched
        profile_path=config.app_dir() / "selftest_profile.json",
    )
    engine.push(MenuScene(engine))
    stats = engine.run()

    failures = driver.verify(stats)
    for failure in failures:
        log.error("SELFTEST check failed: %s", failure)
    log.info(
        "SELFTEST %s: scenes=%s views=%s cameras=%s games=%s best_of_session=%s steps=%s frames=%s fps=%.1f reason=%s",
        "PASS" if not failures else "FAIL",
        sorted(driver.scenes_seen),
        sorted(driver.views_seen),
        sorted(driver.cameras_seen),
        stats.games,
        stats.max_score,
        stats.steps,
        stats.frames,
        stats.fps,
        stats.reason,
    )
    return 0 if not failures else 1
