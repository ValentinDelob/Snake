"""Snake - modular game package.

The package is split by responsibility:

* :mod:`snakegame.config`   - tunable constants and filesystem paths
* :mod:`snakegame.logging_setup` - file/console logging and crash capture
* :mod:`snakegame.geometry` - grid primitives (points, directions)
* :mod:`snakegame.game`     - the game loop and rules
* :mod:`snakegame.agents`   - automated players used by the self-test harness
* :mod:`snakegame.app`      - command line entry point
"""

__version__ = "0.2.0"
