# Code for live updating graph in Elm

1. GraphQL server in Go
2. Elm frontend, with [my basic websocket port](https://gist.github.com/choonkeat/8f61b6b1be0a584fdaaf58b06be71bad)

# Pre-requisites

Elm 0.19, Go and Docker

# Run

```
make
```

- Visit [http://localhost:5000/](http://localhost:5000/) for the demo -- type `hello world` into the text area and the graph will go up as you typed correctly (try multiple, concurrent browser tabs)
- Visit [http://localhost:5000/graphiql.html](http://localhost:5000/graphiql.html) for GraphiQL interface
