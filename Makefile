run-livegraph: build-livegraph
	docker run --env ADDR=0.0.0.0:5000 -p 5000:5000 livegraph:latest ./livegraph

build-livegraph:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o build/livegraph cmd/livegraph/main.go
	elm make --output=build/static/livegraph.js src/LiveGraph.elm
	docker build . -t livegraph

