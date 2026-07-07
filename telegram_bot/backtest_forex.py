"""
One-off backtest tool — NOT part of the live bot pipeline.

Replays forex_scalper.py's exact strategy logic (EMA9/21 crossover + RSI +
ADX filter + 1H trend filter, ATR-based 1.5x SL / 3x TP) against ~60 days
of 15-min history for EURUSD, GBPUSD, USDJPY. Compares taking signals
as-is vs. inverted (BUY<->SELL) to see which has a real statistical edge.

Run: python3 telegram_bot/backtest_forex.py
"""
import time
import pandas as pd
import yfinance as yf

FAST_EMA, SLOW_EMA = 9, 21
RSI_PERIOD = 14
RSI_BUY_MAX, RSI_SELL_MIN = 60, 40
ATR_PERIOD = 14
ATR_SL_MULT, ATR_TP_MULT = 1.5, 3.0
ADX_PERIOD, ADX_MIN = 14, 20
_atr_min = {"EURUSD": 0.00100, "GBPUSD": 0.00120, "USDJPY": 0.12}

SYMBOLS = {"EURUSD": "EURUSD=X", "GBPUSD": "GBPUSD=X", "USDJPY": "USDJPY=X"}

def calc_rsi(close, period):
    delta = close.diff()
    ag = delta.clip(lower=0).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    al = (-delta.clip(upper=0)).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    return 100 - 100 / (1 + ag / al)

def calc_atr(high, low, close, period):
    pc = close.shift(1)
    tr = pd.concat([high-low, (high-pc).abs(), (low-pc).abs()], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()

def calc_adx(high, low, close, period):
    up_move = high.diff()
    down_move = -low.diff()
    plus_dm = up_move.where((up_move > down_move) & (up_move > 0), 0.0)
    minus_dm = down_move.where((down_move > up_move) & (down_move > 0), 0.0)
    pc = close.shift(1)
    tr = pd.concat([high-low, (high-pc).abs(), (low-pc).abs()], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    plus_di = 100 * (plus_dm.ewm(alpha=1/period, min_periods=period, adjust=False).mean() / atr)
    minus_di = 100 * (minus_dm.ewm(alpha=1/period, min_periods=period, adjust=False).mean() / atr)
    dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di)
    return dx.ewm(alpha=1/period, min_periods=period, adjust=False).mean()

def fetch(ticker, period, interval):
    for attempt in range(3):
        try:
            df = yf.download(ticker, period=period, interval=interval, progress=False, auto_adjust=True)
            if df is not None and not df.empty:
                if isinstance(df.columns, pd.MultiIndex):
                    df.columns = [c[0] for c in df.columns]
                return df
        except Exception as exc:
            print(f"  attempt {attempt+1} failed: {exc}")
        time.sleep(3)
    return None

def simulate_trade(df, entry_idx, direction, entry, sl, tp, max_bars=96):
    """Walk forward bar by bar until SL or TP is hit (or max_bars elapses)."""
    for j in range(entry_idx + 1, min(entry_idx + 1 + max_bars, len(df))):
        hi = float(df["High"].iloc[j]); lo = float(df["Low"].iloc[j])
        if direction == "BUY":
            hit_sl = lo <= sl
            hit_tp = hi >= tp
        else:
            hit_sl = hi >= sl
            hit_tp = lo <= tp
        if hit_sl:
            return "SL"   # conservative: assume SL if both hit same bar
        if hit_tp:
            return "TP"
    return "TIMEOUT"

def run_backtest(name, ticker):
    df15 = fetch(ticker, "60d", "15m")
    df1h = fetch(ticker, "180d", "1h")
    if df15 is None or df1h is None or len(df15) < SLOW_EMA + 60:
        print(f"{name}: insufficient data"); return []

    close = df15["Close"].squeeze(); high = df15["High"].squeeze(); low = df15["Low"].squeeze()
    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi = calc_rsi(close, RSI_PERIOD)
    atr = calc_atr(high, low, close, ATR_PERIOD)
    adx = calc_adx(high, low, close, ADX_PERIOD)

    close1h = df1h["Close"].squeeze()
    ema50_1h = close1h.ewm(span=50, adjust=False).mean()
    trend1h = (close1h > ema50_1h).astype(int) * 2 - 1  # +1 / -1
    if trend1h.index.tz is not None: trend1h.index = trend1h.index.tz_localize(None)
    df15_idx = df15.index.tz_localize(None) if df15.index.tz else df15.index

    trades = []
    for i in range(SLOW_EMA + 5, len(df15) - 1):
        bull = (fast_ema.iloc[i-1] > slow_ema.iloc[i-1]) and (fast_ema.iloc[i-2] <= slow_ema.iloc[i-2]) and (fast_ema.iloc[i] > slow_ema.iloc[i])
        bear = (fast_ema.iloc[i-1] < slow_ema.iloc[i-1]) and (fast_ema.iloc[i-2] >= slow_ema.iloc[i-2]) and (fast_ema.iloc[i] < slow_ema.iloc[i])
        if not (bull or bear):
            continue
        adx_val = float(adx.iloc[i])
        if adx_val < ADX_MIN:
            continue
        rsi_val = float(rsi.iloc[i])
        price = float(close.iloc[i])
        atr_val = max(float(atr.iloc[i]), _atr_min.get(name, 0))

        ts = df15_idx[i]
        prior = trend1h[trend1h.index <= ts]
        trend = int(prior.iloc[-1]) if len(prior) else 0

        direction = None
        if bull and rsi_val < RSI_BUY_MAX and trend != -1:
            direction = "BUY"
        elif bear and rsi_val > RSI_SELL_MIN and trend != 1:
            direction = "SELL"
        if direction is None:
            continue

        if direction == "BUY":
            sl = price - ATR_SL_MULT * atr_val; tp = price + ATR_TP_MULT * atr_val
        else:
            sl = price + ATR_SL_MULT * atr_val; tp = price - ATR_TP_MULT * atr_val

        outcome = simulate_trade(df15, i, direction, price, sl, tp)
        pnl_r = {"TP": 2.0, "SL": -1.0, "TIMEOUT": 0.0}[outcome]
        trades.append({"name": name, "i": i, "time": ts, "direction": direction, "outcome": outcome, "pnl_r": pnl_r})
    return trades, df15

def report(trades, label):
    n = len(trades)
    if n == 0:
        print(f"{label}: no trades"); return
    wins = sum(1 for t in trades if t["pnl_r"] > 0)
    losses = sum(1 for t in trades if t["pnl_r"] < 0)
    timeouts = sum(1 for t in trades if t["pnl_r"] == 0)
    total_r = sum(t["pnl_r"] for t in trades)
    win_rate = wins / (wins + losses) * 100 if (wins + losses) else 0
    print(f"{label}: n={n}  wins={wins}  losses={losses}  timeouts={timeouts}  "
          f"win_rate={win_rate:.1f}%  total_R={total_r:+.1f}  avg_R={total_r/n:+.3f}")

def main():
    all_trades = []
    dfs = {}
    for name, ticker in SYMBOLS.items():
        print(f"Backtesting {name} ({ticker})...")
        trades, df15 = run_backtest(name, ticker)
        all_trades.extend(trades)
        dfs[name] = df15

    print(f"\nTotal signals generated: {len(all_trades)}")
    print("\n=== AS-IS (bot's actual signals) ===")
    report(all_trades, "Normal")
    for name in SYMBOLS:
        report([t for t in all_trades if t["name"] == name], f"  {name}")

    inverted_trades = []
    for t in all_trades:
        name = t["name"]; i = t["i"]; df15 = dfs[name]
        close = df15["Close"].squeeze(); high = df15["High"].squeeze(); low = df15["Low"].squeeze()
        atr = calc_atr(high, low, close, ATR_PERIOD)
        price = float(close.iloc[i])
        atr_val = max(float(atr.iloc[i]), _atr_min.get(name, 0))
        inv_dir = "SELL" if t["direction"] == "BUY" else "BUY"
        if inv_dir == "BUY":
            sl = price - ATR_SL_MULT * atr_val; tp = price + ATR_TP_MULT * atr_val
        else:
            sl = price + ATR_SL_MULT * atr_val; tp = price - ATR_TP_MULT * atr_val
        outcome = simulate_trade(df15, i, inv_dir, price, sl, tp)
        pnl_r = {"TP": 2.0, "SL": -1.0, "TIMEOUT": 0.0}[outcome]
        inverted_trades.append({"name": name, "direction": inv_dir, "outcome": outcome, "pnl_r": pnl_r})

    print("\n=== INVERTED (flip every BUY<->SELL) ===")
    report(inverted_trades, "Inverted")
    for name in SYMBOLS:
        report([t for t in inverted_trades if t["name"] == name], f"  {name}")

if __name__ == "__main__":
    main()
