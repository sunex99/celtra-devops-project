// Command data-service is a small HTTP service.
package main

import (
	"log"
	"net/http"
	"time"
)

// newHandler returns the HTTP handler with all routes registered.
func newHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handleHealth)

	return mux
}

// handleHealth tells the load balancer and humans that the process is alive.
func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func main() {
	srv := &http.Server{
		Addr:              ":8080",
		Handler:           newHandler(),
		ReadHeaderTimeout: 5 * time.Second, // Without a header timeout a slow client can hold a connection open forever.
	}

	log.Printf("listening on %s", srv.Addr)
	log.Fatal(srv.ListenAndServe())
}
