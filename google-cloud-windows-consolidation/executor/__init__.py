# Windows MT5 Executor package
# Reads signals from .trade_queue.jsonl and executes orders via native MetaTrader5 API
# Double-gate safety: signal_only (default) or production (with LIVE_TRADING_CONFIRMED)
# DEMO account mandatory before any order execution
