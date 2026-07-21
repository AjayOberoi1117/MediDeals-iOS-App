"""
One-off backtest tool — NOT part of the live bot pipeline.

Replays nifty_scalper.py's exact strategy (Supertrend(7, 2.0) flip on
15-min bars, 0.4% SL / 0.8% TP, intraday MIS squared off end-of-day)
against ~60 days of history for NIFTY (^NSEI) and BANKNIFTY (^NSEBANK).
Compares taking signals as-is vs. inverted (BUY<->SELL) to see whether
flipping actually has a statistical edge, and whether one index is the
real bleeder (like USDJPY turned out to be for the forex scalper).

Run on a machine with Yahoo Finance access:
    python3 telegram_bot/backtest_nifty.py
"""
import time
import pandas as pd
import yfinance as yf

ST_PERIOD, ST_MULT = 7, 2.0
SL_PCT, TP_PCT = 0.4, 0.8          # percent
R_TP = TP_PCT / SL_PCT             # +R multiple when TP hits (= 2.0)

INSTRUMENTS = {"NIFTY": "^NSEI", "BANKNIFTY": "^NSEBANK"}


def calculate_supertrend(df, period, multiplier):
    """Faithful copy of nifty_scalper.calculate_supertrend."""
    hl2 = (df["high"] + df["low"]) / 2
    prev_close = df["close"].shift(1)
    tr = pd.concat([df["high"]-df["low"], (df["high"]-prev_close).abs(),
                    (df["low"]-prev_close).abs()], axis=1).max(axis=1)
    atr = tr.ewm(span=period, adjust=False).mean()
    upper_band = hl2 + multiplier * atr
    lower_band = hl2 - multiplier * atr
    supertrend = pd.Series(index=df.index, dtype=float)
    direction  = pd.Series(index=df.index, dtype=int)
    for i in range(1, len(df)):
        if not (upper_band.iloc[i] < upper_band.iloc[i-1] or df["close"].iloc[i-1] > upper_band.iloc[i-1]):
            upper_band.iloc[i] = upper_band.iloc[i-1]
        if not (lower_band.iloc[i] > lower_band.iloc[i-1] or df["close"].iloc[i-1] < lower_band.iloc[i-1]):
            lower_band.iloc[i] = lower_band.iloc[i-1]
        if i == 1:
            direction.iloc[i] = 1
        elif supertrend.iloc[i-1] == upper_band.iloc[i-1]:
            direction.iloc[i] = -1 if df["close"].iloc[i] > upper_band.iloc[i] else 1
        else:
            direction.iloc[i] = 1 if df["close"].iloc[i] < lower_band.iloc[i] else -1
        supertrend.iloc[i] = lower_band.iloc[i] if direction.iloc[i] == 1 else upper_band.iloc[i]
    df = df.copy()
    df["st_direction"] = direction
    return df


def fetch(ticker):
    for attempt in range(3):
        try:
            df = yf.download(ticker, period="60d", interval="15m", progress=False, auto_adjust=True)
            if df is not None and not df.empty:
                if isinstance(df.columns, pd.MultiIndex):
                    df.columns = [c[0] for c in df.columns]
                df = df.rename(columns=str.lower)[["open", "high", "low", "close"]]
                # to IST, keep only regular market hours
                idx = df.index
                df.index = idx.tz_convert("Asia/Kolkata") if idx.tz else idx.tz_localize("UTC").tz_convert("Asia/Kolkata")
                df = df.between_time("09:15", "15:30").dropna()
                df["day"] = df.index.date
                return df
        except Exception as exc:
            print(f"  attempt {attempt+1} failed: {exc}")
        time.sleep(3)
    return None


def simulate(df, entry_idx, direction, entry):
    """Walk forward within the SAME trading day; square off at EOD. Returns R-multiple."""
    if direction == "BUY":
        sl = entry * (1 - SL_PCT/100); tp = entry * (1 + TP_PCT/100)
    else:
        sl = entry * (1 + SL_PCT/100); tp = entry * (1 - TP_PCT/100)
    entry_day = df["day"].iloc[entry_idx]
    last_close = entry
    for j in range(entry_idx, len(df)):
        if df["day"].iloc[j] != entry_day:
            break                       # next day — MIS already squared off
        hi = float(df["high"].iloc[j]); lo = float(df["low"].iloc[j])
        last_close = float(df["close"].iloc[j])
        if direction == "BUY":
            if lo <= sl: return -1.0     # SL first (conservative if both)
            if hi >= tp: return R_TP
        else:
            if hi >= sl: return -1.0
            if lo <= tp: return R_TP
    # squared off at end of day at last_close
    ret = (last_close - entry) / entry * 100
    if direction == "SELL":
        ret = -ret
    return ret / SL_PCT                  # actual return in R units


COOLDOWN_SECS = 1800   # matches live nifty_scalper.py COOLDOWN


def backtest(name, ticker):
    df = fetch(ticker)
    if df is None or len(df) < 30:
        print(f"{name}: insufficient data"); return []
    df = calculate_supertrend(df, ST_PERIOD, ST_MULT)
    trades = []
    last_signal_ts = None
    for i in range(2, len(df) - 1):
        st_now, st_prev = int(df["st_direction"].iloc[i]), int(df["st_direction"].iloc[i-1])
        if st_now == st_prev:
            continue                     # no flip, no signal
        bar_ts = df.index[i]
        if last_signal_ts is not None and (bar_ts - last_signal_ts).total_seconds() < COOLDOWN_SECS:
            continue                     # live bot would skip — still in cooldown
        direction = "BUY" if st_now == 1 else "SELL"
        # enter on next bar's open, same day only
        if df["day"].iloc[i+1] != df["day"].iloc[i]:
            continue                     # flip on last bar of day — skip (can't enter)
        entry = float(df["open"].iloc[i+1])
        pnl_r = simulate(df, i+1, direction, entry)
        trades.append({"name": name, "direction": direction, "pnl_r": pnl_r})
        last_signal_ts = bar_ts
    return trades


def report(trades, label):
    n = len(trades)
    if n == 0:
        print(f"{label:22s}: no trades"); return
    wins = sum(1 for t in trades if t["pnl_r"] > 0)
    losses = sum(1 for t in trades if t["pnl_r"] < 0)
    total_r = sum(t["pnl_r"] for t in trades)
    wr = wins / (wins + losses) * 100 if (wins + losses) else 0
    print(f"{label:22s}: n={n:3d}  win_rate={wr:5.1f}%  total_R={total_r:+7.1f}  avg_R={total_r/n:+.3f}")


def main():
    all_trades = []
    for name, ticker in INSTRUMENTS.items():
        print(f"Backtesting {name} ({ticker})...")
        all_trades.extend(backtest(name, ticker))

    print(f"\nTotal signals: {len(all_trades)}\n")
    print("=== AS-IS (current live logic) ===")
    report(all_trades, "Normal (both)")
    for name in INSTRUMENTS:
        report([t for t in all_trades if t["name"] == name], f"  {name}")

    # Inverted must be re-simulated, not just sign-flipped — when BUY becomes
    # SELL the 0.4% SL and 0.8% TP swap sides, so which one hits first changes.
    # Same cooldown-gated flip cadence as the live bot; only direction flips.
    inv_trades = []
    for name, ticker in INSTRUMENTS.items():
        df = fetch(ticker)
        if df is None or len(df) < 30:
            continue
        df = calculate_supertrend(df, ST_PERIOD, ST_MULT)
        last_signal_ts = None
        for i in range(2, len(df) - 1):
            st_now, st_prev = int(df["st_direction"].iloc[i]), int(df["st_direction"].iloc[i-1])
            if st_now == st_prev:
                continue
            bar_ts = df.index[i]
            if last_signal_ts is not None and (bar_ts - last_signal_ts).total_seconds() < COOLDOWN_SECS:
                continue
            direction = "BUY" if st_now == 1 else "SELL"
            inv_dir = "SELL" if direction == "BUY" else "BUY"
            if df["day"].iloc[i+1] != df["day"].iloc[i]:
                continue
            entry = float(df["open"].iloc[i+1])
            pnl_r = simulate(df, i+1, inv_dir, entry)
            inv_trades.append({"name": name, "direction": inv_dir, "pnl_r": pnl_r})
            last_signal_ts = bar_ts

    print("\n=== INVERTED (flip every BUY<->SELL) ===")
    report(inv_trades, "Inverted (both)")
    for name in INSTRUMENTS:
        report([t for t in inv_trades if t["name"] == name], f"  {name}")


if __name__ == "__main__":
    main()
