package main

import (
	"crypto/subtle"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Servidor expone herramientas por HTTP solo en loopback con Bearer (C2).
type Servidor struct {
	cfg   Config
	token string
	mux   *http.ServeMux
	rate  map[string][]time.Time
}

// CargarToken lee el token una vez al arrancar (0600, solo root/app).
func CargarToken(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("leer token %s: %w", path, err)
	}
	t := strings.TrimSpace(string(b))
	if len(t) < 32 {
		return "", fmt.Errorf("token demasiado corto (%d)", len(t))
	}
	return t, nil
}

// NuevoServidor registra rutas. Sin token valido no hay servidor.
func NuevoServidor(cfg Config) *Servidor {
	tok, err := CargarToken(cfg.Auth.TokenPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "auth:", err)
		os.Exit(2)
	}
	s := &Servidor{cfg: cfg, token: tok, mux: http.NewServeMux(), rate: map[string][]time.Time{}}
	RegistrarBajoRiesgo()
	RegistrarSistema()
	RegistrarApps()
	RegistrarComunicacion()
	RegistrarArchivos()
	FijarAuditor(NuevoAuditor(filepath.Join(filepath.Dir(cfg.Auth.TokenPath), "logs"), 10*1024*1024))
	s.mux.Handle("/health", s.auth(http.HandlerFunc(s.salud)))
	s.mux.Handle("/tools/list", s.auth(http.HandlerFunc(s.lista)))
	s.mux.Handle("/tools/call", s.auth(http.HandlerFunc(s.llamar)))
	s.mux.Handle("/rpc", s.auth(http.HandlerFunc(s.ManejarRPC)))
	return s
}

func (s *Servidor) bearerOK(r *http.Request) bool {
	got := r.Header.Get("Authorization")
	want := "Bearer " + s.token
	if len(got) != len(want) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}

// auth rechaza con 401 sin cuerpo util ante token ausente o erroneo (R4).
func (s *Servidor) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.bearerOK(r) {
			http.Error(w, "rechazado", http.StatusUnauthorized)
			return
		}
		if !s.permite(r.RemoteAddr) {
			http.Error(w, "rechazado", http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// permite aplica rate-limit simple: 60 req/min por cliente (R20).
func (s *Servidor) permite(remoto string) bool {
	ahora := time.Now()
	corte := ahora.Add(-time.Minute)
	v := s.rate[remoto][:0]
	for _, t := range s.rate[remoto] {
		if t.After(corte) {
			v = append(v, t)
		}
	}
	if len(v) >= 60 {
		s.rate[remoto] = v
		return false
	}
	s.rate[remoto] = append(v, ahora)
	return true
}

// Escuchar solo ata 127.0.0.1 (R1): LAN no responde.
func (s *Servidor) Escuchar() error {
	ln, err := net.Listen("tcp", "127.0.0.1:8765")
	if err != nil {
		return fmt.Errorf("escuchar 127.0.0.1:8765: %w", err)
	}
	return http.Serve(ln, s.mux)
}

func (s *Servidor) salud(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, `{"ok":true}`)
}

func (s *Servidor) lista(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintln(w, ListaJSON())
}

func (s *Servidor) llamar(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintln(w, Despachar(r))
}
