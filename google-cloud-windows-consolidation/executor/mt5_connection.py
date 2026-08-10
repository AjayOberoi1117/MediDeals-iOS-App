"""Canonical MetaTrader 5 terminal discovery and initialization.

This module only opens the local MT5 IPC connection.  It never sends orders.
"""

import os
from pathlib import Path
from typing import Optional


DEFAULT_TERMINAL_PATHS = (
    Path(r"C:\Program Files\VIG Group MT5 Terminal\terminal64.exe"),
    Path(r"C:\Program Files\MetaTrader 5\terminal64.exe"),
    Path(r"C:\Program Files (x86)\MetaTrader 5\terminal64.exe"),
)


def discover_terminal_path() -> Optional[Path]:
    """Return the configured or first known installed MT5 terminal."""
    configured = os.getenv("MT5_TERMINAL_PATH", "").strip().strip('"')
    candidates = (Path(configured),) + DEFAULT_TERMINAL_PATHS if configured else DEFAULT_TERMINAL_PATHS
    return next((path for path in candidates if path.is_file()), None)


def initialize_mt5(mt5, *, login: int, password: str, server: str) -> tuple[bool, Optional[Path]]:
    """Initialize MT5 against an explicitly discovered terminal executable."""
    terminal_path = discover_terminal_path()
    if terminal_path is None:
        return False, None
    initialized = mt5.initialize(
        path=str(terminal_path),
        login=login,
        password=password,
        server=server,
    )
    return bool(initialized), terminal_path
