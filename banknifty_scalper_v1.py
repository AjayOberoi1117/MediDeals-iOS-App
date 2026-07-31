#!/usr/bin/env python3
"""
BANKNIFTY-SCALPER-V1

Strategy: Opening Range Breakout + EMA Trend Confirmation (Calibrated for higher volatility)

Instruments: BANKNIFTY Index (^NSEBANK)
Timeframe: 15-minute candles
Mode: Paper trading simulation with paper_trading_ledger integration
Data: Yahoo Finance (delayed data - ~15-30min latency)

DIFFERENCES FROM NIFTY50:
- Higher volatility: ATR multipliers scaled up
- Larger opening range (4 candles vs 3)
- Tighter daily loss limit (accounting for bigger moves)
- Fewer daily trades allowed (3 vs 5) due to higher variance

RISK CONTROLS:
- No martingale, averaging, or revenge trading
- Max 3 trades per session (vs 5 for NIFTY)
- 5-minute cooldown after stop loss
- 3-minute cooldown after win
- Daily loss limit: -300 points (vs -500 for NIFTY, due to higher per-trade risk)
- Max 2 consecutive losses → stop trading

SIGNAL GENERATION:
1. Identify opening range (first 4 candles of session = 9:15-10:45 IST)
2. Breakout: Close above opening range high / below opening range low
3. Confirmation: EMA(9) slope positive (BUY) or negative (SELL)
4. Volatility filter: ATR must be expanding (not choppy market)
5. Entry: At candle close that breaks range + meets confirmation

EXIT RULES:
- Stop loss: 2.0 × ATR(14) from entry (higher than NIFTY's 1.5× due to volatility)
- Target: 4.0 × ATR(14) from entry (higher than NIFTY's 3.0× due to volatility)
- Time exit: 50 candles maximum (≈12.5 hours of 15m bars, half of NIFTY to capture quick moves)

PAPER INTEGRATION:
- Every signal logged to paper_trading_ledger
- Telegram alerts with [PAPER][BANKNIFTY-SCALPER-V1-DELAYED-DATA] prefix
- Realistic cost modeling (STT, exchange charges, slippage)
"""

import logging
import pandas as pd
import numpy as np
from datetime import datetime, timedelta, time as dt_time
from dataclasses import dataclass
from typing import Optional, Tuple, List
import json
import os
import pytz

# Import shared infrastructure
from paper_trading_ledger import PaperTradingLedger
from telegram_router import TelegramRouter
from trading_bot_safety import enforce_demo_mode, get_paper_trading_label

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

# ============================================================================
# CONFIGURATION (CALIBRATED FOR HIGHER VOLATILITY)
# ============================================================================

CONFIG = {
    "bot_id": "banknifty_scalper_v1",
    "bot_name": "BANKNIFTY-SCALPER-V1-DELAYED-DATA",
    "symbol": "BANKNIFTY",
    "index_ticker": "^NSEBANK",
    "timeframe_minutes": 15,

    # Strategy parameters (higher vol than NIFTY)
    "opening_range_bars": 4,  # 4 * 15min = 60 minutes (vs 3 for NIFTY)
    "ema_period": 9,
    "atr_period": 14,
    "sl_atr_multiplier": 2.0,  # Higher SL (2.0 vs 1.5 for NIFTY)
    "tp_atr_multiplier": 4.0,  # Higher TP (4.0 vs 3.0 for NIFTY)
    "atr_expansion_threshold": 0.05,  # ATR must grow by 5% minimum

    # Trade management (conservative for high vol)
    "max_trades_per_session": 3,  # Lower than NIFTY's 5
    "cooldown_minutes_after_loss": 5,
    "cooldown_minutes_after_win": 3,  # Slightly longer than NIFTY's 2
    "daily_loss_limit_points": -300,  # Lower than NIFTY's -500 due to bigger moves
    "max_consecutive_losses": 2,  # Lower than NIFTY's 3
    "max_holding_candles": 50,  # ~12.5 hours (vs 25 for NIFTY, capture quick moves)

    # Time filters (IST)
    "market_open_hour": 9,
    "market_open_minute": 15,
    "market_close_hour": 15,
    "market_close_minute": 30,
    "no_entry_after_hour": 15,  # 3 PM IST

    # Data quality
    "min_volume_threshold": 10000,
    "max_data_delay_minutes": 30,
    "historical_candles_required": 20,

    # Cost assumptions (paper trading)
    "estimated_brokerage_percent": 0.02,  # 0.02% per side
    "estimated_stt_percent": 0.025,  # STT on NSE equity
    "estimated_exchange_charges_percent": 0.01,  # Exchange charges
    "estimated_slippage_points": 10,  # Higher slippage for BANKNIFTY (10 vs 5 for NIFTY)
}

# ============================================================================
# BOT STATE
# ============================================================================

@dataclass
class TradeState:
    """Current trade state tracking."""
    last_entry_time: Optional[datetime] = None
    last_exit_time: Optional[datetime] = None
    consecutive_losses: int = 0
    daily_pnl_points: float = 0.0
    trades_today: int = 0
    last_exit_reason: Optional[str] = None

# ============================================================================
# BANKNIFTY SCALPER V1
# ============================================================================

class BankNiftyScalperV1:
    """BANKNIFTY scalper using opening range breakout strategy (calibrated for volatility)."""

    def __init__(self, db_path: str = "paper_trading.db"):
        # Enforce paper mode
        mode = enforce_demo_mode()
        log.info(f"Trading mode: {mode}")

        self.config = CONFIG
        self.ledger = PaperTradingLedger(db_path)
        self.router = TelegramRouter()
        self.state = TradeState()
        self.ist_tz = pytz.timezone('Asia/Kolkata')
        self.utc_tz = pytz.UTC

    def is_trading_hours(self, now: datetime) -> bool:
        """Check if within NSE trading hours."""
        if now.weekday() >= 5:  # Saturday or Sunday
            return False

        # Check if within 9:15 AM - 3:30 PM IST
        now_ist = now.astimezone(self.ist_tz)
        market_open = dt_time(9, 15)
        market_close = dt_time(15, 30)

        return market_open <= now_ist.time() <= market_close

    def can_entry(self, now: datetime) -> Tuple[bool, str]:
        """Check if entry is permitted based on risk controls."""
        now_ist = now.astimezone(self.ist_tz)

        # Don't enter after 3 PM IST
        if now_ist.hour >= self.config["no_entry_after_hour"]:
            return False, "After no-entry time"

        # Check cooldown from last trade
        if self.state.last_exit_time:
            if self.state.last_exit_reason == "STOP_LOSS_HIT":
                cooldown = self.config["cooldown_minutes_after_loss"]
            else:
                cooldown = self.config["cooldown_minutes_after_win"]

            time_since_exit = (now - self.state.last_exit_time).total_seconds() / 60
            if time_since_exit < cooldown:
                return False, f"Cooldown: {cooldown - time_since_exit:.0f}m remaining"

        # Check max trades per session
        if self.state.trades_today >= self.config["max_trades_per_session"]:
            return False, f"Max {self.config['max_trades_per_session']} trades reached"

        # Check consecutive losses
        if self.state.consecutive_losses >= self.config["max_consecutive_losses"]:
            return False, f"Max {self.config['max_consecutive_losses']} consecutive losses"

        # Check daily loss limit
        if self.state.daily_pnl_points <= self.config["daily_loss_limit_points"]:
            return False, "Daily loss limit hit"

        return True, "OK"

    def calculate_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """Calculate technical indicators."""
        df = df.copy()

        # EMA(9)
        df['ema9'] = df['close'].ewm(span=9, adjust=False).mean()

        # ATR(14)
        high = df['high']
        low = df['low']
        close = df['close']
        tr1 = high - low
        tr2 = (high - close.shift()).abs()
        tr3 = (low - close.shift()).abs()
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        df['atr'] = tr.rolling(self.config["atr_period"]).mean()

        # EMA slope (direction)
        df['ema_slope'] = df['ema9'].diff()

        return df

    def generate_signals(self, df: pd.DataFrame) -> List[Tuple[int, str, float]]:
        """
        Generate trading signals from candles.

        Returns: List of (candle_index, signal_direction, confidence)
        """
        df = self.calculate_indicators(df)
        signals = []

        # Need at least opening range + some history
        min_required = self.config["opening_range_bars"] + self.config["atr_period"]
        if len(df) < min_required:
            return signals

        # Identify opening range (first N candles)
        opening_range_end = self.config["opening_range_bars"]
        opening_high = df['high'].iloc[:opening_range_end].max()
        opening_low = df['low'].iloc[:opening_range_end].min()

        # Check for breakouts from opening range onward
        for i in range(opening_range_end, len(df)):
            candle = df.iloc[i]
            close = candle['close']
            atr = candle['atr']

            if pd.isna(atr) or atr == 0:
                continue

            # Check for ATR expansion (not choppy)
            if i >= 1:
                atr_prev = df.iloc[i-1]['atr']
                if atr_prev > 0:
                    atr_expansion = (atr - atr_prev) / atr_prev
                    if atr_expansion < self.config["atr_expansion_threshold"]:
                        continue  # Market too choppy, skip

            # Breakout criteria
            breakout_high = close > opening_high
            breakout_low = close < opening_low
            ema_slope = candle['ema_slope']

            # BUY: Breakout above + EMA rising
            if breakout_high and ema_slope > 0:
                signals.append((i, "BUY", 0.8))

            # SELL: Breakout below + EMA falling
            elif breakout_low and ema_slope < 0:
                signals.append((i, "SELL", 0.8))

        return signals

    def calculate_stops_and_targets(
        self,
        entry_price: float,
        direction: str,
        atr: float
    ) -> Tuple[float, float]:
        """Calculate SL and TP based on ATR (higher multipliers for BANKNIFTY volatility)."""
        sl_distance = self.config["sl_atr_multiplier"] * atr
        tp_distance = self.config["tp_atr_multiplier"] * atr

        if direction == "BUY":
            stop_loss = entry_price - sl_distance
            target = entry_price + tp_distance
        else:  # SELL
            stop_loss = entry_price + sl_distance
            target = entry_price - tp_distance

        return stop_loss, target

    def record_signal_to_ledger(
        self,
        signal_direction: str,
        entry_price: float,
        stop_loss: float,
        target: float,
        confidence: float,
        atr: float,
        candle_time: datetime
    ) -> str:
        """Record signal to paper trading ledger."""
        trade_id = f"{self.config['bot_id']}__{candle_time.isoformat()}"

        self.ledger.record_entry_signal(
            trade_id=trade_id,
            bot_id=self.config["bot_id"],
            symbol=self.config["symbol"],
            direction=signal_direction,
            entry_price=entry_price,
            quantity=1,  # Index points (not rupees)
            stop_loss=stop_loss,
            target_1=target,
            confidence_level=f"confidence_{confidence:.0%}",
            data_quality_status="delayed_data_acknowledged",
        )

        log.info(f"✓ Signal recorded: {trade_id}")
        return trade_id

    def send_signal_alert(
        self,
        direction: str,
        entry_price: float,
        stop_loss: float,
        target: float,
        candle_time: datetime,
        atr: float,
        trade_id: str
    ) -> bool:
        """Send Telegram alert for new signal."""
        emoji = "🟢" if direction == "BUY" else "🔴"
        now_ist = candle_time.astimezone(self.ist_tz)

        risk_points = abs(entry_price - stop_loss)
        reward_points = abs(target - entry_price)
        rr = reward_points / risk_points if risk_points > 0 else 0

        message = (
            f"{emoji} <b>[PAPER] BANKNIFTY-SCALPER-V1 — {direction}</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📊 <b>DELAYED-DATA RESEARCH MODE</b>\n"
            f"Data delay: ~15-30 minutes\n"
            f"No real broker orders\n"
            f"Simulated entry only\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"\n"
            f"📍 <b>Entry Reference:</b> {entry_price:.2f}\n"
            f"🛑 <b>Stop Loss:</b> {stop_loss:.2f} ({risk_points:.0f} pts)\n"
            f"🎯 <b>Target:</b> {target:.2f} ({reward_points:.0f} pts)\n"
            f"⚖️ <b>Risk/Reward:</b> 1:{rr:.1f}\n"
            f"📈 <b>ATR(14):</b> {atr:.2f}\n"
            f"\n"
            f"📅 <b>Signal Time (IST):</b> {now_ist.strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"🆔 <b>Signal ID:</b> {trade_id}\n"
            f"⏰ <b>Timeframe:</b> 15-minute candles\n"
            f"⚠️ <b>Note:</b> Higher volatility profile vs NIFTY50\n"
            f"\n"
            f"⚠️ <i>This is simulated paper trading observation only.</i>\n"
            f"<i>Entry will be significantly delayed due to data latency.</i>\n"
            f"<i>Strategy suitable for research, not live deployment.</i>"
        )

        success, msg_id = self.router.send_alert(
            bot_id=self.config["bot_id"],
            message_type="entry_signal",
            message_text=message,
        )

        if success:
            log.info(f"✓ Telegram alert sent: {msg_id}")
        else:
            log.error(f"✗ Telegram alert failed: {msg_id}")

        return success

    def run_scan(self, df: pd.DataFrame) -> int:
        """
        Run strategy scan on latest candles.

        Returns number of signals generated.
        """
        if df is None or df.empty:
            return 0

        now = datetime.now(self.utc_tz)
        if not self.is_trading_hours(now):
            return 0

        # Generate signals (no look-ahead)
        signals = self.generate_signals(df)

        generated_count = 0
        for candle_idx, direction, confidence in signals:
            # Get candle data
            candle = df.iloc[candle_idx]
            entry_price = candle['close']
            atr = candle['atr']
            candle_time = candle.name

            # Check if can entry
            can_enter, reason = self.can_entry(now)
            if not can_enter:
                log.info(f"  ⊘ Signal rejected: {reason}")
                continue

            # Calculate stops and targets (higher multipliers for vol)
            sl, tp = self.calculate_stops_and_targets(entry_price, direction, atr)

            # Record to ledger
            trade_id = self.record_signal_to_ledger(
                direction, entry_price, sl, tp, confidence, atr, candle_time
            )

            # Send Telegram alert
            self.send_signal_alert(direction, entry_price, sl, tp, candle_time, atr, trade_id)

            # Update state
            self.state.last_entry_time = now
            self.state.trades_today += 1
            generated_count += 1

        return generated_count

    def run_once(self, data_fetcher) -> bool:
        """Run strategy once (single scan)."""
        try:
            # Fetch data
            now = datetime.now(self.utc_tz)
            end_date = now
            start_date = now - timedelta(days=7)

            df = data_fetcher.fetch_candles(
                start_date=start_date,
                end_date=end_date,
                interval="15m"
            )

            if df is None or df.empty:
                log.warning("No data available")
                return False

            # Run scan
            signal_count = self.run_scan(df)
            log.info(f"✓ Scan complete: {signal_count} signals")
            return True

        except Exception as e:
            log.error(f"✗ Run scan error: {e}", exc_info=True)
            return False

if __name__ == "__main__":
    print("\n" + "=" * 80)
    print("BANKNIFTY-SCALPER-V1 (Paper Trading Research)")
    print("=" * 80)
    print(f"Bot ID: {CONFIG['bot_id']}")
    print(f"Mode: PAPER (no real broker orders)")
    print(f"Data: Delayed Yahoo Finance (~15-30min latency)")
    print(f"Strategy: Opening Range Breakout + EMA Confirmation (High Volatility Profile)")
    print("=" * 80 + "\n")

    print("Use: from banknifty_scalper_v1 import BankNiftyScalperV1")
    print("Example:")
    print("  scalper = BankNiftyScalperV1()")
    print("  scalper.run_once(data_fetcher)")
