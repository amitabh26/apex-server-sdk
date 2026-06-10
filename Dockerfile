# syntax=docker/dockerfile:1.6

FROM golang:1.21-alpine AS build
WORKDIR /src

COPY bridge/go.mod ./
RUN go mod download

COPY bridge/*.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags='-s -w' -o /app/bridge

FROM gcr.io/distroless/static:nonroot
WORKDIR /app
COPY --from=build /app/bridge ./bridge

USER nonroot
ENTRYPOINT ["/app/bridge"]
