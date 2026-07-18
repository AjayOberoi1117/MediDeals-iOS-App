"""
MT5 Wine Bridge Server
======================
Run this script INSIDE Wine using Windows Python so it can talk to MT5 terminal.

Usage:
    wine python wine_server.py

Starts an rpyc classic server on port 18812. Native Linux Python (trader.py)
connects via mt5linux which calls rpyc.classic.connect("localhost", 18812).

Requirements inside Wine Python:
    wine pip install MetaTrader5 mt5linux rpyc
"""

from rpyc.utils.server import ThreadedServer
import rpyc

print("Starting MT5 Wine bridge server on port 18812 ...")

t = ThreadedServer(
    rpyc.SlaveService,
    hostname="0.0.0.0",
    port=18812,
    protocol_config={"allow_all_attrs": True, "allow_pickle": True},
)

print("Listening on 0.0.0.0:18812 — ready for mt5linux connections.")
t.start()
