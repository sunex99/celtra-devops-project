package main

import (
	"encoding/hex"
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

func TestRandomHex(t *testing.T) {
	got := randomHex()

	if len(got) != 32 {
		t.Errorf("len = %d, want 32", len(got))
	}
	if _, err := hex.DecodeString(got); err != nil {
		t.Errorf("%q is not valid hex: %v", got, err)
	}
}

func TestRandomHexDiffersBetweenCalls(t *testing.T) {
	if a, b := randomHex(), randomHex(); a == b {
		t.Errorf("two calls returned the same value %q", a)
	}
}

func TestDataAcceptsValidAccountIDs(t *testing.T) {
	for _, id := range []string{"a", "acme-42", "ACME_42", strings.Repeat("a", 64)} {
		if rec := do(http.MethodGet, "/"+id+"/data"); rec.Code != http.StatusOK {
			t.Errorf("account id %q: status = %d, want %d", id, rec.Code, http.StatusOK)
		}
	}
}

func TestDataRejectsInvalidAccountIDs(t *testing.T) {
	invalid := map[string]string{
		"space":    "has%20space",
		"dot":      "a.b",
		"html":     "%3Cscript%3E",
		"slash":    "a%2Fb",
		"too long": strings.Repeat("a", 65),
	}
	for name, id := range invalid {
		t.Run(name, func(t *testing.T) {
			rec := do(http.MethodGet, "/"+id+"/data")

			if rec.Code != http.StatusBadRequest {
				t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
			}
			if strings.Contains(rec.Body.String(), "accountId") {
				t.Errorf("error response should not contain a data body, got %q", rec.Body.String())
			}
		})
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
