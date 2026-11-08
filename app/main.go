// Command data-service is a small HTTP service.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

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

// handleData returns the account id from the path with a timestamp and data.
func (s *server) handleData(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(dataResponse{
		AccountID: r.PathValue("accountId"),
		Timestamp: s.now().UTC().Unix(),
		Data:      s.data(),
	})
}

func main() {
	s := &server{
		now:  time.Now,
		data: func() string { return "placeholder" }, // TODO: Remove placeholder and add real random data
	}

	srv := &http.Server{
		Addr:              ":8080",
		Handler:           newHandler(s),
		ReadHeaderTimeout: 5 * time.Second, // Without a header timeout a slow client can hold a connection open forever.
	}

	log.Printf("listening on %s", srv.Addr)
	log.Fatal(srv.ListenAndServe())
}
