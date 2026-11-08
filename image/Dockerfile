# syntax=docker/dockerfile:1

# TODO: pin the base images by digest (golang:1.27-alpine@sha256:...).
FROM golang:1.27-alpine AS build
WORKDIR /src

COPY go.mod ./
RUN go mod download
COPY cmd/ ./cmd/

# CGO_ENABLED=0 produces a fully static binary, which the minimal runtime image needs. -trimpath removes local file paths and -s -w strip debug symbols.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/data-service ./cmd

# "nonroot" runs the process as an unprivileged user.
FROM gcr.io/distroless/static-debian12:nonroot
# transfer files from build stage into final image
COPY --from=build /out/data-service /data-service

# Documentation only: the service listens on PORT, which defaults to 8080.
EXPOSE 8080

ENTRYPOINT ["/data-service"]
