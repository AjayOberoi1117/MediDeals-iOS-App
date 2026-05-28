"""
MT5 Wine Bridge Server
======================
Run this script INSIDE Wine using Windows Python so it can talk to MT5 terminal.

Usage (in Terminal on macOS):
    wine python wine_server.py

This starts a local socket server on port 18812 that the native macOS bot.py
connects to via mt5linux. MT5 terminal must be open and logged in first.

Requirements inside Wine Python:
    wine pip install MetaTrader5 mt5linux
"""

from mt5linux import MetaTrader5

print("Starting MT5 Wine bridge server on localhost:18812 ...")
print("Keep this terminal open while bot.py is running.")
print("Press Ctrl+C to stop.\n")

# MetaTrader5Server listens for connections from native Python (bot.py)
# and proxies all calls to the real MT5 terminal running under Wine.
MetaTrader5(host="localhost", port=18812).run_server()
