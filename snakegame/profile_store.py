"""Persistent player profile (currently: the best score).

Stored as JSON next to the executable. A corrupted or unreadable file must
never prevent the game from starting, so every failure degrades to defaults.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Optional

from . import config
from .logging_setup import get_logger

log = get_logger("profile")

_DEFAULTS: dict[str, Any] = {"high_score": 0, "games_played": 0}


class Profile:
    def __init__(self, data: dict[str, Any] | None = None, path: Optional[Path] = None) -> None:
        self.path = path or config.SAVE_FILE
        self.data = dict(_DEFAULTS)
        if data:
            self.data.update({k: v for k, v in data.items() if k in _DEFAULTS})

    # ------------------------------------------------------------------ #
    @property
    def high_score(self) -> int:
        return int(self.data["high_score"])

    @property
    def games_played(self) -> int:
        return int(self.data["games_played"])

    def record_game(self, score: int) -> bool:
        """Register a finished game. Returns True on a new record."""
        self.data["games_played"] = self.games_played + 1
        record = score > self.high_score
        if record:
            log.info("New high score: %s (was %s)", score, self.high_score)
            self.data["high_score"] = int(score)
        self.save()
        return record

    # ------------------------------------------------------------------ #
    @classmethod
    def load(cls, path: Optional[Path] = None) -> "Profile":
        path = path or config.SAVE_FILE
        if not path.exists():
            log.info("No profile yet, starting fresh (%s)", path)
            return cls(path=path)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            profile = cls(data, path=path)
            log.info(
                "Profile loaded: high_score=%s games=%s", profile.high_score, profile.games_played
            )
            return profile
        except Exception:
            log.exception("Unreadable profile %s, falling back to defaults", path)
            return cls(path=path)

    def save(self) -> None:
        try:
            self.path.write_text(json.dumps(self.data, indent=2), encoding="utf-8")
        except Exception:
            log.exception("Could not write profile %s", self.path)
