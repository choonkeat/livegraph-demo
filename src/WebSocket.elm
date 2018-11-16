port module WebSocket exposing (listen, send)

{-| WebSocket module for Elm 0.19. Setup the ports in your `index.html` like this:

      // pre-requisite: obtain `app` via return value of `init`
      var app = Elm.Main.init({
        node: document.getElementById('root'),
      })

      // step 1: hook up outgoing port
      var ws = {}
      app.ports.websocketOut.subscribe(function(msg) {
        try {
          console.log('[js] send', msg);
          ws.conn.send(msg);
        } catch (e) {
          console.log('[js] send fail', e); // e.g. ws.conn not established
        }
      });

      function connectWebSocket(app, wsUrl, optionalProtocol) {
        ws.conn = new WebSocket(wsUrl, optionalProtocol);
        ws.conn.onopen = function (event) {
            console.log('[js] connected', event);
            app.ports.websocketConnected.send(event.timeStamp|0);
        };
        ws.conn.onmessage = function (event) {
            console.log('[js] message', event);
            app.ports.websocketIn.send(event.data);
        };
        ws.conn.onerror = function (event) {
            console.log('[js] error', event);
        };
        ws.conn.onclose = function (event) {
            console.log('[js] close', event);
            ws.conn.onclose = null;
            ws.conn = null;

            setTimeout(function() {
              connectWebSocket(app, wsUrl, optionalProtocol);
            }, 1000);
        };
      }

      // step 2: hook up incoming port
      // e.g.
      connectWebSocket(app, 'ws://echo.websocket.org');

      // or if we're doing https://github.com/graph-gophers/graphql-transport-ws
      // connectWebSocket(app, 'ws://localhost:5000/graphql', 'graphql-ws');

-}


port websocketConnected : (Int -> msg) -> Sub msg


port websocketIn : (String -> msg) -> Sub msg


port websocketOut : String -> Cmd msg


{-| Returns subscription for `open` and `message` events from native `WebSocket` object

    type Msg
        = WebSocketConnected Int
        | WebSocketReceive String

    subscriptions : Model -> Sub Msg
    subscriptions model =
        WebSocket.listen WebSocketConnected WebSocketReceive

-}
listen : (Int -> msg) -> (String -> msg) -> Sub msg
listen connected received =
    Sub.batch
        [ websocketConnected connected
        , websocketIn received
        ]


{-| Sends a message through the native `WebSocket` object

    sendGreeting : Cmd Msg
    sendGreeting =
        WebSocket.send "hello"

-}
send : String -> Cmd msg
send s =
    websocketOut s
