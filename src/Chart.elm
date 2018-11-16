module Chart exposing (view)

import Api exposing (TimeValue)
import Array
import Html exposing (Html, text)
import LineChart
import LineChart.Area
import LineChart.Axis
import LineChart.Axis.Intersection
import LineChart.Colors
import LineChart.Container
import LineChart.Dots
import LineChart.Events
import LineChart.Grid
import LineChart.Interpolation
import LineChart.Junk
import LineChart.Legends
import LineChart.Line
import Time


view : Time.Zone -> Api.Data -> Html msg
view tz data =
    LineChart.viewCustom (chartConfig tz) <|
        List.indexedMap toLineChartSeries data.series


colors =
    Array.fromList
        [ LineChart.Colors.blue
        , LineChart.Colors.black
        , LineChart.Colors.cyan
        , LineChart.Colors.goldLight
        , LineChart.Colors.gray
        , LineChart.Colors.green
        , LineChart.Colors.pink
        , LineChart.Colors.red
        , LineChart.Colors.rust
        , LineChart.Colors.teal
        ]


dots =
    Array.fromList
        [ LineChart.Dots.circle
        , LineChart.Dots.diamond
        , LineChart.Dots.cross
        , LineChart.Dots.square
        , LineChart.Dots.triangle
        ]


toLineChartSeries : Int -> Api.Series -> LineChart.Series Api.TimeValue
toLineChartSeries index series =
    let
        chosenColor =
            Maybe.withDefault LineChart.Colors.purple
                (Array.get
                    (modBy (Array.length colors) index)
                    colors
                )

        chosenDot =
            Maybe.withDefault LineChart.Dots.plus
                (Array.get
                    (modBy (Array.length dots) index)
                    dots
                )
    in
    LineChart.line chosenColor chosenDot series.name series.timeValues


chartConfig : Time.Zone -> LineChart.Config TimeValue msg
chartConfig tz =
    { y = LineChart.Axis.default 400 "score" .value
    , x = LineChart.Axis.none 800 .milliseconds
    , container = LineChart.Container.default "line-chart-1"
    , interpolation = LineChart.Interpolation.default
    , intersection = LineChart.Axis.Intersection.default
    , legends = LineChart.Legends.default
    , events = LineChart.Events.default
    , junk = LineChart.Junk.default
    , grid = LineChart.Grid.default
    , area = LineChart.Area.normal 0.5 -- Changed from the default!
    , line = LineChart.Line.wider 2.5
    , dots = LineChart.Dots.default
    }
