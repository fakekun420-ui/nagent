package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// Evento es una linea de auditoria JSONL (C6, R13). args sensibles solo como hash.
type Evento struct {
	TS        string `json:"ts"`
	Tool      string `json:"tool"`
	ArgsHash  string `json:"args_hash_sha256"`
	Resultado string `json:"result"`
	Origen    string `json:"origen"`
	Riesgo    string `json:"riesgo"`
	Decision  string `json:"decision"`
	Latencia  int64  `json:"latency_ms"`
	Sesion    string `json:"session_id"`
}

// Auditor escribe JSONL con rotacion por tamano (R14).
type Auditor struct {
	dir      string
	maxBytes int64
}

// NuevoAuditor crea el auditor sobre dir (0600 en ficheros).
func NuevoAuditor(dir string, maxBytes int64) *Auditor {
	if maxBytes <= 0 {
		maxBytes = 10 * 1024 * 1024
	}
	return &Auditor{dir: dir, maxBytes: maxBytes}
}

func hashArgs(args []byte) string {
	h := sha256.Sum256(args)
	return hex.EncodeToString(h[:])
}

// Registrar anade una linea. Nunca registra tokens ni cuerpos sensibles (R15):
// solo hashes y truncados.
func (a *Auditor) Registrar(ev Evento) error {
	if err := os.MkdirAll(a.dir, 0700); err != nil {
		return fmt.Errorf("dir auditoria: %w", err)
	}
	p := filepath.Join(a.dir, "audit.jsonl")
	if st, err := os.Stat(p); err == nil && st.Size() > a.maxBytes {
		if err := os.Rename(p, p+".1"); err != nil {
			return fmt.Errorf("rotar auditoria: %w", err)
		}
	}
	f, err := os.OpenFile(p, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return fmt.Errorf("abrir auditoria: %w", err)
	}
	defer f.Close()
	ev.TS = time.Now().UTC().Format(time.RFC3339)
	if ev.ArgsHash == "" {
		ev.ArgsHash = hashArgs(nil)
	}
	return json.NewEncoder(f).Encode(ev)
}
