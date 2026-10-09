package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// La auditoria registra cada decision con hash de args, nunca valores (R15).
func TestAuditoriaRegistraYOcultaArgs(t *testing.T) {
	RegistrarBajoRiesgo()
	RegistrarSistema()
	dir := t.TempDir()
	FijarAuditor(NuevoAuditor(dir, 1024*1024))
	defer FijarAuditor(nil)
	args := `{"clave":"SECRETA"}`
	_ = DespacharRPC(PeticionRPC{JSONRPC: "2.0", ID: 1, Metodo: "tools/call",
		Params: json.RawMessage(`{"nombre":"no_existe","args":` + args + `}`)})
	b, err := os.ReadFile(filepath.Join(dir, "audit.jsonl"))
	if err != nil {
		t.Fatalf("sin linea de auditoria: %v", err)
	}
	linea := string(b)
	if !strings.Contains(linea, `"tool":"no_existe"`) {
		t.Fatalf("sin tool en linea: %s", linea)
	}
	if strings.Contains(linea, "SECRETA") {
		t.Fatal("args en claro en auditoria (R15)")
	}
	sum := sha256.Sum256([]byte(args))
	if !strings.Contains(linea, hex.EncodeToString(sum[:])) {
		t.Fatalf("sin args_hash correcto: %s", linea)
	}
}
