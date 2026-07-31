#!/usr/bin/env python3
"""
Signal Ledger — Append-only SQLite database for tracking all trading signals.
Provides thread-safe insertion and query methods.
"""

import sqlite3
import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

class SignalLedger:
    def __init__(self, db_path: str = None):
        """Initialize signal ledger. Creates DB if it doesn't exist."""
        if db_path is None:
            # Default to ~/Library/Application Support/AjayTradingBot/signals.db
            app_support = Path.home() / "Library" / "Application Support" / "AjayTradingBot"
            app_support.mkdir(parents=True, exist_ok=True)
            db_path = str(app_support / "signals.db")

        self.db_path = db_path
        self._ensure_schema()

    def _get_connection(self) -> sqlite3.Connection:
        """Get a thread-safe database connection."""
        conn = sqlite3.connect(self.db_path, timeout=10.0, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self):
        """Create schema if it doesn't exist."""
        conn = self._get_connection()
        try:
            conn.execute("""
            CREATE TABLE IF NOT EXISTS signals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                signal_id TEXT UNIQUE NOT NULL,
                timestamp TEXT NOT NULL,
                symbol TEXT NOT NULL,
                direction TEXT NOT NULL,
                confidence TEXT,
                entry_price REAL,
                stop_loss REAL,
                target_1 REAL,
                target_2 REAL,
                qty INTEGER,
                strategy_code TEXT,
                timeframe TEXT,
                market_regime TEXT,
                rsi REAL,
                ema_fast REAL,
                ema_slow REAL,
                volume_ratio REAL,
                scan_id TEXT,
                telegram_status TEXT,
                telegram_timestamp TEXT,
                duplicate_suppressed INTEGER DEFAULT 0,
                data_quality_flags TEXT,
                price_15min REAL,
                price_30min REAL,
                price_60min REAL,
                price_120min REAL,
                price_eod REAL,
                max_favorable_excursion REAL,
                max_adverse_excursion REAL,
                target_reached INTEGER,
                stop_reached INTEGER,
                status TEXT DEFAULT 'unresolved',
                git_sha TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """)
            conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_symbol_date
            ON signals(symbol, timestamp)
            """)
            conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_status
            ON signals(status)
            """)
            conn.commit()
        finally:
            conn.close()

    def insert_signal(self, signal_data: Dict) -> str:
        """
        Insert a signal into the ledger. Returns the signal_id.

        Expected keys:
        - signal_id: unique identifier
        - timestamp: ISO format timestamp
        - symbol: stock symbol
        - direction: BUY/SELL
        - confidence: HIGH/MEDIUM/LOW
        - entry_price, stop_loss, target_1, target_2
        - qty, strategy_code, timeframe, market_regime
        - rsi, ema_fast, ema_slow, volume_ratio
        - scan_id, telegram_status, telegram_timestamp
        - data_quality_flags, git_sha (optional)
        """
        conn = self._get_connection()
        try:
            conn.execute("""
            INSERT INTO signals (
                signal_id, timestamp, symbol, direction, confidence,
                entry_price, stop_loss, target_1, target_2, qty,
                strategy_code, timeframe, market_regime,
                rsi, ema_fast, ema_slow, volume_ratio,
                scan_id, telegram_status, telegram_timestamp,
                data_quality_flags, git_sha
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                signal_data.get('signal_id'),
                signal_data.get('timestamp'),
                signal_data.get('symbol'),
                signal_data.get('direction'),
                signal_data.get('confidence'),
                signal_data.get('entry_price'),
                signal_data.get('stop_loss'),
                signal_data.get('target_1'),
                signal_data.get('target_2'),
                signal_data.get('qty'),
                signal_data.get('strategy_code'),
                signal_data.get('timeframe', '1min'),
                signal_data.get('market_regime'),
                signal_data.get('rsi'),
                signal_data.get('ema_fast'),
                signal_data.get('ema_slow'),
                signal_data.get('volume_ratio'),
                signal_data.get('scan_id'),
                signal_data.get('telegram_status', 'pending'),
                signal_data.get('telegram_timestamp'),
                signal_data.get('data_quality_flags', ''),
                signal_data.get('git_sha'),
            ))
            conn.commit()
            return signal_data.get('signal_id')
        finally:
            conn.close()

    def update_price_at_time(self, signal_id: str, minutes_after: int, price: float):
        """Update price snapshot at N minutes after signal."""
        conn = self._get_connection()
        try:
            column = f"price_{minutes_after}min"
            conn.execute(f"UPDATE signals SET {column} = ? WHERE signal_id = ?",
                        (price, signal_id))
            conn.commit()
        finally:
            conn.close()

    def update_signal_outcome(self, signal_id: str, status: str,
                             mfe: Optional[float] = None,
                             mae: Optional[float] = None,
                             target_hit: Optional[bool] = None,
                             stop_hit: Optional[bool] = None):
        """Update signal with final outcome."""
        conn = self._get_connection()
        try:
            conn.execute("""
            UPDATE signals SET status = ?,
                              max_favorable_excursion = ?,
                              max_adverse_excursion = ?,
                              target_reached = ?,
                              stop_reached = ?
            WHERE signal_id = ?
            """, (status, mfe, mae, target_hit, stop_hit, signal_id))
            conn.commit()
        finally:
            conn.close()

    def get_signals_by_date(self, date: str) -> List[Dict]:
        """Get all signals for a specific date (YYYY-MM-DD)."""
        conn = self._get_connection()
        try:
            cursor = conn.execute("""
            SELECT * FROM signals
            WHERE DATE(timestamp) = ?
            ORDER BY timestamp
            """, (date,))
            return [dict(row) for row in cursor.fetchall()]
        finally:
            conn.close()

    def get_unresolved_signals(self) -> List[Dict]:
        """Get all signals awaiting price updates."""
        conn = self._get_connection()
        try:
            cursor = conn.execute("""
            SELECT * FROM signals
            WHERE status = 'unresolved'
            ORDER BY timestamp DESC
            LIMIT 100
            """)
            return [dict(row) for row in cursor.fetchall()]
        finally:
            conn.close()

    def get_statistics(self, start_date: str = None, end_date: str = None) -> Dict:
        """Get performance statistics for a date range."""
        conn = self._get_connection()
        try:
            where_clause = "1=1"
            params = []

            if start_date:
                where_clause += " AND DATE(timestamp) >= ?"
                params.append(start_date)
            if end_date:
                where_clause += " AND DATE(timestamp) <= ?"
                params.append(end_date)

            # Count signals by status and confidence
            cursor = conn.execute(f"""
            SELECT
                confidence,
                status,
                COUNT(*) as count,
                SUM(CASE WHEN target_reached = 1 THEN 1 ELSE 0 END) as targets_hit,
                SUM(CASE WHEN stop_reached = 1 THEN 1 ELSE 0 END) as stops_hit,
                AVG(max_favorable_excursion) as avg_mfe,
                AVG(max_adverse_excursion) as avg_mae
            FROM signals
            WHERE {where_clause}
            GROUP BY confidence, status
            """, params)

            stats = {
                'by_confidence_status': [dict(row) for row in cursor.fetchall()],
                'total_signals': 0,
                'resolved_signals': 0,
                'win_count': 0,
                'loss_count': 0,
                'win_rate': 0.0
            }

            cursor = conn.execute(f"""
            SELECT
                COUNT(*) as total,
                SUM(CASE WHEN status != 'unresolved' THEN 1 ELSE 0 END) as resolved,
                SUM(CASE WHEN target_reached = 1 THEN 1 ELSE 0 END) as wins,
                SUM(CASE WHEN stop_reached = 1 THEN 1 ELSE 0 END) as losses
            FROM signals
            WHERE {where_clause}
            """, params)

            summary = dict(cursor.fetchone())
            stats['total_signals'] = summary['total'] or 0
            stats['resolved_signals'] = summary['resolved'] or 0
            stats['win_count'] = summary['wins'] or 0
            stats['loss_count'] = summary['losses'] or 0

            if stats['resolved_signals'] > 0:
                stats['win_rate'] = stats['win_count'] / stats['resolved_signals']

            return stats
        finally:
            conn.close()

if __name__ == '__main__':
    ledger = SignalLedger()
    print(f"Signal ledger initialized at {ledger.db_path}")
    print(f"Schema version: 1.0")
