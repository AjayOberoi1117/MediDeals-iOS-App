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

# Start rpyc server that listens for connections from native Linux Python.
# Must be called as a class method — NOT MetaTrader5(host, port).run_server()
# because the constructor tries to CONNECT (client), not listen (server).
MetaTrader5.run_server(host="localhost", port=18812)
