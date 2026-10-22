package id.ninjasage
{
   import Storage.Character;
   import com.brokenfunction.json.decodeJson;
   import com.brokenfunction.json.encodeJson;
   import flash.filesystem.File;
   
   public class Util
   {
      
      public function Util()
      {
         super();
      }
      
      public static function copy(param1:*) : *
      {
         return decodeJson(encodeJson(param1));
      }
      
      public static function copyObject(param1:Object, param2:Object = null) : *
      {
         var _loc3_:String = null;
         if(param2 == null)
         {
            param2 = {};
         }
         for(_loc3_ in param1)
         {
            param2[_loc3_] = param1[_loc3_];
         }
         return param2;
      }
      
      public static function calculateFromString(param1:String, param2:Object = null) : Number
      {
         var _loc7_:String = null;
         var _loc9_:String = null;
         var _loc10_:Number = NaN;
         var _loc11_:Number = NaN;
         var _loc3_:Array = [];
         var _loc4_:Array = [];
         var _loc5_:Object = {
            "+":{
               "p":2,
               "d":"L"
            },
            "-":{
               "p":2,
               "d":"L"
            },
            "*":{
               "p":3,
               "d":"L"
            },
            "/":{
               "p":3,
               "d":"L"
            },
            "%":{
               "p":3,
               "d":"L"
            },
            "^":{
               "p":4,
               "d":"R"
            }
         };
         param1 = param1.replace(/\s+/g,"");
         var _loc6_:Array = param1.match(/([a-zA-Z]+|\d+\.?\d*|\+|\-|\*|\/|\%|\^|\(|\))/g);
         for each(_loc7_ in _loc6_)
         {
            if(!isNaN(Number(_loc7_)))
            {
               _loc3_.push(_loc7_);
            }
            else if(Boolean(param2) && param2.hasOwnProperty(_loc7_))
            {
               _loc3_.push(param2[_loc7_]);
            }
            else if(_loc7_ == "(")
            {
               _loc4_.push(_loc7_);
            }
            else if(_loc7_ == ")")
            {
               while(_loc4_.length > 0 && _loc4_[_loc4_.length - 1] != "(")
               {
                  _loc3_.push(_loc4_.pop());
               }
               _loc4_.pop();
            }
            else if(_loc5_[_loc7_])
            {
               while(Boolean(_loc4_.length > 0) && Boolean(_loc5_[_loc4_[_loc4_.length - 1]]) && (_loc5_[_loc7_].d == "L" && _loc5_[_loc7_].p <= _loc5_[_loc4_[_loc4_.length - 1]].p || _loc5_[_loc7_].d == "R" && _loc5_[_loc7_].p < _loc5_[_loc4_[_loc4_.length - 1]].p))
               {
                  _loc3_.push(_loc4_.pop());
               }
               _loc4_.push(_loc7_);
            }
         }
         while(_loc4_.length > 0)
         {
            _loc3_.push(_loc4_.pop());
         }
         var _loc8_:Array = [];
         for each(_loc9_ in _loc3_)
         {
            if(!isNaN(Number(_loc9_)))
            {
               _loc8_.push(Number(_loc9_));
               continue;
            }
            _loc10_ = _loc8_.pop();
            _loc11_ = _loc8_.pop();
            switch(_loc9_)
            {
               case "+":
                  _loc8_.push(_loc11_ + _loc10_);
                  break;
               case "-":
                  _loc8_.push(_loc11_ - _loc10_);
                  break;
               case "*":
                  _loc8_.push(_loc11_ * _loc10_);
                  break;
               case "/":
                  _loc8_.push(_loc11_ / _loc10_);
                  break;
               case "%":
                  _loc8_.push(_loc11_ % _loc10_);
                  break;
               case "^":
                  _loc8_.push(Math.pow(_loc11_,_loc10_));
            }
         }
         return _loc8_.pop();
      }
      
      public static function convertToNumber(param1:String) : Number
      {
         var _loc2_:Number = 1;
         var _loc3_:String = param1;
         var _loc4_:String = param1.charAt(param1.length - 1).toLowerCase();
         switch(_loc4_)
         {
            case "k":
               _loc2_ = 1000;
               _loc3_ = param1.substring(0,param1.length - 1);
               break;
            case "m":
               _loc2_ = 1000000;
               _loc3_ = param1.substring(0,param1.length - 1);
               break;
            case "b":
               _loc2_ = 1000000000;
               _loc3_ = param1.substring(0,param1.length - 1);
               break;
            case "t":
               _loc2_ = 1000000000000;
               _loc3_ = param1.substring(0,param1.length - 1);
               break;
            default:
               _loc2_ = 1;
               _loc3_ = param1;
         }
         var _loc5_:Number = Number(_loc3_);
         if(isNaN(_loc5_))
         {
            throw new Error("Invalid numeric value");
         }
         return _loc5_ * _loc2_;
      }
      
      public static function formatNumberWithDot(param1:Number) : String
      {
         var _loc2_:String = param1.toString();
         var _loc3_:String = "";
         var _loc4_:int = 0;
         var _loc5_:* = int(_loc2_.length - 1);
         while(_loc5_ >= 0)
         {
            _loc3_ = _loc2_.charAt(_loc5_) + _loc3_;
            if(++_loc4_ % 3 == 0 && _loc5_ != 0)
            {
               _loc3_ = "." + _loc3_;
            }
            _loc5_--;
         }
         return _loc3_;
      }
      
      public static function in_array(param1:*, param2:Array) : Boolean
      {
         var _loc3_:Boolean = false;
         var _loc4_:* = 0;
         while(_loc4_ < param2.length)
         {
            if(param2[_loc4_] == param1)
            {
               _loc3_ = true;
            }
            _loc4_++;
         }
         return _loc3_;
      }
      
      public static function checkInArray(param1:String, param2:Array) : Boolean
      {
         var _loc4_:String = null;
         var _loc3_:Boolean = false;
         for each(_loc4_ in param2)
         {
            if(_loc4_ == param1)
            {
               return true;
            }
         }
         return false;
      }
      
      public static function url(param1:String) : String
      {
         if(param1.length >= 4 && param1.charAt(0) == "h" && param1.charAt(1) == "t" && param1.charAt(2) == "t" && param1.charAt(3) == "p")
         {
            return param1;
         }
         param1 = param1.replace("app-storage:/","");
         return (Character.cdn ? Character.cdn : "https://ninjasage.test/") + param1;
      }
      
      public static function formatBytesSize(param1:Number) : String
      {
         if(param1 < 1024)
         {
            return param1 + " B";
         }
         if(param1 < 1048576)
         {
            return (param1 / 1024).toFixed(2) + " KB";
         }
         if(param1 < 1073741824)
         {
            return (param1 / 1048576).toFixed(2) + " MB";
         }
         return (param1 / 1073741824).toFixed(2) + " GB";
      }
   }
}

