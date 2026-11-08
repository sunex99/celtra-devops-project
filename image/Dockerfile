FROM golang:1.27-alpine@sha256:fa3d596898d9f126af7c01d14ee7597bab3f39cccf392ef36b69fe77cd681f18 AS build
WORKDIR /src

COPY go.mod ./
RUN go mod download
COPY cmd/ ./cmd/

# CGO_ENABLED=0 produces a fully static binary, which the minimal runtime image needs. -trimpath removes local file paths and -s -w strip debug symbols.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/data-service ./cmd

# "nonroot" runs the process as an unprivileged user.
FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
# transfer files from build stage into final image
COPY --from=build /out/data-service /data-service

# Documentation only: the service listens on PORT, which defaults to 8080.
EXPOSE 8080

ENTRYPOINT ["/data-service"]
