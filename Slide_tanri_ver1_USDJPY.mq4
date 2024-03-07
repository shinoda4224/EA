//+------------------------------------------------------------------+
//|                                               MA_Renko_tanri.mq4 |
//|                                                     Yuki Shinoda |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Yuki Shinoda"
#property link      ""
#property version   "1.00"
#property strict

#include <stdlib.mqh>

#define   MAGIC_NO  42244224

input double    entry_jpy                   = 1500000;      // 1エントリーの掛け金(JPY)
input int       ma_length                   = 10;           // 移動平均線の期間(日)
input double    step_pecentage              = 0.6;          // ステップの幅(%)
input bool      Not_allowed_by_hour         = true;         // 時間帯によるエントリー禁止
input bool      Not_allowed_by_day          = false;        // 日によるエントリー禁止
input bool      Not_allowed_by_dayofweek    = false;        // 曜日によるエントリー禁止
input bool      cross_Yen                   = true;         // クロス円=True, ドルストレート=False
input bool      money_management            = false;        // 複利機能
input double    mm_rate                     = 10.0;         // 証拠金に対する1エントリーの掛け金の割合(%)

//ロジックパラメーター初期化
int renko_dir = 1;                                 //1=long, 0=short
double step_width = iClose(NULL, 0, 1) * step_pecentage * 0.01;
double max_std = iClose(NULL, 0, 1);
double min_std = iClose(NULL, 0, 1);

// ロジック構造体
enum STEP_VARY { up_to_up, up_to_dn, up_cont, dn_to_dn, dn_to_up, dn_cont};

// ポジション情報構造体型
struct struct_PositionInfo {
    int               ticket_no;                // チケットNo
    int               entry_dir;                // エントリーオーダータイプ
    double            set_limit;                // リミットレート
    double            set_stop;                 // ストップレート
    datetime          entry_time;               // エントリー時間
};

// ポジション情報構造体型インスタンス化
static struct_PositionInfo  _StPositionInfoData;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
    static    datetime s_lasttime;                      // 最後に記録した時間軸時間
                                                        // staticはこの関数が終了してもデータは保持される
    datetime temptime = iTime( Symbol(), Period(), 0 ); // 現在の時間軸の時間取得
    if ( temptime == s_lasttime ) {                     // 時間に変化が無い場合
        return;                                         // 処理終了
    }
    s_lasttime = temptime;                              // 最後に記録した時間軸時間を
        
    if ( iBars(NULL,0) <= ma_length ) {                 // バーの数が移動平均線の期間より少ない場合
        return;                                         // 処理終了
    }
    
    STEP_VARY logic_result = Logic();                   // ロジック計算

    JudgeClose( logic_result );                         // 決済オーダー判定
    JudgeEntry( logic_result );                         // エントリーオーダー判定    
  }
  
//+------------------------------------------------------------------+
//| ロジック計算
//+------------------------------------------------------------------+
STEP_VARY Logic() {

    STEP_VARY   logic_ret       = up_cont;
    int         renko_dir_new   = 1;

    double      ema             = iMA(NULL, 0, ma_length, 0, MODE_EMA, PRICE_CLOSE, 1);
   
    if (renko_dir == 1){
        if(ema - max_std > 0){
            max_std         = ema;
            step_width      = step_pecentage * 0.01 * max_std;
            renko_dir_new   = 1;
            logic_ret       = up_to_up;
        }
        else if(ema - max_std <= -1*step_width){
            min_std         = max_std - step_width;
            step_width      = step_pecentage * 0.01 * min_std;
            renko_dir_new   = -1;
            logic_ret       = up_to_dn;
        }
        else{
            renko_dir_new   = 1;
            logic_ret       = up_cont;
        }
    }
  
    else if (renko_dir == -1){
        if(ema - min_std < 0){
            min_std         = ema;
            step_width      = step_pecentage * 0.01 * min_std;
            renko_dir_new   = -1;
            logic_ret       = dn_to_dn;
        }
        else if(ema - min_std >= step_width){
            max_std         = min_std + step_width;
            step_width      = step_pecentage * 0.01 * max_std;
            renko_dir_new   = 1;
            logic_ret       = dn_to_up;
        }
        else{
            renko_dir_new   = -1;
            logic_ret       = dn_cont;
        }
    }
  
    renko_dir = renko_dir_new;
    return logic_ret;
}


//+------------------------------------------------------------------+
//| エントリーオーダー判定
//+------------------------------------------------------------------+
void JudgeEntry( STEP_VARY in_renko ) {
    
    bool entry_bool = false;    // エントリー判定
    bool entry_long = false;    // ロングエントリー判定

    if ( in_renko == dn_to_up ) {
        entry_bool = true;
        entry_long = true;
    } 
    else if ( in_renko == up_to_dn ) {
        entry_bool = true;
        entry_long = false;
    }

    GetPosiInfo( _StPositionInfoData );        // ポジション情報を取得
    
    if ( _StPositionInfoData.ticket_no > 0 ) { // ポジション保有中の場合
        entry_bool = false;                    // エントリー禁止
    }
    
    if ( entry_not_allowed() == true ) {
        entry_bool = false;
    }
    
    if ( entry_bool == true ) {
        EA_EntryOrder( entry_long );           // 新規エントリー
    }
}

//+------------------------------------------------------------------+
//| 決済オーダー判定
//+------------------------------------------------------------------+
void JudgeClose( STEP_VARY in_renko ) {    
    
    bool close_bool = false;    // 決済判定

    GetPosiInfo( _StPositionInfoData );
    
    if ( _StPositionInfoData.ticket_no > 0 ) {                      // ポジション保有中の場合

        if ( _StPositionInfoData.entry_dir == OP_SELL ) {           // 売りポジ保有中の場合
            if ( in_renko == dn_to_up || in_renko == up_to_up ) {
                close_bool = true;
            }
            
        } else if ( _StPositionInfoData.entry_dir == OP_BUY ) {     // 買いポジ保有中の場合
            if ( in_renko == up_to_dn || in_renko == dn_to_dn ) {
                close_bool = true;
            }
        } 
    }
      
    
    if ( close_bool == true ) {
        bool close_done = false;
        close_done = EA_Close_Order( _StPositionInfoData.ticket_no );        // 決済処理

        if ( close_done == true ) {
            ClearPosiInfo(_StPositionInfoData);                             // ポジション情報クリア(決済済みの場合)
        }
    }
}


//+------------------------------------------------------------------+
//| ポジション情報を取得
//+------------------------------------------------------------------+
bool GetPosiInfo( struct_PositionInfo &in_st ){

    bool ret = false;
    int  position_total = OrdersTotal();     // 保有しているポジション数取得

    // 全ポジション分ループ
    for ( int icount = 0 ; icount < position_total ; icount++ ) {

        if ( OrderSelect( icount , SELECT_BY_POS ) == true ) {          // インデックス指定でポジションを選択

            if ( OrderMagicNumber() != MAGIC_NO ) {                     // マジックナンバー不一致判定
                continue;                                               // 次のループ処理へ
            }

            if ( OrderSymbol() != Symbol() ) {                          // 通貨ペア不一致判定
                continue;                                               // 次のループ処理へ
            }

            in_st.ticket_no      = OrderTicket();                       // チケット番号を取得
            in_st.entry_dir      = OrderType();                         // オーダータイプを取得
            in_st.set_limit      = OrderTakeProfit();                   // リミットを取得
            in_st.set_stop       = OrderStopLoss();                     // ストップを取得
            in_st.entry_time     = OrderOpenTime();

            ret = true;

            break;                                                      // ループ処理中断
        }
    }

    return ret;
}

//+------------------------------------------------------------------+
//| ポジション情報をクリア(決済済みの場合)
//+------------------------------------------------------------------+
void ClearPosiInfo( struct_PositionInfo &in_st ) {
    
    if ( in_st.ticket_no > 0 ) { // ポジション保有中の場合

        bool select_bool;                // ポジション選択結果

        // ポジションを選択
        select_bool = OrderSelect(
                        in_st.ticket_no ,// チケットNo
                        SELECT_BY_TICKET // チケット指定で注文選択
                    ); 

        // ポジション選択失敗時
        if ( select_bool == false ) {
            printf( "[%d]不明なチケットNo = %d" , __LINE__ , in_st.ticket_no);
            return;
        }

        // ポジションがクローズ済みの場合
        if ( OrderCloseTime() > 0 ) {
            ZeroMemory( in_st );            // ゼロクリア
        }

    }
    
}



//+------------------------------------------------------------------+
//| エントリー注文
//+------------------------------------------------------------------+
bool EA_EntryOrder( 
                    bool in_long    // true:Long false:Short
) {
    
    bool   ret        = false;      // 戻り値
    int    order_type = OP_BUY;     // 注文タイプ
    double order_rate = Ask;        // オーダープライスレート
    
    if ( in_long == true ) {        // Longエントリー
        order_type = OP_BUY;
        order_rate = Ask;

    } else {                        // Shortエントリー
        order_type = OP_SELL;
        order_rate = Bid;
    }

    int ea_ticket_res = -1;         // チケットNo

    ea_ticket_res = OrderSend(                            // 新規エントリー注文
                                Symbol(),                 // 通貨ペア
                                order_type,               // オーダータイプ[OP_BUY / OP_SELL]
                                Lots_calc(),              // ロット[0.01単位]
                                order_rate,               // オーダープライスレート
                                100,                      // スリップ上限    (int)[分解能 0.1pips]
                                0,                        // ストップレート
                                0,                        // リミットレート
                                "MA_RENKO_EA",            // オーダーコメント
                                MAGIC_NO                  // マジックナンバー(識別用)
                               );   

    if ( ea_ticket_res != -1) {    // オーダー正常完了
        ret = true;

    } else {                       // オーダーエラーの場合

        int    get_error_code   = GetLastError();                   // エラーコード取得
        string error_detail_str = ErrorDescription(get_error_code); // エラー詳細取得

        // エラーログ出力
        printf( "[%d]エントリーオーダーエラー。 エラーコード=%d エラー内容=%s" 
            , __LINE__ ,  get_error_code , error_detail_str
         );        
    }

    return ret;
}

//+------------------------------------------------------------------+
//| 決済注文
//+------------------------------------------------------------------+
bool EA_Close_Order( int in_ticket ){

    bool select_bool;                // ポジション選択結果
    bool ret = false;                // 結果

    // ポジションを選択
    select_bool = OrderSelect(
                    in_ticket ,      // チケットNo
                    SELECT_BY_TICKET // チケット指定で注文選択
                ); 

    // ポジション選択失敗時
    if ( select_bool == false ) {
        printf( "[%d]不明なチケットNo = %d" , __LINE__ , in_ticket);
        return ret;    // 処理終了
    }

    // ポジションがクローズ済みの場合
    if ( OrderCloseTime() > 0 ) {
        printf( "[%d]ポジションクローズ済み チケットNo = %d" , __LINE__ , in_ticket );
        return true;   // 処理終了
    }

    bool   close_bool;                  // 注文結果
    int    get_order_type;              // エントリー方向
    double close_rate = 0 ;             // 決済価格
    double close_lot  = 0;              // 決済数量

    get_order_type = OrderType();       // 注文タイプ取得
    close_lot      = OrderLots();       // ロット数


    if ( get_order_type == OP_BUY ) {            // 買いの場合
        close_rate = Bid;

    } else if ( get_order_type == OP_SELL ) {    // 売りの場合
        close_rate = Ask;

    } else {                                     // エントリー指値注文の場合
        return ret;                              // 処理終了
    }


    close_bool = OrderClose(                // 決済オーダー
                    in_ticket,              // チケットNo
                    close_lot,              // ロット数
                    close_rate,             // クローズ価格
                    20,                     // スリップ上限    (int)[分解能 0.1pips]
                    clrWhite                // 色
                  );

    if ( close_bool == false) {    // 失敗

        int    get_error_code   = GetLastError();                   // エラーコード取得
        string error_detail_str = ErrorDescription(get_error_code); // エラー詳細取得

        // エラーログ出力
        printf( "[%d]決済オーダーエラー。 エラーコード=%d エラー内容=%s" 
            , __LINE__ ,  get_error_code , error_detail_str
         );        
    } else {
        ret = true; // 戻り値設定：成功
    }

    return ret; // 戻り値を返す
}


//+------------------------------------------------------------------+
//| ロット計算
//+------------------------------------------------------------------+
double Lots_calc(){

    double ret;
    double order_jpy = 0.0;

    if (money_management == false){
        order_jpy = entry_jpy;
    }

    else if (money_management == true){
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        order_jpy = 25 * equity * mm_rate * 0.01;
    }


    if (cross_Yen == true){
        ret = round( 100 * ( order_jpy / Close[0] * 0.00001 )) * 0.01;
    }
    else {
        ret = round( 100 * ( order_jpy / iClose( "USDJPY#", PERIOD_M5 , 0 ) / Close[0] * 0.01 )) * 0.01;
    }
    
    if(ret < 0.01) ret = 0.01;      //最小ロット
    if(ret > 50) ret = 50;          //最大ロット

    return ret;
}


//+------------------------------------------------------------------+
//| エントリー禁止時間・日を確認
//+------------------------------------------------------------------+
bool entry_not_allowed(){
    bool ret = false;
    
    int current_hour = Hour();
    int current_day = Day();
    int current_dayofweek = DayOfWeek();

    if ( Not_allowed_by_hour == true ){
        if ( current_hour >= 0 && current_hour <= 9 ){
            ret = true;
        }
    }
    
    if ( Not_allowed_by_day == true ){
        if ( current_day == 2 || current_day == 9 || current_day == 16 || current_day == 23 || current_day == 30 ){
            ret = true;
        }
    }

    if ( Not_allowed_by_dayofweek == true ){
       if ( current_dayofweek == 3 ){
            ret = true;
      }
    }

    return ret;
}

//+------------------------------------------------------------------+
//| サマータイム判定
//+------------------------------------------------------------------+

bool isSummerTime(){
   bool ret = false;
   
   datetime summerStart;   //サマータイム開始日
   datetime summerEnd;     //サマータイム終了日
   datetime tc = TimeCurrent();
   
   //サマータイム開始日を3/14の前の日曜日に設定
   summerStart = StringToTime(IntegerToString(Year()) + ".03.14");
   summerStart = summerStart - TimeDayOfWeek(summerStart) * 24 * 60 * 60;
   
   //サマータイム終了日を11/7の前の日曜日に設定
   summerEnd = StringToTime(IntegerToString(Year()) + ".11.07");
   summerEnd = summerEnd - TimeDayOfWeek(summerEnd) *24 * 60 * 60;
   
   //現在の時刻がサマータイム開始日と終了日の間であればtrueを返す
   if(tc > summerStart && tc < summerEnd) ret = true;
   return ret;
}