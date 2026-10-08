// Package main es agentd: daemon local del telefono (Bloque C del plan).
// Compila estatico: GOOS=linux GOARCH=arm64 CGO_ENABLED=0 (modernc.org/sqlite).
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"os"
)

// VerificarSHA devuelve nil si el fichero existe y su sha256 coincide.
func VerificarSHA(path, hexEsperado string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("abrir %s: %w", path, err)
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return fmt.Errorf("leer %s: %w", path, err)
	}
	real := hex.EncodeToString(h.Sum(nil))
	if real != hexEsperado {
		return fmt.Errorf("integrity_fail %s esperado=%s real=%s", path, hexEsperado, real)
	}
	return nil
}

func main() {
	cfg := MustCargar("config.yaml")
	if err := VerificarSHA(cfg.Binarios.LlamaServer, cfg.Binarios.ShaLlama); err != nil {
		log.Fatalf("integridad: %v", err)
	}
	if err := VerificarSHA(cfg.Binarios.Modelo, cfg.Binarios.ShaModelo); err != nil {
		log.Fatalf("integridad: %v", err)
	}
	srv := NuevoServidor(cfg)
	log.Fatal(srv.Escuchar())
}
