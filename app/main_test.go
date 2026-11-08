package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// testServer returns a server with a fixed clock and fixed data,
// so responses can be compared exactly.
func testServer() *server {
	return &server{
		now:  func() time.Time { return time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC) },
		data: func() string { return "deadbeef" },
	}
}

// do sends a request straight to the handler, without a network.
func do(method, path string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	newHandler(testServer()).ServeHTTP(rec, httptest.NewRequest(method, path, nil))
	return rec
}

func TestHealthz(t *testing.T) {
	rec := do(http.MethodGet, "/healthz")

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if body := rec.Body.String(); body != "ok" {
		t.Errorf("body = %q, want %q", body, "ok")
	}
}

func TestHealthzRejectsOtherMethods(t *testing.T) {
	rec := do(http.MethodPost, "/healthz")

	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
}

func TestData(t *testing.T) {
	rec := do(http.MethodGet, "/acme/data")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("Content-Type = %q, want application/json", ct)
	}
	// Comparing the exact text also checks field names and their order.
	want := `{"accountId":"acme","timestamp":1767323045,"data":"deadbeef"}`
	if body := strings.TrimSpace(rec.Body.String()); body != want {
		t.Errorf("body = %s, want %s", body, want)
	}
}

func TestDataRejectsOtherMethods(t *testing.T) {
	rec := do(http.MethodPost, "/acme/data")

	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
}

func TestUnknownPathIsNotFound(t *testing.T) {
	rec := do(http.MethodGet, "/acme/other")

	if rec.Code != http.StatusNotFound {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}
