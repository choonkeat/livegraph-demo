package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	graphql "github.com/graph-gophers/graphql-go"
	"github.com/graph-gophers/graphql-go/relay"
	"github.com/graph-gophers/graphql-transport-ws/graphqlws"
	"github.com/graph-gophers/graphql-transport-ws/graphqlws/event"
)

func main() {
	resolver := Resolver{games: map[string]*Game{}}
	s, err := graphql.ParseSchema(schema, &resolver)
	if err != nil {
		log.Fatalln(err.Error())
	}
	graphQLHandler := newHandler(s, &resolver, &relay.Handler{Schema: s})
	http.HandleFunc("/graphql", graphQLHandler)
	http.Handle("/", http.FileServer(http.Dir("./static")))

	addr := os.Getenv("ADDR")
	if addr == "" {
		addr = ":5000"
	}
	log.Println("Listening at", addr, "...")
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}

func newHandler(s *graphql.Schema, resolver *Resolver, httpHandler http.Handler) http.HandlerFunc {
	wsHandler := graphqlws.NewHandler(&subscriptionHandler{resolver: resolver, schema: s})
	return func(w http.ResponseWriter, r *http.Request) {
		for _, subprotocol := range websocket.Subprotocols(r) {
			if subprotocol == "graphql-ws" {
				wsHandler.ServeHTTP(w, r)
				return
			}
		}
		httpHandler.ServeHTTP(w, r)
	}
}

type subscriptionHandler struct {
	resolver *Resolver
	schema   *graphql.Schema
}

func (h *subscriptionHandler) OnOperation(ctx context.Context, args *event.OnOperationArgs) (json.RawMessage, func(), error) {
	log.Printf("OnOperation")
	ctx, cancel := context.WithCancel(ctx)
	payloadVars := map[string]interface{}{}
	for k, v := range args.Payload.Variables {
		var realv interface{}
		if err := json.Unmarshal(v, &realv); err != nil {
			log.Println(string(v), err.Error())
		} else {
			log.Println(string(v), "ok")
			payloadVars[k] = realv
		}
	}
	c, err := h.schema.Subscribe(ctx, args.Payload.Query, args.Payload.OperationName, map[string]interface{}(payloadVars))
	if err != nil {
		log.Println(err)
		cancel()
		return nil, nil, err
	}

	go func() {
		log.Println("start goroutine")
		defer log.Println("end goroutine")
		defer cancel()
		defer func() {
			argsGame, ok := payloadVars["game"].(string)
			if !ok {
				return
			}
			argsName, ok := payloadVars["name"].(string)
			if !ok {
				return
			}
			log.Printf("removing %#v, %#v", argsGame, argsName)
			h.resolver.mu.Lock()
			for gname := range h.resolver.games {
				if gname != argsGame {
					continue
				}
				delete(h.resolver.games[gname].channels, argsName)
			}
			h.resolver.mu.Unlock()
		}()

		for {
			select {
			case <-ctx.Done():
			case m, more := <-c:
				if !more {
					return
				}
				log.Println("send new data to subscriber", m)

				data, err := json.Marshal(m)
				if err != nil {
					log.Println(err)
					args.Send(json.RawMessage(`{"errors":["internal error: can't marshal response into json"]}`))
					continue
				}
				args.Send(json.RawMessage(data))
			}
		}
	}()

	return nil, cancel, nil
}

/*
 *
 * GraphQL schema and resolvers
 *
 */

var schema = `
schema {
	query: Query
	mutation: Mutation
	subscription: Subscription
}

type Query {
	data(game: String!): Data!
}

type Mutation {
	addData(game: String!, name: String!, value: Int!): TimeValue!
}

type Subscription {
	newValues(game: String!, name: String!): NewTimeValue!
}

type TimeValue {
	milliseconds: String!
	value: Int!
}

type NewTimeValue {
	name: String!
	timeValue: TimeValue!
}

type Data {
	series: [Series!]!
}

type Series {
	name: String!
	timeValues: [TimeValue!]!
}
`

type Resolver struct {
	mu    sync.RWMutex
	games map[string]*Game
}

func (r *Resolver) Data(ctx context.Context, args struct {
	Game string
}) (*Game, error) {
	g, ok := r.games[args.Game]
	if !ok {
		return &Game{
			name: args.Game,
			Data: &Data{
				series: []*Series{},
			},
		}, nil
	}
	return g, nil
}

func (r *Resolver) AddData(ctx context.Context, args struct {
	Game  string
	Name  string
	Value int32
}) (*TimeValue, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now().UTC()
	oldest := now.Add(-(15 * time.Second))
	nt := NewTimeValue{
		name: args.Name,
		tv: &TimeValue{
			value:        args.Value,
			milliseconds: fmt.Sprintf("%d", now.UnixNano()/int64(time.Millisecond)),
		},
	}
	defer func() {
		for k := range r.games[args.Game].channels {
			log.Println("broadcasting", args.Game, "to", k)
			r.games[args.Game].channels[k] <- &nt
		}
	}()

	if r.games == nil {
		r.games = map[string]*Game{}
	}

	g, ok := r.games[args.Game]
	if !ok {
		g = &Game{
			name:     args.Game,
			channels: map[string](chan *NewTimeValue){},
			Data: &Data{
				series: []*Series{},
			},
		}
		r.games[args.Game] = g
	}

	var found bool
	tv := TimeValue{
		t:            now,
		milliseconds: nt.tv.milliseconds,
		value:        nt.tv.value,
	}
	for i := range g.series {
		offset := 0
		for j := range g.series[i].timeValues {
			if g.series[i].timeValues[j].t.Before(oldest) {
				offset++
			}
		}
		g.series[i].timeValues = g.series[i].timeValues[offset:]

		if g.series[i].name == args.Name {
			g.series[i].timeValues = append(g.series[i].timeValues, &tv)
			found = true
		}
	}
	if found {
		return &tv, nil
	}

	g.series = append(g.series, &Series{
		name:       args.Name,
		timeValues: []*TimeValue{&tv},
	})

	return &tv, nil
}

func (r *Resolver) NewValues(ctx context.Context, args struct {
	Game string
	Name string
}) (<-chan *NewTimeValue, error) {
	g, ok := r.games[args.Game]
	if !ok {
		log.Println("Adding game", args.Game)
		r.mu.Lock()
		g = &Game{
			name:     args.Game,
			channels: map[string](chan *NewTimeValue){},
			Data: &Data{
				series: []*Series{},
			},
		}
		r.games[args.Game] = g
		r.mu.Unlock()
	}

	c, ok := g.channels[args.Name]
	if !ok {
		log.Println("Adding subscription", args.Name, "on game=", args.Game)
		c = make(chan *NewTimeValue)
		g.channels[args.Name] = c
	} else {
		log.Println("Re-establishing subscription", args.Name, "on game=", args.Game)
	}
	return c, nil
}

/*
 *
 * GraphQL types
 *
 */

type Game struct {
	channels map[string]chan *NewTimeValue
	name     string
	*Data
}

/*
 */

type Series struct {
	name       string
	timeValues []*TimeValue
}

func (s *Series) Name() string {
	return s.name
}

func (s *Series) TimeValues() []*TimeValue {
	return s.timeValues
}

/*
 */

type TimeValue struct {
	t            time.Time
	milliseconds string
	value        int32
}

func (t *TimeValue) Milliseconds() string {
	return t.milliseconds
}

func (t *TimeValue) Value() int32 {
	return t.value
}

/*
 */

type NewTimeValue struct {
	name string
	tv   *TimeValue
}

func (t *NewTimeValue) Name() string {
	return t.name
}

func (t *NewTimeValue) TimeValue() *TimeValue {
	return t.tv
}

/*
 */

type Data struct {
	series []*Series
}

func (d *Data) Series() []*Series {
	return d.series
}
