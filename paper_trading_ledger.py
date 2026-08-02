"""
PAPER-TRADING LEDGER AND SIMULATION ENGINE
===========================================

Central SQLite ledger for recording all simulated trades across bots.
Enables accurate performance tracking without touching real broker APIs.

Schema: Comprehensive trade record with realistic cost assumptions.
"""

import sqlite3
import json
import logging
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from enum import Enum
from pathlib import Path

log = logging.getLogger(__name__)


class TradeStatus(Enum):
    """Trade status in paper-trading ledger."""
    ENTRY_PENDING = "entry_pending"
    ENTERED = "entered"
    PARTIAL_EXIT = "partial_exit"
    EXITED = "exited"
    CANCELLED = "cancelled"
    REJECTED = "rejected"


class ExitReason(Enum):
    """Reason for trade exit."""
    TARGET_HIT = "target_hit"
    STOP_LOSS_HIT = "stop_loss_hit"
    TRAILING_STOP = "trailing_stop"
    TIME_BASED = "time_based"
    MANUAL_CLOSE = "manual_close"
    MARKET_CLOSE = "market_close"
    SIGNAL_REVERSAL = "signal_reversal"


class PaperTradingLedger:
    """SQLite ledger for paper trading records."""

    def __init__(self, db_path: Optional[str] = None):
        """
        Initialize ledger.

        Args:
            db_path: Path to SQLite database (default: ~/.paper_trades.db)
        """
        if db_path is None:
            db_path = str(Path.home() / ".paper_trades.db")

        self.db_path = db_path
        self._init_db()
        log.info(f"Paper trading ledger initialized at {self.db_path}")

    def _init_db(self):
        """Create schema if not exists."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("PRAGMA journal_mode=WAL")  # Write-Ahead Logging for concurrency
            cursor = conn.cursor()

            # Main trades table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS trades (
                    trade_id TEXT PRIMARY KEY,
                    bot_id TEXT NOT NULL,
                    strategy_version TEXT,
                    signal_id TEXT,
                    symbol TEXT NOT NULL,
                    exchange TEXT,
                    instrument_type TEXT DEFAULT 'EQUITY',

                    direction TEXT NOT NULL,  -- BUY or SELL
                    quantity INT NOT NULL,
                    notional_exposure REAL,

                    entry_time TEXT,
                    entry_price REAL,
                    assumed_fill_price REAL,

                    stop_loss REAL,
                    target_1 REAL,
                    target_2 REAL,
                    trailing_stop REAL,

                    exit_time TEXT,
                    exit_price REAL,
                    exit_reason TEXT,

                    gross_pnl REAL,
                    brokerage REAL,
                    stt_charges REAL,
                    exchange_charges REAL,
                    taxes REAL,
                    slippage REAL,
                    estimated_latency_ms INT,
                    spread REAL,

                    net_pnl REAL,
                    pnl_pct REAL,

                    max_favorable_excursion REAL,
                    max_favorable_excursion_pct REAL,
                    max_adverse_excursion REAL,
                    max_adverse_excursion_pct REAL,

                    confidence_level TEXT,
                    market_regime TEXT,
                    data_quality_status TEXT,

                    status TEXT NOT NULL,  -- TradeStatus
                    git_commit_sha TEXT,

                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    notes TEXT
                )
            """)

            # Delivery tracking table (for Telegram, emails, etc.)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS signal_delivery (
                    delivery_id TEXT PRIMARY KEY,
                    trade_id TEXT NOT NULL,
                    channel TEXT NOT NULL,  -- telegram, email, sms
                    message_id TEXT,
                    status TEXT NOT NULL,  -- attempted, delivered, failed
                    attempts INT DEFAULT 1,
                    last_error TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY (trade_id) REFERENCES trades (trade_id)
                )
            """)

            # Price snapshots table (for MFE/MAE calculation)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS price_snapshots (
                    snapshot_id TEXT PRIMARY KEY,
                    trade_id TEXT NOT NULL,
                    offset_seconds INT,  -- 60, 300, 900, 1800, etc.
                    offset_name TEXT,    -- 1min, 5min, 15min, 30min, eod
                    price REAL,
                    time TEXT,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY (trade_id) REFERENCES trades (trade_id)
                )
            """)

            # Indexes for performance
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_trades_bot_id ON trades(bot_id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_trades_symbol ON trades(symbol)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_trades_entry_time ON trades(entry_time)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_delivery_trade_id ON signal_delivery(trade_id)")

            conn.commit()

    def record_entry_signal(
        self,
        trade_id: str,
        bot_id: str,
        symbol: str,
        direction: str,
        entry_price: float,
        quantity: int,
        stop_loss: float,
        target_1: float,
        target_2: Optional[float] = None,
        trailing_stop: Optional[float] = None,
        confidence_level: str = "MEDIUM",
        signal_id: Optional[str] = None,
        strategy_version: Optional[str] = None,
        git_commit_sha: Optional[str] = None,
        **kwargs
    ) -> bool:
        """
        Record entry signal in ledger.

        Args:
            trade_id: Unique trade identifier
            bot_id: Bot that generated the signal
            symbol: Trading symbol
            direction: BUY or SELL
            entry_price: Signal price
            quantity: Quantity to trade
            stop_loss: Stop-loss level
            target_1: First target
            target_2: Second target (optional)
            trailing_stop: Trailing stop (optional)
            confidence_level: HIGH/MEDIUM/LOW
            signal_id: Cross-reference to signal
            strategy_version: Strategy version
            git_commit_sha: Git commit for reproducibility
            **kwargs: Additional fields

        Returns:
            bool: True if recorded successfully
        """
        try:
            notional = entry_price * quantity
            now = datetime.utcnow().isoformat()

            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT INTO trades (
                        trade_id, bot_id, symbol, direction, quantity, notional_exposure,
                        entry_price, assumed_fill_price, stop_loss, target_1, target_2, trailing_stop,
                        confidence_level, signal_id, strategy_version, git_commit_sha,
                        status, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    trade_id, bot_id, symbol, direction, quantity, notional,
                    entry_price, entry_price, stop_loss, target_1, target_2, trailing_stop,
                    confidence_level, signal_id, strategy_version, git_commit_sha,
                    TradeStatus.ENTRY_PENDING.value, now, now
                ))
                conn.commit()
            return True
        except Exception as e:
            log.error(f"Failed to record entry signal {trade_id}: {e}")
            return False

    def record_entry_fill(
        self,
        trade_id: str,
        fill_price: float,
        fill_time: str,
        slippage: float = 0.0,
        estimated_latency_ms: int = 100,
        spread: float = 0.0,
    ) -> bool:
        """
        Record actual entry fill.

        Args:
            trade_id: Trade identifier
            fill_price: Actual fill price
            fill_time: Fill time
            slippage: Realized slippage
            estimated_latency_ms: Network latency estimate
            spread: Bid-ask spread

        Returns:
            bool: True if recorded successfully
        """
        try:
            now = datetime.utcnow().isoformat()
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    UPDATE trades
                    SET entry_time = ?, entry_price = ?, slippage = ?,
                        estimated_latency_ms = ?, spread = ?,
                        status = ?, updated_at = ?
                    WHERE trade_id = ?
                """, (
                    fill_time, fill_price, slippage, estimated_latency_ms,
                    spread, TradeStatus.ENTERED.value, now, trade_id
                ))
                conn.commit()
            return True
        except Exception as e:
            log.error(f"Failed to record entry fill {trade_id}: {e}")
            return False

    def record_exit(
        self,
        trade_id: str,
        exit_price: float,
        exit_time: str,
        exit_reason: str,
        brokerage: float = 0.0,
        stt_charges: float = 0.0,
        exchange_charges: float = 0.0,
        taxes: float = 0.0,
    ) -> bool:
        """
        Record trade exit.

        Args:
            trade_id: Trade identifier
            exit_price: Exit price
            exit_time: Exit time
            exit_reason: Reason for exit (TARGET_HIT, STOP_LOSS, etc.)
            brokerage: Trading fees/commission
            stt_charges: Securities transaction tax
            exchange_charges: Exchange fees
            taxes: Other taxes

        Returns:
            bool: True if recorded successfully
        """
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()

                # Get entry details
                cursor.execute("""
                    SELECT entry_price, quantity, direction
                    FROM trades
                    WHERE trade_id = ?
                """, (trade_id,))
                row = cursor.fetchone()
                if not row:
                    log.error(f"Trade {trade_id} not found")
                    return False

                entry_price, quantity, direction = row

                # Calculate P&L
                if direction == "BUY":
                    gross_pnl = (exit_price - entry_price) * quantity
                else:  # SELL
                    gross_pnl = (entry_price - exit_price) * quantity

                total_costs = brokerage + stt_charges + exchange_charges + taxes
                net_pnl = gross_pnl - total_costs
                pnl_pct = (net_pnl / (entry_price * quantity)) * 100 if entry_price > 0 else 0

                now = datetime.utcnow().isoformat()
                cursor.execute("""
                    UPDATE trades
                    SET exit_time = ?, exit_price = ?, exit_reason = ?,
                        gross_pnl = ?, brokerage = ?, stt_charges = ?,
                        exchange_charges = ?, taxes = ?,
                        net_pnl = ?, pnl_pct = ?,
                        status = ?, updated_at = ?
                    WHERE trade_id = ?
                """, (
                    exit_time, exit_price, exit_reason,
                    gross_pnl, brokerage, stt_charges,
                    exchange_charges, taxes,
                    net_pnl, pnl_pct,
                    TradeStatus.EXITED.value, now, trade_id
                ))
                conn.commit()
            return True
        except Exception as e:
            log.error(f"Failed to record exit {trade_id}: {e}")
            return False

    def record_price_snapshot(
        self,
        trade_id: str,
        offset_seconds: int,
        offset_name: str,
        price: float,
        time: str,
    ) -> bool:
        """
        Record price snapshot for MFE/MAE calculation.

        Args:
            trade_id: Trade identifier
            offset_seconds: Offset from entry (e.g., 60 for 1-min snapshot)
            offset_name: Human-readable name (e.g., "1min", "15min", "eod")
            price: Price at snapshot
            time: Snapshot time

        Returns:
            bool: True if recorded successfully
        """
        try:
            snapshot_id = f"{trade_id}_{offset_name}"
            now = datetime.utcnow().isoformat()

            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT OR REPLACE INTO price_snapshots (
                        snapshot_id, trade_id, offset_seconds, offset_name,
                        price, time, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (snapshot_id, trade_id, offset_seconds, offset_name, price, time, now))
                conn.commit()
            return True
        except Exception as e:
            log.error(f"Failed to record price snapshot {trade_id}: {e}")
            return False

    def get_trades_by_bot(self, bot_id: str) -> List[Dict]:
        """Get all trades by bot."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT * FROM trades WHERE bot_id = ?
                    ORDER BY created_at DESC
                """, (bot_id,))
                return [dict(row) for row in cursor.fetchall()]
        except Exception as e:
            log.error(f"Failed to get trades for {bot_id}: {e}")
            return []

    def get_trades_by_date(self, bot_id: str, date_str: str) -> List[Dict]:
        """Get trades on a specific date."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT * FROM trades
                    WHERE bot_id = ? AND DATE(entry_time) = ?
                    ORDER BY entry_time
                """, (bot_id, date_str))
                return [dict(row) for row in cursor.fetchall()]
        except Exception as e:
            log.error(f"Failed to get trades for {bot_id} on {date_str}: {e}")
            return []

    def get_statistics(self, bot_id: str, start_date: str, end_date: str) -> Dict:
        """
        Get performance statistics for a bot over date range.

        Returns:
            dict with: win_rate, avg_win, avg_loss, payoff_ratio, net_pnl, etc.
        """
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()

                # Get all exited trades in date range
                cursor.execute("""
                    SELECT net_pnl, gross_pnl, pnl_pct, status, confidence_level
                    FROM trades
                    WHERE bot_id = ? AND status = ? AND DATE(exit_time) BETWEEN ? AND ?
                    ORDER BY exit_time
                """, (bot_id, TradeStatus.EXITED.value, start_date, end_date))

                trades = cursor.fetchall()
                if not trades:
                    return {"total_trades": 0, "warning": "No exited trades in range"}

                wins = sum(1 for t in trades if t[0] and t[0] > 0)
                losses = sum(1 for t in trades if t[0] and t[0] < 0)
                total = len(trades)

                win_pnls = [t[0] for t in trades if t[0] and t[0] > 0]
                loss_pnls = [t[0] for t in trades if t[0] and t[0] < 0]

                avg_win = sum(win_pnls) / len(win_pnls) if win_pnls else 0
                avg_loss = abs(sum(loss_pnls) / len(loss_pnls)) if loss_pnls else 0
                payoff_ratio = avg_win / avg_loss if avg_loss > 0 else 0

                net_pnl = sum(t[0] for t in trades if t[0])
                profit_factor = sum(win_pnls) / abs(sum(loss_pnls)) if loss_pnls and sum(loss_pnls) != 0 else 0

                return {
                    "total_trades": total,
                    "wins": wins,
                    "losses": losses,
                    "win_rate": wins / total if total > 0 else 0,
                    "avg_win": avg_win,
                    "avg_loss": avg_loss,
                    "payoff_ratio": payoff_ratio,
                    "net_pnl": net_pnl,
                    "profit_factor": profit_factor,
                    "sample_size_warning": total < 20,
                }
        except Exception as e:
            log.error(f"Failed to get statistics for {bot_id}: {e}")
            return {"error": str(e)}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    # Test ledger
    ledger = PaperTradingLedger()

    # Record a trade
    trade_id = "TRADE_20260731_001"
    ledger.record_entry_signal(
        trade_id=trade_id,
        bot_id="scanner_v2",
        symbol="RELIANCE",
        direction="BUY",
        entry_price=2815.50,
        quantity=10,
        stop_loss=2750.00,
        target_1=2900.00,
        confidence_level="HIGH",
        signal_id="SIG_001",
    )
    print(f"✓ Recorded entry signal: {trade_id}")

    # Record exit
    ledger.record_exit(
        trade_id=trade_id,
        exit_price=2900.00,
        exit_time="2026-07-31 13:45:00",
        exit_reason=ExitReason.TARGET_HIT.value,
        brokerage=100.0,
        stt_charges=50.0,
    )
    print(f"✓ Recorded exit: {trade_id}")

    # Get statistics
    stats = ledger.get_statistics("scanner_v2", "2026-07-31", "2026-07-31")
    print(f"\n✓ Statistics:")
    for k, v in stats.items():
        print(f"  {k}: {v}")
