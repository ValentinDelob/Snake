"""Logging bootstrap.

The game is shipped as a windowed executable, which has no console: the log
file produced here is the only way to diagnose a run, so it must capture the
environment, the gameplay milestones and any uncaught exception.
"""

from __future__ import annotations

import logging
import platform
import sys
from logging.handlers import RotatingFileHandler

from . import __version__, config

LOGGER_NAME = "snake"
_FORMAT = "%(asctime)s | %(levelname)-7s | %(name)-14s | %(message)s"
_DATEFMT = "%Y-%m-%d %H:%M:%S"


def get_logger(suffix: str = "") -> logging.Logger:
    """Return the application logger, optionally a named child of it."""
    return logging.getLogger(f"{LOGGER_NAME}.{suffix}" if suffix else LOGGER_NAME)


def setup_logging(level: int = logging.INFO) -> logging.Logger:
    """Configure file (+ console when available) logging and crash capture."""
    config.LOG_DIR.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger(LOGGER_NAME)
    logger.setLevel(level)
    logger.handlers.clear()
    logger.propagate = False

    formatter = logging.Formatter(_FORMAT, _DATEFMT)

    file_handler = RotatingFileHandler(
        config.LOG_FILE, maxBytes=512_000, backupCount=3, encoding="utf-8"
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    # A windowed PyInstaller build has no stderr; only attach when it exists.
    if sys.stderr is not None:
        stream_handler = logging.StreamHandler(sys.stderr)
        stream_handler.setFormatter(formatter)
        logger.addHandler(stream_handler)

    sys.excepthook = _log_uncaught_exception
    return logger


def log_environment(argv: list[str] | None = None) -> None:
    """Write a startup banner describing the runtime."""
    logger = get_logger("startup")
    logger.info("=" * 68)
    logger.info("Snake v%s starting", __version__)
    logger.info("python   : %s", sys.version.replace("\n", " "))
    logger.info("platform : %s", platform.platform())
    logger.info("frozen   : %s", bool(getattr(sys, "frozen", False)))
    logger.info("app dir  : %s", config.app_dir())
    logger.info("log file : %s", config.LOG_FILE)
    if argv is not None:
        logger.info("argv     : %s", " ".join(argv))
    try:
        import pygame

        logger.info("pygame   : %s (SDL %s)", pygame.version.ver, ".".join(map(str, pygame.get_sdl_version())))
    except Exception:  # pragma: no cover - pygame missing is fatal anyway
        logger.exception("pygame could not be imported")


def _log_uncaught_exception(exc_type, exc_value, exc_tb) -> None:
    if issubclass(exc_type, KeyboardInterrupt):
        sys.__excepthook__(exc_type, exc_value, exc_tb)
        return
    get_logger("crash").critical(
        "Uncaught exception", exc_info=(exc_type, exc_value, exc_tb)
    )
