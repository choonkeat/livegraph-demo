FROM scratch

COPY build/livegraph /app/livegraph
COPY build/static /app/static

WORKDIR /app
