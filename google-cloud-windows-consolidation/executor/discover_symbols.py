"""
Symbol Discovery Tool for Vantage MT5 Account
Discovers actual broker symbol names and specifications
Maps canonical symbols (BTCUSD, XAUUSD, EURUSD, GBPUSD) to Vantage symbols
"""

import os
import sys
import json
from pathlib import Path

try:
    import MetaTrader5 as mt5
except ImportError:
    print("ERROR: MetaTrader5 package not installed. Run: pip install MetaTrader5")
    sys.exit(1)

from dotenv import load_dotenv
from mt5_connection import initialize_mt5

load_dotenv()

# MT5 Credentials
MT5_LOGIN = int(os.getenv("MT5_LOGIN", "0"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")
MT5_SERVER = os.getenv("MT5_SERVER", "")

# Canonical symbols we're looking for
CANONICAL_SYMBOLS = {
    "BTC": ["BTC/USD", "BTCUSD", "BTC.m", "XBTM"],
    "GOLD": ["XAU/USD", "XAUUSD", "GC=F", "GOLD.m"],
    "EURUSD": ["EUR/USD", "EURUSD"],
    "GBPUSD": ["GBP/USD", "GBPUSD"],
}


def discover_symbols():
    """Discover available symbols on the broker."""
    print("=" * 70)
    print("SYMBOL DISCOVERY — VANTAGE MT5")
    print("=" * 70)
    print()

    # Initialize MT5
    print(f"Connecting to MT5: login={MT5_LOGIN}, server={MT5_SERVER}")
    initialized, terminal_path = initialize_mt5(
        mt5, login=MT5_LOGIN, password=MT5_PASSWORD, server=MT5_SERVER
    )
    print(f"Terminal: {terminal_path or 'NOT FOUND'}")
    if not initialized:
        print(f"❌ MT5 initialization failed: {mt5.last_error()}")
        sys.exit(1)

    print("✅ Connected to MT5")

    # Verify account type
    acc = mt5.account_info()
    print(f"Account: {acc.name} | Type: {'DEMO' if acc.trade_mode == 0 else 'REAL'}")

    if acc.trade_mode != 0:
        print("⚠️  WARNING: This is a REAL account. Using live money symbols.")
        print("Proceed with caution!")

    print()
    print("Discovering symbols...")
    print()

    # Get all available symbols
    all_symbols = mt5.symbols_get()
    if not all_symbols:
        print("❌ No symbols found on this server")
        mt5.shutdown()
        sys.exit(1)

    print(f"Total symbols on server: {len(all_symbols)}")
    print()

    # Search for each canonical symbol
    symbol_mapping = {}

    for category, possible_names in CANONICAL_SYMBOLS.items():
        print(f"🔍 Searching for {category}...")
        found = False

        for possible_name in possible_names:
            # Try exact match
            symbol_info = mt5.symbol_info(possible_name)
            if symbol_info is not None:
                print(f"  ✅ Found: {possible_name}")
                print(f"     | Digits: {symbol_info.digits}")
                print(f"     | Point: {symbol_info.point}")
                print(f"     | Volume min: {symbol_info.volume_min}")
                print(f"     | Volume max: {symbol_info.volume_max}")
                print(f"     | Volume step: {symbol_info.volume_step}")
                print(f"     | Trade mode: {symbol_info.trade_mode}")
                print(f"     | Ask: {symbol_info.ask}, Bid: {symbol_info.bid}")

                symbol_mapping[category] = {
                    "canonical": category,
                    "vantage_symbol": possible_name,
                    "digits": symbol_info.digits,
                    "point": symbol_info.point,
                    "volume_min": symbol_info.volume_min,
                    "volume_max": symbol_info.volume_max,
                    "volume_step": symbol_info.volume_step,
                    "trade_mode": symbol_info.trade_mode,
                    "ask": float(symbol_info.ask),
                    "bid": float(symbol_info.bid),
                }
                found = True
                break

        if not found:
            print(f"  ❌ NOT FOUND: Tried {possible_names}")
            print(f"     Available crypto/metal symbols on server:")

            # Show available alternatives
            alternatives = [
                s.name
                for s in all_symbols
                if any(keyword in s.name.upper() for keyword in [
                    "BTC", "XAU", "GOLD" if category == "GOLD" else "",
                    "EUR" if category == "EURUSD" else "",
                    "GBP" if category == "GBPUSD" else ""
                ])
            ]
            if alternatives:
                for alt in alternatives[:5]:
                    print(f"       - {alt}")
            else:
                print(f"       (no alternatives found)")

        print()

    # Save mapping to file
    mapping_file = Path("symbol_mapping.json")
    print("=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"Symbols found: {len(symbol_mapping)}/{len(CANONICAL_SYMBOLS)}")

    if symbol_mapping:
        print()
        print("Symbol Mapping:")
        for cat, info in symbol_mapping.items():
            print(f"  {cat:10} → {info['vantage_symbol']}")

        # Save to file
        with open(mapping_file, "w") as f:
            json.dump(symbol_mapping, f, indent=2)

        print()
        print(f"✅ Mapping saved to: {mapping_file}")
        print()
        print("Next step: Update your executors with these symbol names")

    else:
        print()
        print("❌ No canonical symbols found!")
        print()
        print("Troubleshooting:")
        print("1. Verify your Vantage account has access to these instruments")
        print("2. Check broker's symbol naming (may differ from canonical names)")
        print("3. Ensure MetaTrader5 terminal shows the symbols")
        print("4. Some brokers require activation/subscription for crypto/metals")

    mt5.shutdown()
    print()
    print("✅ Discovery complete")


if __name__ == "__main__":
    discover_symbols()
