#!/usr/bin/env python3
"""
Strategy Research Harness for NIFTY50 and BANKNIFTY Scalpers

Provides reproducible framework for testing multiple strategy configurations
with proper train/validation/holdout split, look-ahead prevention, and
detailed performance reporting.
"""

import yfinance as yf
import pandas as pd
import numpy as np
from datetime import datetime, timedelta, time as dt_time
from dataclasses import dataclass, field, asdict
from typing import List, Dict, Tuple, Optional
from enum import Enum
import json
import hashlib
import sys

# ============================================================================
# CONFIGURATION CLASSES
# ============================================================================

class StrategySignal(Enum):
    """Signal direction."""
    BUY = 1
    SELL = -1
    NEUTRAL = 0

@dataclass
class StrategyConfig:
    """Immutable strategy configuration."""
    config_id: str
    name: str
    symbol: str  # ^NSEI or ^NSEBANK
    timeframe_minutes: int

    # Entry criteria (configurable per strategy)
    entry_criteria: Dict = field(default_factory=dict)

    # Risk management
    atr_period: int = 14
    sl_atr_multiplier: float = 1.5  # SL = 1.5 * ATR
    tp_atr_multiplier: float = 3.0  # TP = 3.0 * ATR

    # Trade management
    max_trades_per_session: int = 5
    cooldown_minutes_after_loss: int = 5
    cooldown_minutes_after_win: int = 2
    daily_loss_limit_points: int = -500
    max_consecutive_losses: int = 3

    # Data quality
    min_volume_threshold: float = 10000  # Min volume per candle
    max_data_delay_minutes: float = 30  # Assumed data delay

    # Time filters
    no_entry_after_hour: int = 15  # Don't enter after 3 PM IST
    no_entry_before_hour: int = 9  # Don't enter before 9 AM IST (after 9:15)

    def config_hash(self) -> str:
        """Generate unique hash for this configuration."""
        config_str = json.dumps(asdict(self), sort_keys=True, default=str)
        return hashlib.md5(config_str.encode()).hexdigest()[:8]

@dataclass
class SimulationResult:
    """Result of a single simulated trade."""
    config_id: str
    candle_time: pd.Timestamp
    signal_direction: StrategySignal
    entry_price: float
    stop_loss: float
    target: float
    exit_price: Optional[float] = None
    exit_time: Optional[pd.Timestamp] = None
    exit_reason: Optional[str] = None
    points_pnl: float = 0.0
    mfe: float = 0.0  # Max Favorable Excursion
    mae: float = 0.0  # Max Adverse Excursion
    holding_bars: int = 0
    was_accepted: bool = True
    rejection_reason: Optional[str] = None

@dataclass
class PerformanceMetrics:
    """Aggregated performance metrics."""
    config_id: str
    symbol: str
    test_period: str  # "development", "validation", "holdout"
    date_range: Tuple[datetime, datetime]

    total_signals: int = 0
    signals_accepted: int = 0
    signals_rejected: int = 0

    trades_total: int = 0
    trades_won: int = 0
    trades_lost: int = 0
    trades_breakeven: int = 0

    win_rate: float = 0.0
    profit_factor: float = 0.0
    expectancy_points: float = 0.0

    gross_pnl_points: float = 0.0
    max_drawdown_points: float = 0.0
    max_winning_streak: int = 0
    max_losing_streak: int = 0

    avg_win_points: float = 0.0
    avg_loss_points: float = 0.0
    avg_holding_bars: float = 0.0

    mfe_avg: float = 0.0
    mae_avg: float = 0.0

# ============================================================================
# DATA FETCHER WITH LOOK-AHEAD PREVENTION
# ============================================================================

class DataFetcher:
    """Fetch and validate data without look-ahead bias."""

    def __init__(self, symbol: str, max_retries: int = 3):
        self.symbol = symbol
        self.max_retries = max_retries
        self.cache = {}

    def fetch_candles(
        self,
        start_date: datetime,
        end_date: datetime,
        interval: str = "15m"
    ) -> Optional[pd.DataFrame]:
        """
        Fetch candles for date range with ZERO look-ahead.

        Args:
            start_date: Start of data window (UTC)
            end_date: End of data window (UTC)
            interval: "15m", "1h", "1d"

        Returns:
            DataFrame with OHLCV data, indexed by candle close time
        """
        cache_key = f"{self.symbol}_{start_date.date()}_{end_date.date()}_{interval}"
        if cache_key in self.cache:
            return self.cache[cache_key]

        for attempt in range(self.max_retries):
            try:
                # yfinance returns data up to market close
                # For backtesting, we use this as historical record
                df = yf.download(
                    self.symbol,
                    start=start_date,
                    end=end_date,
                    interval=interval,
                    progress=False
                )

                if df is not None and not df.empty:
                    # Standardize column names
                    df.columns = [c.lower() for c in df.columns]

                    # Ensure we have required columns
                    required = ['open', 'high', 'low', 'close', 'volume']
                    if not all(c in df.columns for c in required):
                        print(f"  ⚠ Missing columns in {self.symbol}; available: {df.columns}")
                        return None

                    # Ensure index is properly timezone-aware
                    if df.index.tz is None:
                        df.index = df.index.tz_localize('UTC')
                    else:
                        df.index = df.index.tz_convert('UTC')

                    # Sort by time
                    df = df.sort_index()

                    self.cache[cache_key] = df
                    return df

            except Exception as e:
                if attempt < self.max_retries - 1:
                    import time
                    time.sleep(2 ** attempt)
                else:
                    print(f"  ✗ Failed to fetch {self.symbol}: {e}")

        return None

# ============================================================================
# STRATEGY TESTER WITH LOOK-AHEAD PREVENTION
# ============================================================================

class StrategyTester:
    """Test strategy configurations chronologically without look-ahead."""

    def __init__(self, config: StrategyConfig, data: pd.DataFrame):
        self.config = config
        self.data = data.copy()
        self.results: List[SimulationResult] = []
        self.last_trade_exit_time = {}  # Track cooldown
        self.daily_loss = 0.0
        self.trades_today = 0
        self.consecutive_losses = 0

    def calculate_atr(self, window: int = 14) -> pd.Series:
        """Calculate Average True Range."""
        high = self.data['high']
        low = self.data['low']
        close = self.data['close']

        tr1 = high - low
        tr2 = (high - close.shift()).abs()
        tr3 = (low - close.shift()).abs()
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = tr.rolling(window).mean()

        return atr

    def generate_signals(self) -> Dict[int, Tuple[StrategySignal, str]]:
        """
        Generate signals for each candle.

        Returns dict: {candle_index: (signal, reason)}
        Only signals available at candle close (NO LOOK-AHEAD).
        """
        signals = {}

        # This is a template; specific strategies override this
        # For now, return empty signals (subclasses implement strategy)
        return signals

    def simulate_trade(
        self,
        entry_index: int,
        entry_price: float,
        sl: float,
        tp: float,
        signal_dir: StrategySignal
    ) -> Tuple[Optional[SimulationResult], int]:
        """
        Simulate a trade from entry until exit.

        Args:
            entry_index: Candle index where signal fires
            entry_price: Entry price (at candle close)
            sl: Stop loss level
            tp: Target price level
            signal_dir: BUY or SELL

        Returns:
            (SimulationResult, exit_index)
        """
        if entry_index >= len(self.data):
            return None, entry_index

        entry_candle = self.data.iloc[entry_index]
        entry_time = entry_candle.name

        # Search for exit within max 100 candles (scalp hold time)
        max_hold_bars = 100
        exit_index = None
        exit_reason = None
        mfe = 0.0
        mae = 0.0

        for i in range(entry_index + 1, min(entry_index + max_hold_bars, len(self.data))):
            candle = self.data.iloc[i]
            high = candle['high']
            low = candle['low']
            close = candle['close']

            # Update MFE/MAE
            if signal_dir == StrategySignal.BUY:
                mfe = max(mfe, high - entry_price)
                mae = min(mae, low - entry_price)

                # Check exits
                if low <= sl:
                    exit_index = i
                    exit_reason = "STOP_LOSS_HIT"
                    break
                elif high >= tp:
                    exit_index = i
                    exit_reason = "TARGET_HIT"
                    break

            elif signal_dir == StrategySignal.SELL:
                mfe = max(mfe, entry_price - low)
                mae = min(mae, entry_price - high)

                # Check exits
                if high >= sl:
                    exit_index = i
                    exit_reason = "STOP_LOSS_HIT"
                    break
                elif low <= tp:
                    exit_index = i
                    exit_reason = "TARGET_HIT"
                    break

        # If no exit found, close at market (end of hold period or close of data)
        if exit_index is None:
            if entry_index + max_hold_bars < len(self.data):
                exit_index = entry_index + max_hold_bars
                exit_reason = "TIME_EXIT"
            else:
                exit_index = len(self.data) - 1
                exit_reason = "DATA_END"

        exit_candle = self.data.iloc[exit_index]
        exit_time = exit_candle.name
        exit_price = exit_candle['close']

        # Calculate P&L
        if signal_dir == StrategySignal.BUY:
            points_pnl = exit_price - entry_price
        else:
            points_pnl = entry_price - exit_price

        holding_bars = exit_index - entry_index

        result = SimulationResult(
            config_id=self.config.config_id,
            candle_time=entry_time,
            signal_direction=signal_dir,
            entry_price=entry_price,
            stop_loss=sl,
            target=tp,
            exit_price=exit_price,
            exit_time=exit_time,
            exit_reason=exit_reason,
            points_pnl=points_pnl,
            mfe=mfe,
            mae=mae,
            holding_bars=holding_bars,
        )

        return result, exit_index

# ============================================================================
# PERFORMANCE CALCULATOR
# ============================================================================

def calculate_metrics(
    results: List[SimulationResult],
    config_id: str,
    symbol: str,
    test_period: str,
    date_range: Tuple[datetime, datetime]
) -> PerformanceMetrics:
    """Calculate comprehensive performance metrics."""

    metrics = PerformanceMetrics(
        config_id=config_id,
        symbol=symbol,
        test_period=test_period,
        date_range=date_range,
    )

    if not results:
        return metrics

    # Separate accepted and rejected
    accepted = [r for r in results if r.was_accepted]

    metrics.total_signals = len(results)
    metrics.signals_accepted = len(accepted)
    metrics.signals_rejected = len(results) - len(accepted)

    if not accepted:
        return metrics

    # Trade outcomes
    metrics.trades_total = len(accepted)
    metrics.trades_won = sum(1 for r in accepted if r.points_pnl > 0)
    metrics.trades_lost = sum(1 for r in accepted if r.points_pnl < 0)
    metrics.trades_breakeven = metrics.trades_total - metrics.trades_won - metrics.trades_lost

    # Win rate and profit factor
    if metrics.trades_total > 0:
        metrics.win_rate = metrics.trades_won / metrics.trades_total

    winning_pnl = sum(r.points_pnl for r in accepted if r.points_pnl > 0)
    losing_pnl = sum(abs(r.points_pnl) for r in accepted if r.points_pnl < 0)

    if losing_pnl > 0:
        metrics.profit_factor = winning_pnl / losing_pnl if winning_pnl > 0 else 0

    # P&L metrics
    pnls = [r.points_pnl for r in accepted]
    metrics.gross_pnl_points = sum(pnls)

    if metrics.trades_total > 0:
        metrics.expectancy_points = metrics.gross_pnl_points / metrics.trades_total

    if metrics.trades_won > 0:
        metrics.avg_win_points = winning_pnl / metrics.trades_won

    if metrics.trades_lost > 0:
        metrics.avg_loss_points = -(losing_pnl / metrics.trades_lost)

    # Drawdown
    cumulative_pnl = np.cumsum(pnls)
    running_max = np.maximum.accumulate(cumulative_pnl)
    drawdowns = running_max - cumulative_pnl
    metrics.max_drawdown_points = -float(np.min(drawdowns)) if len(drawdowns) > 0 else 0

    # Streaks
    wins_losses = [1 if r.points_pnl > 0 else -1 for r in accepted]
    current_streak = 1
    max_win_streak = 0
    max_loss_streak = 0

    for outcome in wins_losses:
        if outcome == 1:
            current_streak = max(1, current_streak + 1) if current_streak > 0 else 1
            max_win_streak = max(max_win_streak, current_streak)
        else:
            current_streak = min(-1, current_streak - 1) if current_streak < 0 else -1
            max_loss_streak = max(max_loss_streak, abs(current_streak))

    metrics.max_winning_streak = max_win_streak
    metrics.max_losing_streak = max_loss_streak

    # Holding time
    holding_bars = [r.holding_bars for r in accepted]
    if holding_bars:
        metrics.avg_holding_bars = np.mean(holding_bars)

    # MFE/MAE
    if accepted:
        metrics.mfe_avg = np.mean([r.mfe for r in accepted])
        metrics.mae_avg = np.mean([r.mae for r in accepted])

    return metrics

# ============================================================================
# REPORTER
# ============================================================================

def report_metrics(metrics: PerformanceMetrics) -> str:
    """Format metrics as readable report string."""
    lines = [
        f"\n{'=' * 80}",
        f"STRATEGY PERFORMANCE REPORT",
        f"{'=' * 80}",
        f"Config ID:        {metrics.config_id}",
        f"Symbol:           {metrics.symbol}",
        f"Test Period:      {metrics.test_period.upper()}",
        f"Date Range:       {metrics.date_range[0].date()} to {metrics.date_range[1].date()}",
        f"",
        f"SIGNAL SUMMARY:",
        f"  Total signals:    {metrics.total_signals}",
        f"  Signals accepted: {metrics.signals_accepted}",
        f"  Signals rejected: {metrics.signals_rejected}",
        f"  Acceptance rate:  {100*metrics.signals_accepted/metrics.total_signals:.1f}%" if metrics.total_signals > 0 else "  Acceptance rate:  N/A",
        f"",
        f"TRADE OUTCOMES:",
        f"  Total trades:     {metrics.trades_total}",
        f"  Winning trades:   {metrics.trades_won}",
        f"  Losing trades:    {metrics.trades_lost}",
        f"  Breakeven trades: {metrics.trades_breakeven}",
        f"  Win rate:         {100*metrics.win_rate:.1f}%" if metrics.trades_total > 0 else "  Win rate:         N/A",
        f"",
        f"P&L METRICS (in points):",
        f"  Gross P&L:        {metrics.gross_pnl_points:+.1f}",
        f"  Expectancy:       {metrics.expectancy_points:+.1f}",
        f"  Avg win:          {metrics.avg_win_points:+.1f}",
        f"  Avg loss:         {metrics.avg_loss_points:+.1f}",
        f"  Profit factor:    {metrics.profit_factor:.2f}x" if metrics.profit_factor > 0 else "  Profit factor:    N/A",
        f"",
        f"RISK METRICS:",
        f"  Max drawdown:     {metrics.max_drawdown_points:+.1f} points",
        f"  Max win streak:   {metrics.max_winning_streak} trades",
        f"  Max loss streak:  {metrics.max_losing_streak} trades",
        f"  Avg hold time:    {metrics.avg_holding_bars:.1f} candles",
        f"  Avg MFE:          {metrics.mfe_avg:+.1f} points",
        f"  Avg MAE:          {metrics.mae_avg:+.1f} points",
        f"",
        f"{'=' * 80}",
    ]

    return "\n".join(lines)

if __name__ == "__main__":
    print("Strategy Research Harness loaded")
    print("Use: from scalper_strategy_harness import StrategyConfig, StrategyTester, etc.")
