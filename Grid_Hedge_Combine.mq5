//+------------------------------------------------------------------+
//|                                           Grid_Hedge_Combine.mq5 |
//|                                      Copyright 2024, Farid Zarie |
//|                                        https://github.com/Far-1d |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Farid Zarie"
#property link      "https://github.com/Far-1d"
#property version   "1.10"
#property description "Grid and Hedge EA"
#property description "created at 12/5/2024"
#property description "made with ❤ & ️🎮"

//--- imports
#include <Trade/Trade.mqh>
CTrade      trade;                        // object of CTrade class
#include <Trade\SymbolInfo.mqh>
CSymbolInfo sInfo;


//--- enums
enum start_methods{
   trade_anyway,              // open a buy & sell position anyway
   no_prev_positions,         // only open positions if no other position exists
};

enum lot_inc_mtd{
   aggressive,                // Aggresive
   constant                   // Constant
};


//--- inputs
input group "Grid Config";
input bool           enable_grid       = true;              // Enable Grid ?
input int            grid_step         = 10;                // Grid Step in pip
input double         grid_tp_step      = 10;                // Grid TP Step in pip 
input double         grid_multiplier   = 10;                // Grid Lot Size Increase %
input lot_inc_mtd    grid_lot_mtd      = aggressive;        // Grid Lot Size Increase Method 
input bool           enable_modify_tp  = true;              // Enable Close Remaining Positions ?
input int            ret_percent       = 40;                // Retrace Percent for all TPs
input int            max_entry_ecc     = 2;                 // Maximum Entry Price Freedom in points

input group "Hedge Config";
input bool           enable_hedge      = true;              // Enable Hedge ?
input int            hedge_step        = 10;                // Hedge Step in pip
input double         hedge_multiplier  = 20;                // Hedge Lot Size Increase %
input lot_inc_mtd    hedge_lot_mtd     = aggressive;        // Hedge Lot Size Increase Method 
input double         hedge_profit      = 5;                 // Hedge Profit in $
input bool           hedge_open_pos    = true;              // Open an Initial Trade on Start ?
input bool           enable_hedge_sl   = true;              // Enable SL in Hedge ?

input group "EA Config";
input int            Magic             = 101;
//input start_methods  ea_sm             = trade_anyway;      // How to Start the EA
input double         lot_size          = 0.1;               // Initial Lot Size
input int            max_spread        = 25;                // Maximum Spread of Symbol


//--- globals
double start_price;                                         // price of chart at the start of EA
string positions_data[][6];                                 // stores every grid position data (ticket, price, symbol, type, lot)
string hedge_data[][6];                                     // stores every hedge position data (price, symbol, type, lot)
bool initiated = false;
double old_lot_grid_value_buy  = lot_size;
double old_lot_grid_value_sell = lot_size;
double old_lot_hedge_value_buy  = lot_size;
double old_lot_hedge_value_sell = lot_size;
double last_sell_price;
double last_buy_price;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   sInfo.Name(_Symbol);
   
   if (TimeCurrent() > StringToTime("2024-5-22"))
   {
      Print("free version time ended. contact support.");
      return (INIT_FAILED);
   }

   start_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);        // because bid is the price shown to user
   //EventSetTimer(60*60*2);
   trade.SetExpertMagicNumber(Magic);
   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
}

//void OnTimer(void)
//  {
//   ArrayPrint(hedge_data);
//  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
   double 
         bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID),
         ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   //--- GRID
      
   if (enable_grid)
   {
      double 
         n_b  = (bid - start_price)/(grid_step*10*_Point),
         n_a  = (ask - start_price)/(grid_step*10*_Point);
      
      if (MathAbs((int)n_b - NormalizeDouble(n_b,2)) < _Point*max_entry_ecc ||
          MathAbs(1+((int)n_b) - NormalizeDouble(n_b,2)) < _Point*max_entry_ecc ||
          MathAbs(1-((int)n_b) - NormalizeDouble(n_b,2)) < _Point*max_entry_ecc){
         grid_sell();
      }
      if (MathAbs((int)n_a - NormalizeDouble(n_a,2)) < _Point*max_entry_ecc ||
          MathAbs(1+((int)n_a) - NormalizeDouble(n_a,2)) < _Point*max_entry_ecc ||
          MathAbs(1-((int)n_a) - NormalizeDouble(n_a,2)) < _Point*max_entry_ecc){
         grid_buy();
      }
   }
   
   
   //--- HEDGE
   
   if (! initiated)
   {
         start_hedge_positions();
         initiated = true;
   }

   if (enable_hedge)
   {
      int size = ArraySize(positions_data)/6;
      
      for(int i=0; i<size; i++){
         if (positions_data[i][3] == "sell")
         {
            double n_a  = MathAbs(ask - (double)positions_data[i][1]-(hedge_step*10*_Point));
            
            if (check_hedge_data("buy-price", (string)ask) == -1  &&
               n_a < _Point*max_entry_ecc)
            {
               hedge_buy(i);
            }
         }
         else if (positions_data[i][3] == "buy")
         {
            double n_b = MathAbs(bid + (hedge_step*10*_Point) - (double)positions_data[i][1]);
            
            if (check_hedge_data("sell-price", (string)bid) == -1  &&
               n_b < _Point*max_entry_ecc)
            {
               hedge_sell(i);
            }
         }
      }
   }
   
   
}


//+------------------------------------------------------------------+ 
//| TradeTransaction function                                        | 
//+------------------------------------------------------------------+ 
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
   
   ENUM_TRADE_TRANSACTION_TYPE type = (ENUM_TRADE_TRANSACTION_TYPE)trans.type; 
   if (type == TRADE_TRANSACTION_DEAL_ADD ){
   
      int h_index = check_hedge_data("ticket", ( string )trans.position);
      int g_index = check_grid_data("ticket", ( string )trans.position);
      
      if (h_index != -1 && g_index == -1)
      {
         if (TimeCurrent() - StringToTime(hedge_data[h_index][5]) > PeriodSeconds(PERIOD_M1))
            ArrayRemove(hedge_data, h_index, 1);
      }
      else if (h_index == -1 && g_index != -1)
      {
         if (TimeCurrent() - StringToTime(positions_data[g_index][5]) > PeriodSeconds(PERIOD_M1))
            ArrayRemove(positions_data, g_index, 1);
      }
      
      modify_grid_tp();
   }
   
}


//+------------------------------------------------------------------+


//-------------------------       Grid Functions       -------------------------\\


//+------------------------------------------------------------------+
//| opens a new buy position upon each tp in Grid                    |
//+------------------------------------------------------------------+
void grid_buy(){
   double 
      current        = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
      buy_tp         = SymbolInfoDouble(_Symbol, SYMBOL_BID) + grid_tp_step*10*_Point,
     
      new_lot_buy    = grid_lot_mtd == aggressive ? 
            fix_lot_size_digits(old_lot_grid_value_buy * (1 + (grid_multiplier/100))) :
            fix_lot_size_digits(old_lot_grid_value_buy + (lot_size*grid_multiplier/100)) ,

      buy_lot        = current < last_buy_price? last_buy_price!=0? new_lot_buy : lot_size : lot_size;

   // check no active BUY position is on that price level   
   if (check_grid_data("buy-price", ( string )SymbolInfoDouble(_Symbol, SYMBOL_ASK)) == -1)
   {
      Print(">>>>>>>>    buy lot size ", buy_lot, "     old is ", old_lot_grid_value_buy);
      trade.Buy(buy_lot, _Symbol, 0, 0, buy_tp, "grid");
      store_grid_data((string)trade.ResultOrder(), "buy", buy_lot);
      old_lot_grid_value_buy = buy_lot;
      last_buy_price = current;
   }
}


//+------------------------------------------------------------------+
//| opens a new sell position upon each tp in Grid                   |
//+------------------------------------------------------------------+
void grid_sell(){
   double 
      current        = SymbolInfoDouble(_Symbol, SYMBOL_BID),
      sell_tp        = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - grid_tp_step*10*_Point,
      
      new_lot_sell   = grid_lot_mtd == aggressive ? 
            fix_lot_size_digits(old_lot_grid_value_sell *(1 + (grid_multiplier/100))) :
            fix_lot_size_digits(old_lot_grid_value_sell + (lot_size*grid_multiplier/100)),
      sell_lot       = current > last_sell_price? last_sell_price!=0? new_lot_sell: lot_size : lot_size; 
   
   // check no active SELL position is on that price level 
   if (check_grid_data("sell-price", ( string )SymbolInfoDouble(_Symbol, SYMBOL_BID)) == -1)
   {
      Print(">>>>>>>>      sell lot size ", sell_lot, "     old is ", old_lot_grid_value_sell);
      trade.Sell(sell_lot, _Symbol, 0, 0, sell_tp, "grid");
      store_grid_data((string)trade.ResultOrder(), "sell", sell_lot);
      old_lot_grid_value_sell = sell_lot;
      last_sell_price = current;
   }
}


//+------------------------------------------------------------------+
//| remenant positions' tp modifier                                  |
//+------------------------------------------------------------------+
void modify_grid_tp(){
   int buy_counter  = 0;
   int sell_counter = 0;
   
   double 
      highest_buy    = 0, 
      lowest_buy     = 100000000000000,
      highest_sell   = 0,
      lowest_sell    = 100000000000000;
   
   if (enable_grid && enable_modify_tp && !enable_hedge){
      if (PositionsTotal() > 2)
      {
         for (int i=PositionsTotal()-1; i>=0; i--){
            ulong tikt = PositionGetTicket(i);
            if (PositionSelectByTicket(tikt))
            {
               if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               {
                  buy_counter ++;
                  double   
                     tp    = PositionGetDouble(POSITION_TP),
                     entry = PositionGetDouble(POSITION_PRICE_OPEN);
                  if (entry > highest_buy) highest_buy = entry;
                  if (entry < lowest_buy ) lowest_buy  = entry;
               }
               if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               {
                  sell_counter ++;
                  double
                     tp    = PositionGetDouble(POSITION_TP),
                     entry = PositionGetDouble(POSITION_PRICE_OPEN);
                  if (entry > highest_sell) highest_sell = entry;
                  if (entry < lowest_sell ) lowest_sell  = entry;
               }
            }
         }
         
         //--- if more that 1 buy position is out there, modify tps
         if (buy_counter >  1){
            double modified_buy_tp = lowest_buy + (highest_buy - lowest_buy)*ret_percent/100;
            for (int i=PositionsTotal()-1; i>=0; i--){
               ulong tikt = PositionGetTicket(i);
               if (PositionSelectByTicket(tikt))
               {
                  if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                  {
                     trade.PositionModify(tikt, 0, modified_buy_tp);
                  }
               }
            }
         }
         
         //--- if more that 1 sell position is out there, modify tps
         if (sell_counter > 1){
            double modified_sell_tp = highest_sell - (highest_sell - lowest_sell)*ret_percent/100;
            for (int i=PositionsTotal()-1; i>=0; i--){
               ulong tikt = PositionGetTicket(i);
               if (PositionSelectByTicket(tikt))
               {
                  if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                  {
                     trade.PositionModify(tikt, 0, modified_sell_tp);
                  }
               }
            }
         }
         
      }
   }
}


//+------------------------------------------------------------------+
//| stores grid position data in an array                            |
//+------------------------------------------------------------------+
void store_grid_data(string pos_number, string pos_type, double lot){
   int size = ArraySize(positions_data)/6;
   ArrayResize(positions_data, size+1);
   //--- calculate price level
   double price;
   if (pos_type == "buy")
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   positions_data[size][0] = pos_number;
   positions_data[size][1] = ( string )price;
   positions_data[size][2] = _Symbol;
   positions_data[size][3] = pos_type;
   positions_data[size][4] = (string)lot;
   positions_data[size][5] = TimeToString(TimeCurrent());
}


//-------------------------      Hedge Functions      -------------------------\\


//+------------------------------------------------------------------+
//| initial positions for hedge start                                |
//+------------------------------------------------------------------+
void start_hedge_positions(){
   if (enable_hedge && hedge_open_pos && !enable_grid)
   {
      if (PositionsTotal() <= 0)
      {
         double 
            buy_tp  = SymbolInfoDouble(_Symbol, SYMBOL_BID) + grid_step*10*_Point,
            sell_tp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - grid_step*10*_Point;
         
         trade.Buy(fix_lot_size_digits(lot_size), _Symbol, 0, 0, buy_tp, "hedge");
      }
      else
      {
         
      }
   }
}



//+------------------------------------------------------------------+
//| all hedge related funtions                                       |
//+------------------------------------------------------------------+
void hedge_buy(int index){
   double 
      main_trade_price  = (double)positions_data[index][1],
      current           = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
      sell_tp           = main_trade_price - grid_tp_step*10*_Point,
      buy_sl            = sell_tp,
      buy_lot           = (double)positions_data[index][4]*(1+(hedge_multiplier/100));
      
   double buy_tp = calculate_profit("sell", main_trade_price, (double)positions_data[index][4], current, buy_lot);
   double sell_sl = buy_tp;
   
   if (!enable_hedge_sl) 
   {
      buy_sl =0; 
      sell_tp=0;
   }
   //--- open hegde position
   trade.Buy(fix_lot_size_digits(buy_lot), _Symbol, 0, buy_sl, buy_tp, "hedge");
   store_hedge_data((string)trade.ResultOrder(), "buy", buy_lot);

   //--- modify main position with a new sl
   if (trade.PositionModify((long)positions_data[index][0], sell_sl, sell_tp))
   {
      Print("---------------------   old sell position modified. ");
   }
}

//+------------------------------------------------------------------+
//| all hedge related funtions                                       |
//+------------------------------------------------------------------+
void hedge_sell(int index){
   double 
      main_trade_price  = (double)positions_data[index][1],
      current           = SymbolInfoDouble(_Symbol, SYMBOL_BID),
      buy_tp            = main_trade_price + grid_tp_step*10*_Point,
      sell_sl           = buy_tp,
      sell_lot          = (double)positions_data[index][4]*(1+(hedge_multiplier/100));

   double sell_tp = calculate_profit("buy", main_trade_price, (double)positions_data[index][4], current, sell_lot);
   double buy_sl = sell_tp;

   if (!enable_hedge_sl) 
   {
      buy_sl =0; 
      sell_tp=0;
      //trade.BuyStop(sell_lot*(1+(hedge_multiplier/100), )
   }
   
   //--- open hegde position
   trade.Sell(fix_lot_size_digits(sell_lot), _Symbol, 0, sell_sl, sell_tp, "hedge");
   store_hedge_data((string)trade.ResultOrder(), "sell", sell_lot);

   
   //--- modify main position with a sl
   if (trade.PositionModify((ulong)positions_data[index][0], buy_sl, buy_tp))
   {
      Print("---------------------   old buy position modified. ");
   }
}


//+------------------------------------------------------------------+
//| stores hedge position data in an array                           |
//+------------------------------------------------------------------+
void store_hedge_data(string pos_number, string pos_type, double lot){
   int size = ArraySize(hedge_data)/6;
   ArrayResize(hedge_data, size+1);

   //--- calculate price level
   double price;
   if (pos_type == "buy")
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   hedge_data[size][0] = pos_number;
   hedge_data[size][1] = ( string )price;
   hedge_data[size][2] = _Symbol;
   hedge_data[size][3] = pos_type;
   hedge_data[size][4] = (string)lot;
   hedge_data[size][5] = TimeToString(TimeCurrent());
}


//-------------------------     Auxiliary Functions     -------------------------\\


//+------------------------------------------------------------------+
//| check stores position data for matches                           |
//+------------------------------------------------------------------+
int check_grid_data(string field, string search_value){
      int size = ArraySize(positions_data)/6;
      
      for (int i=0; i<size; i++){
         if (field == "ticket" && 
            positions_data[i][0] == search_value &&
            positions_data[i][2] == _Symbol)
            {
               return i;
            }
   
         if (field == "buy-price" && 
            // have 25 points spread compensation
            MathAbs((double)positions_data[i][1] - (double)search_value) <= _Point*max_spread &&
            positions_data[i][2] == _Symbol &&
            positions_data[i][3] == "buy")
            {
               return i;
            }
            
         if (field == "sell-price" && 
            // have 25 points spread compensation
            MathAbs((double)positions_data[i][1] - (double)search_value) <= _Point*max_spread &&
            positions_data[i][2] == _Symbol &&
            positions_data[i][3] == "sell")
            {
               return i;
            }
      }

   return -1;
}

//+------------------------------------------------------------------+
//| check stores position data for matches                           |
//+------------------------------------------------------------------+
int check_hedge_data(string field, string search_value){
      int size = ArraySize(hedge_data)/6;
   
      for (int i=0; i<size; i++){
         if (field == "ticket" && 
            hedge_data[i][0] == search_value &&
            hedge_data[i][2] == _Symbol)
            {
               return i;
            }
         if (field == "buy-price" && 
            // have "max_spread" points spread compensation
            MathAbs((double)hedge_data[i][1] - (double)search_value) <= _Point*max_spread &&
            hedge_data[i][2] == _Symbol &&
            hedge_data[i][3] == "buy")
            {
               return i;
            }
            
         if (field == "sell-price" && 
            // have "max_spread" points spread compensation
            MathAbs((double)hedge_data[i][1] - (double)search_value) <= _Point*max_spread &&
            hedge_data[i][2] == _Symbol &&
            hedge_data[i][3] == "sell")
            {
               return i;
            }
      }
   return -1;
}


//+------------------------------------------------------------------+
//| calculate the price which equals the input hedge profit          |
//+------------------------------------------------------------------+
double calculate_profit (string type, double main_price, double main_lot, double current_price, double current_lot){
   double tp;
   
   if (type == "sell")
   {
      tp = ( ( (hedge_profit/sInfo.ContractSize()) + 
               ((main_lot+current_lot)*SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)*2*_Point) +
               (current_price*current_lot) -
               (main_price*main_lot) ) / 
                                         (current_lot-main_lot) );
      Print("res1 = ", tp);
      return tp;
   }
   else
   {
      tp = ( ( (hedge_profit/sInfo.ContractSize()) + 
               ((main_lot+current_lot)*SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)*2*_Point) -
               (current_price*current_lot) +
               (main_price*main_lot) ) / 
                                         (main_lot-current_lot) );
      Print("res2 = ", tp);
      return tp;
   }
}


//+------------------------------------------------------------------+
//| fix lot size digit to symbol favor                               |
//+------------------------------------------------------------------+
double fix_lot_size_digits(double lot){
   double 
      step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
      min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
      max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   int digit = ( int )MathAbs(log10(step));
   
   double result = NormalizeDouble(lot, digit);
   return MathMin(max, MathMax(min, result));
}