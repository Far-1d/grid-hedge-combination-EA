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
input lot_inc_mtd    grid_lot_mtd      = true;              // Grid Lot Size Increase Method 
input bool           enable_modify_tp  = true;              // Enable Close Remaining Positions ?
input int            ret_percent       = 40;                // Retrace Percent for all TPs
input int            max_entry_ecc     = 2;                 // Maximum Entry Price Freedom in points

input group "EA Config";
input int            Magic             = 101;
//input start_methods  ea_sm             = trade_anyway;      // How to Start the EA
input double         lot_size          = 0.1;               // Initial Lot Size
input int            max_spread        = 25;                // Maximum Spread of Symbol


//--- globals
double start_price;                                         // price of chart at the start of EA
string positions_data[][5];                                 // stores every positions data (position_number, price, symbol, lotsize, is_open)
bool initiated = false;
double old_lot_value_buy  = lot_size;
double old_lot_value_sell = lot_size;
double last_pos_price;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   if (TimeCurrent() > StringToTime("2024-5-17"))
   {
      Print("free version time ended. contact support.");
      return (INIT_FAILED);
   }

   start_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);        // because bid is the price shown to user
   
   trade.SetExpertMagicNumber(Magic);
   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
}
  
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
   if (! initiated)
   {
         //start_positions();
         initiated = true;
   }
   
   if (enable_grid)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double n    = (bid - start_price)/(grid_step*10*_Point);
      
      if (MathAbs((int)n - NormalizeDouble(n,2)) < _Point*2){
         open_new_grid_positions();
      }
   }

   
   hedge();
   
}


//+------------------------------------------------------------------+ 
//| TradeTransaction function                                        | 
//+------------------------------------------------------------------+ 
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
   
   ENUM_TRADE_TRANSACTION_TYPE type = (ENUM_TRADE_TRANSACTION_TYPE)trans.type; 

   if (type == TRADE_TRANSACTION_DEAL_ADD){
      int index = check_position_data("ticket", ( string )trans.position);
      
      if (index == -1)
      {
         string pos_type = "";
         if (trans.deal_type == DEAL_TYPE_BUY)
            pos_type = "buy";
         else if (trans.deal_type == DEAL_TYPE_SELL)
            pos_type = "sell";
         
         store_position_data(( string )trans.position, pos_type);
      }
      else
      {  
         positions_data[index][4] = "deactive";
      }
      
      modify_grid_tp();
   }
}



//+------------------------------------------------------------------+


/*
//+------------------------------------------------------------------+
//| initial positions when ea starts                                 |
//+------------------------------------------------------------------+
bool start_positions(){
   if (ea_sm == trade_anyway || PositionsTotal() <= 0)
   {
      double 
         buy_tp  = SymbolInfoDouble(_Symbol, SYMBOL_BID) + grid_step*10*_Point,
         sell_tp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - grid_step*10*_Point;
         
      trade.Buy(fix_lot_size_digits(lot_size), _Symbol, 0, 0, buy_tp);
      trade.Sell(fix_lot_size_digits(lot_size), _Symbol, 0, 0, sell_tp);
   }
   
   if (ea_sm == no_prev_positions && PositionsTotal() != 1)
   {
      //--- if there are more than 1 position, stop EA
      return false;
   }
 
   return true;
}*/


//+------------------------------------------------------------------+
//| opens a new single/set of position(s) upon each tp in Grid       |
//+------------------------------------------------------------------+
void open_new_grid_positions(){
   if (enable_grid)
   {
      double 
         current        = SymbolInfoDouble(_Symbol, SYMBOL_BID),
         buy_tp         = SymbolInfoDouble(_Symbol, SYMBOL_BID) + grid_tp_step*10*_Point,
         sell_tp        = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - grid_tp_step*10*_Point,
        
         new_lot_buy    = grid_lot_mtd == aggressive ? 
               fix_lot_size_digits(old_lot_value_buy * (1 + (grid_multiplier/100))) :
               fix_lot_size_digits(old_lot_value_buy + (lot_size*grid_multiplier/100)) ,
         
         new_lot_sell   = grid_lot_mtd == aggressive ? 
               fix_lot_size_digits(old_lot_value_sell *(1 + (grid_multiplier/100))) :
               fix_lot_size_digits(old_lot_value_sell + (lot_size*grid_multiplier/100)),
               
         buy_lot        = current < last_pos_price? last_pos_price!=0? new_lot_buy : lot_size : lot_size,
         sell_lot       = current > last_pos_price? last_pos_price!=0? new_lot_sell: lot_size : lot_size; 
   
   
      // check no active BUY position is on that price level   
      if (check_position_data("buy-price", ( string )SymbolInfoDouble(_Symbol, SYMBOL_ASK)) == -1)
      {
         trade.Buy(buy_lot, _Symbol, 0, 0, buy_tp);
         old_lot_value_buy = buy_lot;
         last_pos_price = current;
         Print("----------------- old lot buy = ", buy_lot);
      }
      
      // check no active SELL position is on that price level 
      if (check_position_data("sell-price", ( string )SymbolInfoDouble(_Symbol, SYMBOL_BID)) == -1)
      {
         trade.Sell(sell_lot, _Symbol, 0, 0, sell_tp);
         old_lot_value_sell = sell_lot;
         last_pos_price = current;
         Print("----------------- old lot sell = ", sell_lot);
      }
   }
}


//+------------------------------------------------------------------+
//| stores position data in an array                                 |
//+------------------------------------------------------------------+
void store_position_data(string pos_number, string pos_type){
   
   int size = ArraySize(positions_data)/5;
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
   positions_data[size][4] = "active";
}


//+------------------------------------------------------------------+
//| check stores position data for matches                           |
//+------------------------------------------------------------------+
int check_position_data(string field, string search_value){
   int size = ArraySize(positions_data)/5;
   
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
         positions_data[i][4] == "active" &&
         positions_data[i][2] == _Symbol &&
         positions_data[i][3] == "buy")
         {
            return i;
         }
         
      if (field == "sell-price" && 
         // have 25 points spread compensation
         MathAbs((double)positions_data[i][1] - (double)search_value) <= _Point*max_spread &&
         positions_data[i][4] == "active" &&
         positions_data[i][2] == _Symbol &&
         positions_data[i][3] == "sell")
         {
            return i;
         }
   }
   
   return -1;
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
   
   if (enable_grid && enable_modify_tp){
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
//| all hedge related funtions                                       |
//+------------------------------------------------------------------+
void hedge(){

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