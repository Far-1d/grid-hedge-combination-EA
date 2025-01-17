//+------------------------------------------------------------------+
//|                                           Grid_Hedge_Combine.mq5 |
//|                                      Copyright 2024, Farid Zarie |
//|                                        https://github.com/Far-1d |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Farid Zarie"
#property link      "https://github.com/Far-1d"
#property version   "2.0"
#property description "Grid and Hedge EA"
#property description "created at 12/5/2024"
#property description "made with ❤ & ️🎮"
#property description ""
#property description ""
#property description ""
#property description "update: expert can be run on multiple chart simultaneously"

#define BOX_NAME "info_box"
#define TEXT_NAME "info_text"

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
enum profit_mtds{
  Profit,                     // Profit only
  commission,                 // Profit + Commission
  swap                        // Profit + Commission + Swap 
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
input double         hedge_profit      = 5;                 // Hedge Profit in $
input profit_mtds    profit_mtd        = swap;              // Profit Calculation Method
input bool           repeat_hedges     = true;              // Open Repetitive Hedges on the Same Level  
input bool           hedge_open_pos    = true;              // Open an Initial Trade on Start ?
input bool           enable_hedge_sl   = true;              // Enable SL in Hedge ?

input group "EA Config";
input int            Magic             = 101;
input int            max_trades        = 10;                // Maximum Open Trades on a Price Level
input double         lot_size          = 0.01;              // Initial Lot Size
input int            max_spread        = 25;                // Maximum Spread of Symbol
input color          box_clr           = clrDarkSlateGray;  // Box Color
input color          text_clr          = clrWhite;          // Text Color
input int            box_time          = 10;                // Box Visible Time (per candle)


//--- globals
double start_price;                                // price of chart at the start of EA
string positions_data [][6];                       // stores every grid position data (ticket, price, symbol, type, lot)
string hedge_data [][6];                           // stores every hedge position data (price, symbol, type, lot)
string oscillating_data [][30][7];                 // store data of grid and hedges which are oscillating 

bool initiated = false;
double old_lot_grid_value_buy  = lot_size;
double old_lot_grid_value_sell = lot_size;
double old_lot_hedge_value_buy  = lot_size;
double old_lot_hedge_value_sell = lot_size;
double last_sell_price=1000000000000;
double last_buy_price=0;
datetime clear_time;                // time to clear info box from chart

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   sInfo.Name(_Symbol);

   start_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);        // because bid is the price shown to user

   trade.SetExpertMagicNumber(Magic);
   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
   clear_objects();
}


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
         n_b  = fabs(NormalizeDouble((bid - start_price)/(grid_step*10*_Point), 3)),
         n_a  = fabs(NormalizeDouble((ask - start_price)/(grid_step*10*_Point), 3));
      
      if (fabs((int)n_b - n_b) < 0.002 ||
          fabs(1-((int)n_a) - n_a) < 0.002 )
      {
         grid_sell();
      }
      if (fabs((int)n_a - n_a) < 0.002 ||
          fabs(1-((int)n_a) - n_a) < 0.002)
      {
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
            double n_a = MathAbs(ask - (double)positions_data[i][1]-(hedge_step*10*_Point));
            
            if (check_hedge_data("buy-price", (string)ask) == -1  &&
               n_a < _Point*max_entry_ecc)
            {
               if (repeat_hedges)
               {
                  hedge_buy(i);
               }
               else
               {
                  if (enable_hedge_sl)
                  {
                     hedge_buy(i);
                  }
                  else
                  {                  
                     if (! stop_orders_exists(ask))
                     {
                        hedge_buy(i);
                     }
                  }
               }
            }
         }
         else if (positions_data[i][3] == "buy")
         {
            double n_b = MathAbs(bid + (hedge_step*10*_Point) - (double)positions_data[i][1]);
            
            if (check_hedge_data("sell-price", (string)bid) == -1  &&
               n_b < _Point*max_entry_ecc)
            {
               if (repeat_hedges)
               {
                  hedge_sell(i);
               }
               else
               {
                  if (enable_hedge_sl)
                  {
                     hedge_sell(i);
                  }
                  else
                  {
                     if (! stop_orders_exists(bid))
                     {
                        hedge_sell(i);
                     }
                  }
               }
            }
         }
         
         if (!enable_hedge_sl)
         {
            calculate_group_profit();
         }
      }
      
      // new
      if (!enable_grid && !enable_hedge_sl)
      {
         if (PositionsTotal() == 0) start_hedge_positions();
         calculate_group_profit();
      }
   }
   
   static int totalbars = iBars(_Symbol, PERIOD_CURRENT);
   int bars = iBars(_Symbol, PERIOD_CURRENT);
  
   check_arrays();
   
   if (TimeCurrent()> clear_time && ObjectFind(0, BOX_NAME)>=0) clear_objects();
}

//+------------------------------------------------------------------+ 
//| TradeTransaction function                                        | 
//+------------------------------------------------------------------+ 
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
   
   ENUM_TRADE_TRANSACTION_TYPE type = (ENUM_TRADE_TRANSACTION_TYPE)trans.type; 
   if (type == TRADE_TRANSACTION_DEAL_ADD ){
      
      modify_grid_tp();
   }
   
   if (type == TRADE_TRANSACTION_ORDER_DELETE)
   {
      if (!enable_grid && enable_hedge && !enable_hedge_sl)
      {  
         // update v2.0
         int total = 0;
         for (int i=0; i<PositionsTotal(); i++){
            ulong tikt = PositionGetTicket(i);
            if (PositionSelectByTicket(tikt))
            {
               if (PositionGetInteger(POSITION_MAGIC) == Magic) total ++;
            }
         }
         
         
         if (total == 2)
         {
            for(int j=0;j<PositionsTotal(); j++){
               ulong tikt = PositionGetTicket(j);
               if (PositionGetString(POSITION_COMMENT) == "hedge" && PositionGetInteger(POSITION_MAGIC) == Magic)
                  trade.PositionModify(tikt, 0,0);
            }
         }
      }
      if (trans.order_type == ORDER_TYPE_BUY_STOP )
      {
         string new_tikt = ( string )trans.position;
         string old_tikt = ( string )trans.order;
         update_order_state(old_tikt, new_tikt);
         
         double lot     = fix_lot_size_digits(trans.volume*(1+(hedge_multiplier/100)));
         Print("sell stop lot size in trans:  ",lot ," which is trans.volume - ",trans.volume, " * ", (1+(hedge_multiplier/100)));
         double price   = trans.price - hedge_step*10*_Point;
         if(positions_open(price))
         {
            trade.SellStop(lot, price, _Symbol);
            string stop_pos_number = (string)trade.ResultOrder();
            if (!store_oscillating_trades(stop_pos_number, "sell", "hedge", "deactive", (long)new_tikt))
               trade.OrderDelete((long)stop_pos_number);
         }
      }
      else if (trans.order_type == ORDER_TYPE_SELL_STOP)
      {
         string new_tikt = ( string )trans.position;
         string old_tikt = ( string )trans.order;
         update_order_state(old_tikt, new_tikt);
         
         double lot     = fix_lot_size_digits(trans.volume*(1+(hedge_multiplier/100)));
         Print("BUY stop lot size in trans:  ",lot," which is trans.volume - ",trans.volume, " * ", (1+(hedge_multiplier/100)));
         double price   = trans.price + hedge_step*10*_Point;
         if (positions_open(price))
         {
            trade.BuyStop(lot, price, _Symbol);
            string stop_pos_number = (string)trade.ResultOrder();
            if (!store_oscillating_trades(stop_pos_number, "buy", "hedge", "deactive", (long)new_tikt))
               trade.OrderDelete((long)stop_pos_number);
         }
      }
      long order_tikt = 0;
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
            old_lot_grid_value_buy * (1 + (grid_multiplier/100)) :
            old_lot_grid_value_buy + (lot_size*grid_multiplier/100) ,

      buy_lot        = current < last_buy_price? new_lot_buy : lot_size;
   
   buy_lot = is_grid_open("buy")? buy_lot: lot_size;
   // check no active BUY position is on that price level   
   if (check_grid_data("buy-price", ( string )SymbolInfoDouble(_Symbol, SYMBOL_ASK)) == -1)
   {  
      if (positions_open(current))
      {
         if (trade.Buy(fix_lot_size_digits(buy_lot), _Symbol, 0, 0, buy_tp, "grid"))
         {
            store_grid_data((string)trade.ResultOrder(), "buy", buy_lot);
            old_lot_grid_value_buy = buy_lot;
            last_buy_price = current;
         }
      }
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
            old_lot_grid_value_sell *(1 + (grid_multiplier/100)) :
            old_lot_grid_value_sell + (lot_size*grid_multiplier/100),
      sell_lot       = current > last_sell_price? new_lot_sell : lot_size; 
   
   sell_lot = is_grid_open("sell")? sell_lot : lot_size;
   // check no active SELL position is on that price level 
   if (check_grid_data("sell-price", ( string )SymbolInfoDouble(_Symbol, SYMBOL_BID)) == -1)
   {
      if (positions_open(current))
      {
         if (trade.Sell(fix_lot_size_digits(sell_lot), _Symbol, 0, 0, sell_tp, "grid"))
         {
            store_grid_data((string)trade.ResultOrder(), "sell", sell_lot);
            old_lot_grid_value_sell = sell_lot;
            last_sell_price = current;
         }
      }
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
               // update v2.0
               if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && PositionGetInteger(POSITION_MAGIC) == Magic)
               {
                  buy_counter ++;
                  double   
                     tp    = PositionGetDouble(POSITION_TP),
                     entry = PositionGetDouble(POSITION_PRICE_OPEN);
                  if (entry > highest_buy) highest_buy = entry;
                  if (entry < lowest_buy ) lowest_buy  = entry;
               }
               if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && PositionGetInteger(POSITION_MAGIC) == Magic)
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
                  if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && PositionGetDouble(POSITION_TP)!=NormalizeDouble(modified_buy_tp, _Digits))
                  {
                     if(PositionGetInteger(POSITION_MAGIC) == Magic)
                     {
                        trade.PositionModify(tikt, 0, modified_buy_tp);
                     }
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
                  if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && PositionGetDouble(POSITION_TP)!=NormalizeDouble(modified_sell_tp, _Digits))
                  {
                     if(PositionGetInteger(POSITION_MAGIC) == Magic)
                     {
                        trade.PositionModify(tikt, 0, modified_sell_tp);
                     }
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
      double 
         buy_tp  = SymbolInfoDouble(_Symbol, SYMBOL_BID) + hedge_step*10*_Point,
         buy_sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - hedge_step*10*_Point;
      string h_ticket = "-1";
      string o_ticket = "-1";
      
      if (trade.Buy(fix_lot_size_digits(lot_size), _Symbol, 0, buy_sl- hedge_step*10*_Point, buy_tp, "hedge"))
      {
         h_ticket = (string)trade.ResultOrder();
      }
      if (h_ticket != "-1")
      {   
         if(!store_oscillating_trades(h_ticket, "buy", "hedge", "active"))
            trade.PositionClose((long)h_ticket);
      }
       
      if (trade.SellStop(fix_lot_size_digits(lot_size*(1+(hedge_multiplier/100))), buy_sl, _Symbol, 0, 0))
      {
         o_ticket = (string)trade.ResultOrder();
         //trade.PositionModify((long)h_ticket, 0, 0);
      }
      if (o_ticket != "-1")
      {   
         if(!store_oscillating_trades(o_ticket, "sell", "hedge", "deactive", (long)h_ticket))
            trade.OrderDelete((long)o_ticket);
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
   Print("hedge buy lot: ", buy_lot);
   double buy_tp = calculate_profit("sell", main_trade_price, (double)positions_data[index][4], current, buy_lot);
   double sell_sl = buy_tp;
   
   if (!enable_hedge_sl && positions_open(main_trade_price))
   {
      buy_sl =0;
      buy_tp =0;
      sell_sl=0;
      sell_tp=0;
   }
   string h_pos_number = "-1";
   if (positions_open(current))
   {
   //--- open hegde position
      if (trade.Buy(fix_lot_size_digits(buy_lot), _Symbol, 0, buy_sl, buy_tp, "hedge"))
      {
         h_pos_number = (string)trade.ResultOrder();
         store_hedge_data(h_pos_number, "buy", buy_lot);
      }
   }
   
   string stop_pos_number ="-1";
   if (!enable_hedge_sl && positions_open(main_trade_price)) 
   {
      double sell_stop_lot = buy_lot*(1+(hedge_multiplier/100));
      Print("hedge sell stop lot: ", sell_stop_lot);
      trade.SellStop(fix_lot_size_digits(sell_stop_lot), main_trade_price, _Symbol, 0, sell_tp);
      stop_pos_number = (string)trade.ResultOrder();
   }
   
   if (!enable_hedge_sl)
   {
      store_oscillating_trades(positions_data[index][0], positions_data[index][3],"grid","active");
      if (h_pos_number != "-1")
      {   
         if (!store_oscillating_trades(h_pos_number, "buy", "hedge", "active", (long)positions_data[index][0]))
            trade.PositionClose(h_pos_number);
      }
      if (stop_pos_number != "-1")
      {   
         if (!store_oscillating_trades(stop_pos_number, "sell", "hedge", "deactive", (long)h_pos_number))
            trade.OrderDelete((long)stop_pos_number);
      }
   }
   //--- modify main position with a new sl
   trade.PositionModify((long)positions_data[index][0], sell_sl, sell_tp);
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
   Print("hedge sell lot: ", sell_lot);
   double sell_tp = calculate_profit("buy", main_trade_price, (double)positions_data[index][4], current, sell_lot);
   double buy_sl = sell_tp;
   
   if (!enable_hedge_sl && positions_open(main_trade_price))
   {
      buy_sl =0;
      buy_tp =0;
      sell_sl=0;
      sell_tp=0;
   }
   
   string h_pos_number = "-1";
   if (positions_open(current))
   {
      //--- open hegde position
      if (trade.Sell(fix_lot_size_digits(sell_lot), _Symbol, 0, sell_sl, sell_tp, "hedge"))
      {
         h_pos_number = (string)trade.ResultOrder();
         store_hedge_data(h_pos_number, "sell", sell_lot);
      }
   }

   string stop_pos_number = "-1";
   if (!enable_hedge_sl && positions_open(main_trade_price)) 
   {
      double buy_stop_lot = sell_lot*(1+(hedge_multiplier/100));
      Print("hedge buy stop lot: ", buy_stop_lot);
      trade.BuyStop(fix_lot_size_digits(buy_stop_lot), main_trade_price, _Symbol, 0, 0);
      stop_pos_number = (string)trade.ResultOrder();
   }
   
   if (!enable_hedge_sl)
   {
      store_oscillating_trades(positions_data[index][0], positions_data[index][3],"grid","active");
      if (h_pos_number != "-1")
      {
         if(!store_oscillating_trades(h_pos_number, "sell", "hedge", "active", (long)positions_data[index][0]))
            trade.PositionClose(h_pos_number);
      }
      if (stop_pos_number != "-1")
      {   
         if(!store_oscillating_trades(stop_pos_number, "buy", "hedge", "deactive", (long)h_pos_number))
            trade.OrderDelete((long)stop_pos_number);
      }
   }
   
   //--- modify main position with a sl
   trade.PositionModify((ulong)positions_data[index][0], buy_sl, buy_tp);
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


//+------------------------------------------------------------------+
//| store the data of trades of a pack of trades                     |
//+------------------------------------------------------------------+
bool store_oscillating_trades(string pos_number, string pos_type, string type, string order_type, long refrence=NULL){
   int size = ArraySize(oscillating_data)/210;
   int i_index, j_index;
   
   if (refrence != NULL)
   {
      for (int i=0; i<size; i++){
         for (int j=0; j<30; j++){
            if (oscillating_data[i][j][0] == (string)refrence)
            {
               if (j != 29)
               {
                  i_index = i;
                  j_index = j+1;
                  break;
               }
               else
               {
                  return false;
               }
            }
         }
      }
   }
   else
   {  
      ArrayResize(oscillating_data, size+1);
      for (int j=0; j<30; j++){
         for (int k=0; k<7; k++){
            oscillating_data[size][j][k] = "-1";
         }
      }
      i_index = size;
      j_index = 0;
   }
   

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

   oscillating_data[i_index][j_index][0] = pos_number;
   oscillating_data[i_index][j_index][1] = ( string )price;
   oscillating_data[i_index][j_index][2] = ( string )refrence;
   oscillating_data[i_index][j_index][3] = pos_type;
   oscillating_data[i_index][j_index][4] = type;
   oscillating_data[i_index][j_index][5] = TimeToString(TimeCurrent());
   oscillating_data[i_index][j_index][6] = order_type;
   return true;
}


//+------------------------------------------------------------------+
//| update data for opened orders                                    |
//+------------------------------------------------------------------+
void update_order_state(string old_tikt, string new_tikt){
   for (int i =0; i< ArraySize(oscillating_data)/210; i++){
      for (int j=0; j<30; j++){
         if (oscillating_data[i][j][0]== old_tikt)
         {
            oscillating_data[i][j][0] = new_tikt;
            oscillating_data[i][j][5] = TimeToString(TimeCurrent());
            oscillating_data[i][j][6] = "active";
         }
      }
   }
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

      return tp;
   }
   else
   {
      tp = ( ( (hedge_profit/sInfo.ContractSize()) + 
               ((main_lot+current_lot)*SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)*2*_Point) -
               (current_price*current_lot) +
               (main_price*main_lot) ) / 
                                         (main_lot-current_lot) );
                                         
      return tp;
   }
}


//+------------------------------------------------------------------+
//| calculate total profit of multiple trade                         |
//+------------------------------------------------------------------+
void calculate_group_profit(){
   string info="";
   for (int i=ArraySize(oscillating_data)/210-1; i>=0; i--){
      double total_profit = 0;
      string tikets;
      for (int j=0; j<30; j++){
         if (oscillating_data[i][j][0] != "-1" && oscillating_data[i][j][6] == "active"){
            if (PositionSelectByTicket((long)oscillating_data[i][j][0]))
            {
               double 
                  p = PositionGetDouble(POSITION_PROFIT),
                  s = PositionGetDouble(POSITION_SWAP),
                  c = PositionGetDouble(POSITION_VOLUME)*6.6;
               
               if (profit_mtd == Profit)
                  total_profit += (p);
               else if (profit_mtd == commission)
                  total_profit += (p-c);
               else
                  total_profit += (p-c-s);
               if (oscillating_data[i][j][6]=="active")
                  tikets += oscillating_data[i][j][0] + " ";
               else
                  tikets += "o"+oscillating_data[i][j][0] + " ";
            }
         }
      }
      
      if (total_profit > hedge_profit)
      {
         info += "positions <"+ tikets+ "> were closed with total profit of "+ (string) NormalizeDouble(total_profit,2)+" \n";
         close_positions_at(i);
      }
      
   }
   if (info != "")
      create_info_box(info);

}


//+------------------------------------------------------------------+
//| check if orders exist on a level in order to stop hedge          |
//+------------------------------------------------------------------+
bool stop_orders_exists(double price){
   bool exists = false;
   for (int k=0; k<OrdersTotal(); k++){
      ulong order_tikt = OrderGetTicket(k);
      if (MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - price)<_Point*2*max_entry_ecc && OrderGetInteger(ORDER_MAGIC)==Magic)
         return true;
   }
   for (int k=0; k<PositionsTotal(); k++){
      ulong order_tikt = PositionGetTicket(k);
      if (MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - price)<_Point*2*max_entry_ecc && PositionGetString(POSITION_COMMENT)=="" && OrderGetInteger(ORDER_MAGIC)==Magic)
         return true;
   }
   
   return false;
   
}


//+------------------------------------------------------------------+
//| check the number of open positions on a price level              |
//+------------------------------------------------------------------+
bool positions_open(double price){
   int trade_count = 0;
   for (int k=0; k<OrdersTotal(); k++){
      ulong order_tikt = OrderGetTicket(k);
      if (MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - price)<_Point*2*max_entry_ecc && OrderGetInteger(ORDER_MAGIC)==Magic)
         trade_count ++;
   }
   for (int k=0; k<PositionsTotal(); k++){
      ulong order_tikt = PositionGetTicket(k);
      if (MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - price)<_Point*2*max_entry_ecc && PositionGetInteger(POSITION_MAGIC)==Magic)
         trade_count ++;
   }

   if (trade_count <max_trades) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| closes all positions of a group                                  |
//+------------------------------------------------------------------+
void close_positions_at(int index){
   for (int j=0; j<30; j++){
      if (oscillating_data[index][j][0] != "-1")
      {
         if (oscillating_data[index][j][6] == "active")
         {
            trade.PositionClose((long)oscillating_data[index][j][0]);
         }
         else
         {
            trade.OrderDelete((long)oscillating_data[index][j][0]);
         }
      }
   }
   
   bool must_delete_row = true;
   for (int j=0; j<30; j++){
      if (oscillating_data[index][j][0] != "-1")
      {
         if (oscillating_data[index][j][6] == "active" && PositionSelectByTicket((long)oscillating_data[index][j][0]))
            must_delete_row = false;
      }
   }
   if (must_delete_row)
      ArrayRemove(oscillating_data, index, 1);
   
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


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void check_arrays(){
   for (int i=(ArraySize(positions_data)/6)-1; i>=0; i--){
      if (!PositionSelectByTicket((ulong)positions_data[i][0]))
      {
         ArrayRemove(positions_data, i,1);
      }
   }
   for (int i=(ArraySize(hedge_data)/6)-1; i>=0; i--){
      if (!PositionSelectByTicket((ulong)hedge_data[i][0]))
      {
         ArrayRemove(hedge_data, i, 1);
      }
   }
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool is_grid_open(string type){
   if (PositionsTotal()>0)
   {
      for (int i=0; i<PositionsTotal(); i++){
         ulong tikt = PositionGetTicket(i);
         if (type == "buy")
         {   
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY &&
             PositionGetString(POSITION_COMMENT) == "grid" &&
             PositionGetInteger(POSITION_MAGIC) == Magic ) return true;
         }
         if (type == "sell")
         {
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && 
            PositionGetString(POSITION_COMMENT) == "grid" &&
            PositionGetInteger(POSITION_MAGIC) == Magic ) return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| create a ui box for user to see closed positions                 |
//+------------------------------------------------------------------+
void create_info_box(string text){
   int len = StringLen(text);
   
   if(ObjectFind(0, BOX_NAME) <= -1)
   {
      ObjectCreate(0, BOX_NAME, OBJ_RECTANGLE_LABEL, 0, 0,0);
      ObjectSetInteger(0, BOX_NAME, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, BOX_NAME, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, BOX_NAME, OBJPROP_YDISTANCE, 36);
      ObjectSetInteger(0, BOX_NAME, OBJPROP_XSIZE, 50+len*8);
      ObjectSetInteger(0, BOX_NAME, OBJPROP_YSIZE, 32);
      ObjectSetInteger(0, BOX_NAME, OBJPROP_BGCOLOR, box_clr);
      ObjectSetInteger(0, BOX_NAME, OBJPROP_COLOR, box_clr);
   }
   else {
      ObjectSetInteger(0, BOX_NAME, OBJPROP_XSIZE, 50+len*8);
   }
   if (ObjectFind(0, TEXT_NAME) <= -1)
   {
      ObjectCreate(0, TEXT_NAME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, TEXT_NAME, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, TEXT_NAME, OBJPROP_XDISTANCE, 30);
      ObjectSetInteger(0, TEXT_NAME, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, TEXT_NAME, OBJPROP_XSIZE, 40+len*8);
      ObjectSetInteger(0, TEXT_NAME, OBJPROP_COLOR, text_clr);
   }
   
   ObjectSetString(0, TEXT_NAME, OBJPROP_TEXT, text);
   
   clear_time = TimeCurrent()+PeriodSeconds(PERIOD_CURRENT)*box_time;
}


//+------------------------------------------------------------------+
//| remove all objects drawn                                         |
//+------------------------------------------------------------------+
void clear_objects(){
   ObjectDelete(0, BOX_NAME);
   ObjectDelete(0, TEXT_NAME);
}