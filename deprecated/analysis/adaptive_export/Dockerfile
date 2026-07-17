# syntax=docker/dockerfile:1.7

FROM golang:1.24.6-alpine AS build
RUN apk add --no-cache git ca-certificates

WORKDIR /pixie
COPY pixie/pixie/ /pixie/

WORKDIR /pixie/src/vizier/services/adaptive_export/cmd
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /adaptive-export .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata \
 && adduser -D -u 10100 -g 10100 adaptive
USER 10100:10100
COPY --from=build /adaptive-export /usr/local/bin/adaptive-export
ENTRYPOINT ["/usr/local/bin/adaptive-export"]
