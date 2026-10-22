package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"syscall"
	"time"
)

const (
	listenAddr       = "127.0.0.1:35001"
	responseFile     = "saml-response.txt"
	maxSAMLBodyBytes = 4 << 20
)

const successHTML = `<!DOCTYPE html>
<html>
<head><title>Authentication Successful</title></head>
<body style="font-family: sans-serif; text-align: center; padding-top: 50px;">
    <h2>Authentication Successful</h2>
    <p>You can now safely close this window.</p>
    <script>
        setTimeout(function() { window.close(); }, 2000);
    </script>
</body>
</html>`

func main() {
	done := make(chan struct{}, 1)
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		SAMLServer(w, r, done)
	})

	server := &http.Server{
		Addr:              listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		select {
		case <-done:
			log.Println("SAMLResponse received, shutting down server.")
		case sig := <-sigs:
			log.Printf("Received signal %v, shutting down server.", sig)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(ctx); err != nil {
			log.Printf("HTTP server shutdown failed: %v", err)
		}
	}()

	log.Printf("Starting HTTP server at %s", listenAddr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("HTTP server failed: %v", err)
	}
}

func SAMLServer(w http.ResponseWriter, r *http.Request, done chan<- struct{}) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	switch r.Method {
	case "POST":
		r.Body = http.MaxBytesReader(w, r.Body, maxSAMLBodyBytes)
		if err := r.ParseForm(); err != nil {
			http.Error(w, fmt.Sprintf("failed to parse form: %v", err), http.StatusBadRequest)
			return
		}
		SAMLResponse := r.FormValue("SAMLResponse")
		if len(SAMLResponse) == 0 {
			log.Printf("SAMLResponse field is empty or missing")
			http.Error(w, "SAMLResponse field is empty or missing", http.StatusBadRequest)
			return
		}

		if err := os.WriteFile(responseFile, []byte(url.QueryEscape(SAMLResponse)), 0600); err != nil {
			log.Printf("failed to write %s: %v", responseFile, err)
			http.Error(w, "failed to save SAMLResponse", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, successHTML)
		log.Printf("Got SAMLResponse field and saved it to the %s file", responseFile)

		select {
		case done <- struct{}{}:
		default:
		}
		return
	default:
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, fmt.Sprintf("POST method expected, %s received", r.Method), http.StatusMethodNotAllowed)
	}
}
