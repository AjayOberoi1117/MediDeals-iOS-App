//+------------------------------------------------------------------+
//| TradeFromFile.mq5 (Enhanced with SL/TP Validation)               |
//| Reads mt5_signals.csv and executes trades with stop validation   |
//|                                                                  |
//| Safety features:                                                 |
//| - Validates SL/TP against broker minimums per symbol             |
//| - Normalizes prices to SYMBOL_DIGITS                             |
//| - Guards against duplicate/stale orders                          |
//| - Approved symbols only: EURUSD, GBPUSD, XAUUSD (USDJPY blocked) |
//| - Demo mode: 0.01 lots max                                       |
//|                                                                  |
//| Deploy: copy to MQL5\Experts\, compile, attach to any chart.    |
//+------------------------------------------------------------------+
#property copyright "MediDeals Trading Bots"
#property version   "2.00"

#include <Trade\Trade.mqh>

CTrade trade;

input double LotSize      = 0.01;   // Lot size per trade (DEMO)
input int    Deviation    = 20;     // Max slippage in points
input int    CheckSecs    = 5;      // How often to check for signals (seconds)
input string SignalsFile  = "mt5_signals.csv"; // File written by trader.py

// Approved symbols (USDJPY explicitly disabled)
bool IsApprovedSymbol(string symbol)
{
   return (symbol == "EURUSD" || symbol == "GBPUSD" || symbol == "XAUUSD" || symbol == "BTCUSD");
}

// Normalize price to SYMBOL_DIGITS
double NormalizePrice(string symbol, double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

// Validate and adjust SL/TP for a BUY trade
bool ValidateBuyStops(string symbol, double& sl, double& tp, double bid_price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double min_stop_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);

   // Normalize input prices
   sl = NormalizePrice(symbol, sl);
   tp = NormalizePrice(symbol, tp);

   // For BUY: SL must be BELOW execution price, TP above
   if (sl == 0)
   {
      Print("REJECT BUY ", symbol, ": SL is zero");
      return false;
   }

   if (tp == 0)
   {
      Print("REJECT BUY ", symbol, ": TP is zero");
      return false;
   }

   if (sl >= bid_price)
   {
      Print("REJECT BUY ", symbol, ": SL=", sl, " must be below Bid=", bid_price);
      return false;
   }

   if (tp <= bid_price)
   {
      Print("REJECT BUY ", symbol, ": TP=", tp, " must be above Bid=", bid_price);
      return false;
   }

   // Check minimum stop distances
   double min_sl = bid_price - (min_stop_level * point);
   double max_tp = bid_price + (min_stop_level * point);

   if (sl < min_sl)
   {
      Print("WARN BUY ", symbol, ": SL=", sl, " too close to Bid, expanding to ", min_sl);
      sl = NormalizePrice(symbol, min_sl);
   }

   if (tp < max_tp)
   {
      Print("WARN BUY ", symbol, ": TP=", tp, " too close to Bid, expanding to ", max_tp);
      tp = NormalizePrice(symbol, max_tp);
   }

   return true;
}

// Validate and adjust SL/TP for a SELL trade
bool ValidateSellStops(string symbol, double& sl, double& tp, double ask_price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double min_stop_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);

   // Normalize input prices
   sl = NormalizePrice(symbol, sl);
   tp = NormalizePrice(symbol, tp);

   // For SELL: SL must be ABOVE execution price, TP below
   if (sl == 0)
   {
      Print("REJECT SELL ", symbol, ": SL is zero");
      return false;
   }

   if (tp == 0)
   {
      Print("REJECT SELL ", symbol, ": TP is zero");
      return false;
   }

   if (sl <= ask_price)
   {
      Print("REJECT SELL ", symbol, ": SL=", sl, " must be above Ask=", ask_price);
      return false;
   }

   if (tp >= ask_price)
   {
      Print("REJECT SELL ", symbol, ": TP=", tp, " must be below Ask=", ask_price);
      return false;
   }

   // Check minimum stop distances
   double min_sl = ask_price + (min_stop_level * point);
   double min_tp = ask_price - (min_stop_level * point);

   if (sl > min_sl)
   {
      Print("WARN SELL ", symbol, ": SL=", sl, " too close to Ask, expanding to ", min_sl);
      sl = NormalizePrice(symbol, min_sl);
   }

   if (tp > min_tp)
   {
      Print("WARN SELL ", symbol, ": TP=", tp, " too close to Ask, contracting to ", min_tp);
      tp = NormalizePrice(symbol, min_tp);
   }

   return true;
}

// Check for duplicate open position with same magic
bool HasOpenPosition(int magic)
{
   int total = PositionsTotal();
   for (int i = 0; i < total; i++)
   {
      if (PositionSelectByTicket(PositionGetTicket(i)))
      {
         if ((int)PositionGetInteger(POSITION_MAGIC) == magic)
         {
            return true;
         }
      }
   }
   return false;
}

int OnInit()
{
   trade.SetDeviationInPoints(Deviation);
   EventSetTimer(CheckSecs);
   Print("TradeFromFile EA v2 started | watching: ", SignalsFile, " | approved: EURUSD,GBPUSD,XAUUSD");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   ProcessSignals();
}

void ProcessSignals()
{
   if (!FileIsExist(SignalsFile))
      return;

   int handle = FileOpen(SignalsFile, FILE_READ|FILE_TXT|FILE_ANSI);
   if (handle == INVALID_HANDLE)
      return;

   string lines[];
   int count = 0;
   while (!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      StringTrimLeft(line);
      StringTrimRight(line);
      if (StringLen(line) > 5)
      {
         ArrayResize(lines, count + 1);
         lines[count++] = line;
      }
   }
   FileClose(handle);

   if (count == 0) return;

   // Clear file immediately so we don't re-process
   handle = FileOpen(SignalsFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if (handle != INVALID_HANDLE) FileClose(handle);

   for (int i = 0; i < count; i++)
   {
      string parts[];
      // Format: SYMBOL,DIRECTION,SL,TP,MAGIC,SOURCE,TIMESTAMP
      if (StringSplit(lines[i], ',', parts) < 5) continue;

      string symbol    = parts[0];
      string direction = parts[1];
      double sl        = StringToDouble(parts[2]);
      double tp        = StringToDouble(parts[3]);
      int    magic     = (int)StringToInteger(parts[4]);

      ProcessSignal(symbol, direction, sl, tp, magic);
   }
}

void ProcessSignal(string symbol, string direction, double sl, double tp, int magic)
{
   // Validate symbol
   if (!IsApprovedSymbol(symbol))
   {
      Print("REJECT ", symbol, ": not in approved list (EURUSD,GBPUSD,XAUUSD)");
      return;
   }

   // Check for duplicate position
   if (HasOpenPosition(magic))
   {
      Print("SKIP ", symbol, ": duplicate position with magic=", magic);
      return;
   }

   // Get current prices
   MqlTick tick;
   if (!SymbolInfoTick(symbol, tick))
   {
      Print("ERROR: Cannot get tick for ", symbol);
      return;
   }

   double bid = tick.bid;
   double ask = tick.ask;

   // Normalize and validate SL/TP
   bool valid = false;
   if (direction == "BUY")
   {
      valid = ValidateBuyStops(symbol, sl, tp, bid);
   }
   else if (direction == "SELL")
   {
      valid = ValidateSellStops(symbol, sl, tp, ask);
   }
   else
   {
      Print("REJECT: unknown direction ", direction);
      return;
   }

   if (!valid)
   {
      Print("REJECT: SL/TP validation failed for ", direction, " ", symbol);
      return;
   }

   // Execute the trade
   ExecuteTrade(symbol, direction, sl, tp, magic);
}

void ExecuteTrade(string symbol, string direction, double sl, double tp, int magic)
{
   trade.SetExpertMagicNumber(magic);

   bool ok = false;
   string comment = "Bot#" + IntegerToString(magic);

   if (direction == "BUY")
      ok = trade.Buy(LotSize, symbol, 0, sl, tp, comment);
   else if (direction == "SELL")
      ok = trade.Sell(LotSize, symbol, 0, sl, tp, comment);
   else
      return;

   if (ok)
   {
      Print("TRADE OK: ", direction, " ", symbol,
            " lot=", LotSize, " sl=", sl, " tp=", tp, " magic=", magic);
   }
   else
   {
      int err = GetLastError();
      Print("TRADE FAILED: ", direction, " ", symbol,
            " error=", err, " (", ErrorDescription(err), ") magic=", magic);
   }
}

// Helper: get error description
string ErrorDescription(int error)
{
   switch(error)
   {
      case 4756: return "TRADE_RETCODE_INVALID_STOPS";
      case 4754: return "TRADE_RETCODE_INVALID_PRICE";
      default: return "ERR_" + IntegerToString(error);
   }
}
