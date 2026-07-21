"""
One-off backtest tool — NOT part of the live bot pipeline.

Tests the DIRECTIONAL quality of options_scalper.py's filtered signals.

IMPORTANT LIMITATION: Yahoo Finance has no historical premium data for
NIFTY/BANKNIFTY option contracts, so this CANNOT backtest real option
P&L (the 30% SL / 60% TP premium rules). What it CAN do — and what
actually matters — is measure whether the filtered signal is
directionally right on the UNDERLYING index: after a confirmed
bullish flip (Buy Call) does the index actually go up, and by how
much before it goes against you? If the underlying direction isn't
reliably right, no option strategy on top of it can work.

Replays the exact live filter chain:
    Supertrend(7,2.0) flip  +  ADX(14) >= 20  +  1H EMA50 trend aligned
enters next-bar-open, squares off end-of-day (intraday), and reports
per index:
  - signal count (validates "trades rarely" vs the raw scalper)
  - directional win rate (net favorable at square-off)
  - avg Max-Favorable-Excursion (MFE) and Max-Adverse-Excursion (MAE), %
  - a proxy R using underlying thresholds (0.30% adverse stop, 0.60%
    favorable target) — labelled clearly as a PROXY, not option premium.

Run on a machine with Yahoo Finance access:
    python3 telegram_bot/backtest_options.py
"""
import time
import pandas as pd
import yfinance as yf

ST_PERIOD, ST_MULT = 7, 2.0
ADX_PERIOD, ADX_MIN = 14, 20
TREND_EMA = 50
COOLDOWN_SECS = 1800

# Underlying-move proxy thresholds (NOT option premium — see module docstring).
# Rough stand-in for the option's 30%/60% premium rule via ATM delta ~0.5.
UND_STOP_PCT, UND_TARGET_PCT = 0.30, 0.60

INSTRUMENTS = {"NIFTY": "^NSEI", "BANKNIFTY": "^NSEBANK"}


def calc_adx(high, low, close, period):
    up_move = high.diff(); down_move = -low.diff()
    plus_dm = up_move.where((up_move > down_move) & (up_move > 0), 0.0)
    minus_dm = down_move.where((down_move > up_move) & (down_move > 0), 0.0)
    pc = close.shift(1)
    tr = pd.concat([high-low, (high-pc).abs(), (low-pc).abs()], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    plus_di = 100 * (plus_dm.ewm(alpha=1/period, min_periods=period, adjust=False).mean() / atr)
    minus_di = 100 * (minus_dm.ewm(alpha=1/period, min_periods=period, adjust=False).mean() / atr)
    dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di)
    return dx.ewm(alpha=1/period, min_periods=period, adjust=False).mean()


def calculate_supertrend(df, period, multiplier):
    """Faithful copy of options_scalper.calculate_supertrend."""
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


def fetch_15m(ticker):
    for attempt in range(3):
        try:
            df = yf.download(ticker, period="60d", interval="15m", progress=False, auto_adjust=True)
            if df is not None and not df.empty:
                if isinstance(df.columns, pd.MultiIndex):
                    df.columns = [c[0] for c in df.columns]
                df = df.rename(columns=str.lower)[["open", "high", "low", "close"]]
                idx = df.index
                df.index = idx.tz_convert("Asia/Kolkata") if idx.tz else idx.tz_localize("UTC").tz_convert("Asia/Kolkata")
                df = df.between_time("09:15", "15:30").dropna()
                df["day"] = df.index.date
                return df
        except Exception as exc:
            print(f"  15m attempt {attempt+1} failed: {exc}")
        time.sleep(3)
    return None


def fetch_1h_trend(ticker):
    """Returns a Series of +1/-1 trend indexed by 1H bar timestamp (IST)."""
    for attempt in range(3):
        try:
            df = yf.download(ticker, period="60d", interval="1h", progress=False, auto_adjust=True)
            if df is not None and not df.empty:
                if isinstance(df.columns, pd.MultiIndex):
                    df.columns = [c[0] for c in df.columns]
                df.columns = [str(c).lower() for c in df.columns]
                close = df["close"].squeeze()
                if isinstance(close, pd.DataFrame):
                    close = close.iloc[:, 0]
                ema = close.ewm(span=TREND_EMA, adjust=False).mean()
                trend = (close > ema).astype(int) * 2 - 1
                if trend.index.tz is not None:
                    trend.index = trend.index.tz_convert("Asia/Kolkata")
                return trend
        except Exception as exc:
            print(f"  1h attempt {attempt+1} failed: {exc}")
        time.sleep(3)
    return None


def trend_at(trend_series, ts):
    """As-of lookup: most recent 1H trend value at or before ts."""
    prior = trend_series[trend_series.index <= ts]
    return int(prior.iloc[-1]) if len(prior) else 0


def excursions(df, entry_idx, direction, entry):
    """Intraday MFE/MAE in %, favorable-signed for the trade direction, plus a
    proxy outcome using underlying stop/target thresholds. Same-day only."""
    entry_day = df["day"].iloc[entry_idx]
    mfe = mae = 0.0
    proxy = None
    for j in range(entry_idx, len(df)):
        if df["day"].iloc[j] != entry_day:
            break
        hi = float(df["high"].iloc[j]); lo = float(df["low"].iloc[j])
        if direction == "BUY":
            fav = (hi - entry) / entry * 100
            adv = (lo - entry) / entry * 100
        else:
            fav = (entry - lo) / entry * 100
            adv = (entry - hi) / entry * 100
        mfe = max(mfe, fav)
        mae = min(mae, adv)
        if proxy is None:
            if mae <= -UND_STOP_PCT and mfe >= UND_TARGET_PCT:
                proxy = "STOP"     # conservative: both breached in a bar -> stop
            elif mae <= -UND_STOP_PCT:
                proxy = "STOP"
            elif mfe >= UND_TARGET_PCT:
                proxy = "TARGET"
    if proxy is None:
        # squared off EOD: win if net favorable at the day's last close
        eod_close = entry
        for j in range(entry_idx, len(df)):
            if df["day"].iloc[j] != entry_day:
                break
            eod_close = float(df["close"].iloc[j])
        net = (eod_close - entry) / entry * 100
        if direction == "SELL":
            net = -net
        proxy = "EOD_WIN" if net > 0 else "EOD_LOSS"
    return mfe, mae, proxy


def run(name, ticker):
    df = fetch_15m(ticker)
    trend = fetch_1h_trend(ticker)
    if df is None or trend is None or len(df) < 30:
        print(f"{name}: insufficient data"); return []
    df = calculate_supertrend(df, ST_PERIOD, ST_MULT)
    high = df["high"]; low = df["low"]; close = df["close"]
    adx = calc_adx(high, low, close, ADX_PERIOD)

    trades = []
    last_ts = None
    for i in range(2, len(df) - 1):
        st_now, st_prev = int(df["st_direction"].iloc[i]), int(df["st_direction"].iloc[i-1])
        if st_now == st_prev:
            continue
        bar_ts = df.index[i]
        if last_ts is not None and (bar_ts - last_ts).total_seconds() < COOLDOWN_SECS:
            continue
        if float(adx.iloc[i]) < ADX_MIN:
            continue                                  # ADX strength gate
        tr = trend_at(trend, bar_ts)
        if st_now == 1 and tr != 1:
            continue                                  # bull flip needs bull 1H trend
        if st_now == -1 and tr != -1:
            continue                                  # bear flip needs bear 1H trend
        if df["day"].iloc[i+1] != df["day"].iloc[i]:
            continue                                  # can't enter next day
        direction = "BUY" if st_now == 1 else "SELL"  # BUY=Call bet, SELL=Put bet
        entry = float(df["open"].iloc[i+1])
        mfe, mae, proxy = excursions(df, i+1, direction, entry)
        trades.append({"name": name, "direction": direction,
                       "mfe": mfe, "mae": mae, "proxy": proxy})
        last_ts = bar_ts
    return trades


def report(trades, label):
    n = len(trades)
    if n == 0:
        print(f"{label:14s}: no signals"); return
    tgt = sum(1 for t in trades if t["proxy"] == "TARGET")
    stp = sum(1 for t in trades if t["proxy"] == "STOP")
    eodw = sum(1 for t in trades if t["proxy"] == "EOD_WIN")
    eodl = sum(1 for t in trades if t["proxy"] == "EOD_LOSS")
    wins = tgt + eodw
    wr = wins / n * 100
    avg_mfe = sum(t["mfe"] for t in trades) / n
    avg_mae = sum(t["mae"] for t in trades) / n
    print(f"{label:14s}: n={n:3d}  dir_win={wr:5.1f}%  "
          f"[target={tgt} stop={stp} eod+={eodw} eod-={eodl}]  "
          f"avgMFE={avg_mfe:+.2f}%  avgMAE={avg_mae:+.2f}%")


def main():
    all_trades = []
    for name, ticker in INSTRUMENTS.items():
        print(f"Backtesting {name} ({ticker})...")
        all_trades.extend(run(name, ticker))

    print(f"\nTotal filtered signals over ~60 days: {len(all_trades)}")
    print("(directional test on the UNDERLYING — NOT option premium P&L; see header)\n")
    report(all_trades, "BOTH")
    for name in INSTRUMENTS:
        report([t for t in all_trades if t["name"] == name], f"  {name}")
    print("\ndir_win = target-hit or closed-day-favorable.  Proxy stop/target = "
          f"{UND_STOP_PCT}% / {UND_TARGET_PCT}% underlying move (stand-in for the "
          "option 30/60 premium rule).")


if __name__ == "__main__":
    main()
