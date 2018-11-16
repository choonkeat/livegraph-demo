module LiveGraph exposing (main)

import Api exposing (NewTimeValue, decodeNewTimeValue)
import Browser
import Chart
import Html exposing (Html, br, button, div, form, input, pre, text, textarea)
import Html.Attributes exposing (placeholder, style, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Json.Decode
import Json.Decode.Pipeline
import Json.Encode
import LineChart.Axis.Tick
import RemoteData exposing (WebData)
import Task
import Time
import WebSocket


answer =
    "hello world"


main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }


type alias Flags =
    { graphqlUrl : String
    , uid : String
    }


type alias Model =
    { flags : Flags
    , notice : Maybe String
    , data : WebData Api.Data
    , game : String
    , name : String
    , typedText : String
    , timezone : Time.Zone
    }


type Msg
    = WebSocketConnected Int
    | WebSocketReceive String
    | DataLoaded (WebData Api.Data)
    | OnSetTypedText String
    | DataAdded (WebData Api.TimeValue)
    | DataReceived String Time.Posix
    | UpdateTimezone (Result String Time.Zone)


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        model =
            Model
                flags
                Nothing
                RemoteData.NotAsked
                "foobar"
                ("Guest" ++ flags.uid)
                ""
                Time.utc
    in
    ( model
    , Cmd.batch
        [ Task.attempt UpdateTimezone Time.here
        , loadInitialData flags.graphqlUrl model
        ]
    )


view : Model -> Html Msg
view model =
    let
        chart =
            case model.data of
                RemoteData.NotAsked ->
                    text ""

                RemoteData.Loading ->
                    text "Loading..."

                RemoteData.Failure err ->
                    text (Debug.toString err)

                RemoteData.Success data ->
                    Chart.view model.timezone data
    in
    div []
        [ pre [] [ text (Maybe.withDefault "" model.notice) ]
        , div []
            [ viewForm model ]
        , chart
        ]


viewForm : Model -> Html Msg
viewForm model =
    form []
        [ textarea
            [ onInput OnSetTypedText
            , style "width" "99%"
            , style "height" "3em"
            , placeholder ("Type: " ++ answer)
            ]
            [ text model.typedText ]
        ]


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        WebSocketConnected value ->
            ( model, WebSocket.send (Json.Encode.encode 0 (subscriptionQuery model)) )

        WebSocketReceive value ->
            ( model, Task.perform (DataReceived value) Time.now )

        DataReceived value now ->
            let
                oldest =
                    Time.millisToPosix (Time.posixToMillis now - 15000)

                newTimeValue =
                    Json.Decode.decodeString
                        (Json.Decode.at [ "payload", "data", "newValues" ] decodeNewTimeValue)
                        value

                newdata =
                    addNewTimeValueToData oldest model.data newTimeValue
            in
            ( { model | data = newdata }, Cmd.none )

        DataLoaded data ->
            ( { model | data = data }, Cmd.none )

        OnSetTypedText s ->
            let
                newModel =
                    { model | typedText = s }
            in
            ( newModel, sendData newModel )

        DataAdded webdata ->
            ( model, Cmd.none )

        UpdateTimezone (Result.Ok tz) ->
            ( { model | timezone = tz }, Cmd.none )

        UpdateTimezone (Result.Err err) ->
            ( { model | notice = Just (Debug.toString err) }, Cmd.none )


addNewTimeValueToData : Time.Posix -> WebData Api.Data -> Result x NewTimeValue -> WebData Api.Data
addNewTimeValueToData oldest curr result =
    case curr of
        RemoteData.Success data ->
            case result of
                Ok newTimeValue ->
                    let
                        cleanedSeries =
                            List.map (pruneSeries oldest) data.series

                        newseries =
                            addNewTimeValueToSeries newTimeValue cleanedSeries []
                    in
                    RemoteData.succeed { data | series = newseries }

                Err x ->
                    curr

        _ ->
            curr


{-| Prune data points older than `oldest`
-}
pruneSeries : Time.Posix -> Api.Series -> Api.Series
pruneSeries oldest series =
    { series
        | timeValues =
            List.filter
                (\tv ->
                    toFloat (Time.posixToMillis oldest) < tv.milliseconds
                )
                series.timeValues
    }


addNewTimeValueToSeries : Api.NewTimeValue -> List Api.Series -> List Api.Series -> List Api.Series
addNewTimeValueToSeries newTimeValueApi pending result =
    case pending of
        x :: xs ->
            if newTimeValueApi.name == x.name then
                let
                    newTimeValues =
                        List.append x.timeValues [ newTimeValueApi.timeValue ]

                    newx =
                        { x | timeValues = newTimeValues }
                in
                List.append (List.reverse result) (newx :: xs)

            else
                addNewTimeValueToSeries newTimeValueApi xs (x :: result)

        [] ->
            let
                newx =
                    { name = newTimeValueApi.name, timeValues = [ newTimeValueApi.timeValue ] }
            in
            List.append (List.reverse result) [ newx ]



--


{-| Count how many characters you typed correctly (prefix matching only)
-}
countMatchingPrefix : Int -> List Char -> List Char -> Int
countMatchingPrefix sum correct input =
    case ( correct, input ) of
        ( x :: xs, y :: ys ) ->
            if x == y then
                countMatchingPrefix (sum + 1) xs ys

            else
                sum

        ( _, _ ) ->
            sum


sendData : Model -> Cmd Msg
sendData model =
    let
        value =
            countMatchingPrefix 0 (String.toList answer) (String.toList model.typedText)

        addDataMutation =
            Json.Encode.object
                [ ( "query", Json.Encode.string """
                            mutation mutation($game : String!, $name : String!, $value : Int!) {
                              addData(game:$game, name:$name, value:$value) {
                                milliseconds
                                value
                              }
                            }
                        """ )
                , ( "variables"
                  , Json.Encode.object
                        [ ( "game", Json.Encode.string model.game )
                        , ( "name", Json.Encode.string model.name )
                        , ( "value", Json.Encode.int value )
                        ]
                  )
                ]
    in
    Http.post model.flags.graphqlUrl (Http.jsonBody addDataMutation) (Json.Decode.at [ "data", "addData" ] Api.decodeTimeValue)
        |> RemoteData.sendRequest
        |> Cmd.map DataAdded


{-| websocket payload to send to kick off our 'live' data subscription
-}
subscriptionQuery : Model -> Json.Encode.Value
subscriptionQuery model =
    Json.Encode.object
        [ ( "id", Json.Encode.string model.flags.uid )
        , ( "type", Json.Encode.string "start" )
        , ( "payload"
          , Json.Encode.object
                [ ( "query", Json.Encode.string """
                    subscription subscription($game : String!, $name : String!){
                      newValues(game:$game, name:$name) {
                        name
                        timeValue {
                          milliseconds
                          value
                        }
                      }
                    }
                    """ )
                , ( "variables"
                  , Json.Encode.object
                        [ ( "game", Json.Encode.string model.game )
                        , ( "name", Json.Encode.string model.name )
                        ]
                  )
                ]
          )
        ]


subscriptions : Model -> Sub Msg
subscriptions model =
    WebSocket.listen WebSocketConnected WebSocketReceive


{-| Fire off a GraphQL request to pull initial data off the server for rendering
-}
loadInitialData : String -> Model -> Cmd Msg
loadInitialData graphqlUrl model =
    Http.post graphqlUrl (Http.jsonBody (initialDataQuery model)) (Json.Decode.at [ "data", "data" ] Api.decodeData)
        |> RemoteData.sendRequest
        |> Cmd.map DataLoaded


initialDataQuery : Model -> Json.Encode.Value
initialDataQuery model =
    Json.Encode.object
        [ ( "query", Json.Encode.string """
                query query($game: String!){
                  data(game:$game) {
                    series {
                      name
                      timeValues {
                        milliseconds
                        value
                      }
                    }
                  }
                }
            """ )
        , ( "variables"
          , Json.Encode.object
                [ ( "game", Json.Encode.string model.game )
                ]
          )
        ]
