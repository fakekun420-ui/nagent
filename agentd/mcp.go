package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
)

// PeticionRPC es un mensaje JSON-RPC 2.0 (Bloque D).
type PeticionRPC struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id"`
	Metodo  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
}

// RespuestaRPC es la respuesta JSON-RPC 2.0.
type RespuestaRPC struct {
	JSONRPC string  `json:"jsonrpc"`
	ID      any     `json:"id"`
	Result  any     `json:"result,omitempty"`
	Error   *ErrRPC `json:"error,omitempty"`
}

// ErrRPC es un error JSON-RPC 2.0.
type ErrRPC struct {
	Codigo  int    `json:"code"`
	Mensaje string `json:"mensaje"`
}

func respOK(id any, r any) RespuestaRPC { return RespuestaRPC{JSONRPC: "2.0", ID: id, Result: r} }
func respErr(id any, c int, m string) RespuestaRPC {
	return RespuestaRPC{JSONRPC: "2.0", ID: id, Error: &ErrRPC{Codigo: c, Mensaje: m}}
}

// DespacharRPC atiende initialize/tools/list/tools/call (D).
func DespacharRPC(p PeticionRPC) RespuestaRPC {
	switch p.Metodo {
	case "initialize":
		return respOK(p.ID, map[string]any{"nombre": "nagent", "version": "0.1.0", "protocolo": "2.0"})
	case "tools/list":
		return respOK(p.ID, CatalogoMCP())
	case "tools/call":
		var ll struct {
			Nombre string          `json:"nombre"`
			Args   json.RawMessage `json:"args"`
		}
		if err := json.Unmarshal(p.Params, &ll); err != nil {
			return respErr(p.ID, -32700, "params ilegibles")
		}
		h, ok := Registro[ll.Nombre]
		if !ok {
			return respErr(p.ID, -32601, "unknown_tool")
		}
		if RequiereConfirmacion(h.Riesgo) {
			return respOK(p.ID, map[string]any{"estado": "pendiente", "nota": "riesgo alto: confirmar en la app"})
		}
		res, err := h.Ejecuta(ll.Args)
		if err != nil {
			return respErr(p.ID, -32000, err.Error())
		}
		return respOK(p.ID, map[string]any{"ok": res})
	default:
		return respErr(p.ID, -32601, "metodo desconocido: "+p.Metodo)
	}
}

// CatalogoMCP serializa el registro con riesgo (R6).
func CatalogoMCP() []map[string]string {
	var c []map[string]string
	for _, h := range Registro {
		c = append(c, map[string]string{"nombre": h.Nombre, "riesgo": h.Riesgo.String(), "schema": h.Schema})
	}
	return c
}

// ManejarRPC es el handler POST /rpc (mismo auth Bearer que el resto).
func (s *Servidor) ManejarRPC(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "solo POST", http.StatusMethodNotAllowed)
		return
	}
	var p PeticionRPC
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 256*1024)).Decode(&p); err != nil {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(respErr(nil, -32700, "json ilegible"))
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(DespacharRPC(p))
}

// ServirStdio atiende una linea JSON por stdin (solo pruebas, sin token ni red).
func ServirStdio() {
	sc := bufio.NewScanner(os.Stdin)
	sc.Buffer(make([]byte, 256*1024), 256*1024)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	for sc.Scan() {
		var p PeticionRPC
		if err := json.Unmarshal(sc.Bytes(), &p); err != nil {
			b, _ := json.Marshal(respErr(nil, -32700, "json ilegible"))
			fmt.Fprintln(out, string(b))
			continue
		}
		b, _ := json.Marshal(DespacharRPC(p))
		fmt.Fprintln(out, string(b))
	}
}
