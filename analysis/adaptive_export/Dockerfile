FROM golang:1.24-alpine AS build
WORKDIR /src
COPY pixie/pixie/src/api/go /pixie/pixie/src/api/go
COPY pixie/pixie/go.mod pixie/pixie/go.sum /pixie/pixie/
COPY soc/analysis/adaptive_export/ .
RUN go build -o /adaptive-export .

FROM alpine:3.21
COPY --from=build /adaptive-export /usr/local/bin/adaptive-export
ENTRYPOINT ["adaptive-export"]
