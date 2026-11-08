// Command data-service is a small HTTP service.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"regexp"
	"syscall"
	"time"
)

// accountIDPattern is what we accept as an account id
var accountIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// server holds what the handlers depend on. The clock and the data source are
// fields so tests can replace them with fixed values.
type server struct {
	now  func() time.Time
	data func() string
}

// dataResponse is the JSON body returned by GET /{accountId}/data.
type dataResponse struct {
	AccountID string `json:"accountId"`
	Timestamp int64  `json:"timestamp"`
	Data      string `json:"data"`
}

// newHandler returns the HTTP handler with all routes registered.
func newHandler(s *server) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handleHealth)
	mux.HandleFunc("GET /{accountId}/data", s.handleData)

	return mux
}

// handleHealth tells the load balancer and humans that the process is alive.
func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

// handleData returns the account id from the path with a timestamp and data (400 if the account id has an unexpected format)
func (s *server) handleData(w http.ResponseWriter, r *http.Request) {
	accountID := r.PathValue("accountId")
	if !accountIDPattern.MatchString(accountID) {
		http.Error(w, "invalid account id", http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(dataResponse{
		AccountID: accountID,
		Timestamp: s.now().UTC().Unix(),
		Data:      s.data(),
	})
}

// randomHex returns 16 random bytes as a 32 character hex string.
func randomHex() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// run serves h on ln until ctx is cancelled, then shuts down gracefully:
// it stops accepting new connections and gives requests that are already running up to 10 seconds to finish.
func run(ctx context.Context, ln net.Listener, h http.Handler) error {
	srv := &http.Server{
		Handler:           h,
		ReadHeaderTimeout: 5 * time.Second, // Without a header timeout a slow client can hold a connection open forever.
	}

	errCh := make(chan error, 1)
	go func() { errCh <- srv.Serve(ln) }()

	select {
	case err := <-errCh:
		return err // The server failed on its own.
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}

// envOr returns the value of the environment variable key, or fallback if it is empty.
func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	// Logs are JSON on stdout, which is where a container platform collects them.
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	s := &server{
		now:  time.Now,
		data: randomHex,
	}

	addr := ":" + envOr("PORT", "8080")
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		slog.Error("listen failed", "err", err)
		os.Exit(1)
	}

	// ctx is cancelled on Ctrl+C or SIGTERM, which is what ECS sends to stop a task.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	slog.Info("listening", "addr", addr)
	if err := run(ctx, ln, newHandler(s)); err != nil {
		slog.Error("server failed", "err", err)
		os.Exit(1)
	}
	slog.Info("stopped")
}
