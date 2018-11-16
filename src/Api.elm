module Api exposing (Data, NewTimeValue, Series, TimeValue, decodeData, decodeNewTimeValue, decodeSeries, decodeTimeValue)

import Json.Decode


type alias TimeValue =
    { milliseconds : Float
    , value : Float
    }


type alias NewTimeValue =
    { name : String
    , timeValue : TimeValue
    }


type alias Data =
    { series : List Series
    }


type alias Series =
    { name : String
    , timeValues : List TimeValue
    }



--


decodeTimeValue : Json.Decode.Decoder TimeValue
decodeTimeValue =
    Json.Decode.map2 TimeValue
        (Json.Decode.field "milliseconds" (Json.Decode.map (\s -> Maybe.withDefault 0.0 (String.toFloat s)) Json.Decode.string))
        (Json.Decode.field "value" (Json.Decode.map (\i -> toFloat i) Json.Decode.int))


decodeNewTimeValue : Json.Decode.Decoder NewTimeValue
decodeNewTimeValue =
    Json.Decode.map2 NewTimeValue
        (Json.Decode.field "name" Json.Decode.string)
        (Json.Decode.field "timeValue" decodeTimeValue)


decodeData : Json.Decode.Decoder Data
decodeData =
    Json.Decode.map Data
        (Json.Decode.field "series" (Json.Decode.list decodeSeries))


decodeSeries : Json.Decode.Decoder Series
decodeSeries =
    Json.Decode.map2 Series
        (Json.Decode.field "name" Json.Decode.string)
        (Json.Decode.field "timeValues" (Json.Decode.list decodeTimeValue))
