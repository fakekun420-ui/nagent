package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"
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
// Registra tools/call en la auditoria global (C6); sin auditor no falla.
func DespacharRPC(p PeticionRPC) (out RespuestaRPC) {
	t0 := time.Now()
	ev := Evento{Origen: "loopback", Decision: "denegada", Resultado: "metodo desconocido"}
	argsJSON := p.Params
	defer func() {
		ev.Latencia = time.Since(t0).Milliseconds()
		ev.ArgsHash = hashArgs(argsJSON)
		if auditorGlobal != nil {
			_ = auditorGlobal.Registrar(ev)
		}
	}()
	switch p.Metodo {
	case "initialize":
		ev.Decision = "ejecutada"
		ev.Resultado = "ok"
		out = respOK(p.ID, map[string]any{"nombre": "nagent", "version": "0.1.0", "protocolo": "2.0"})
	case "tools/list":
		ev.Decision = "ejecutada"
		ev.Resultado = "ok"
		out = respOK(p.ID, CatalogoMCP())
	case "tools/call":
		var ll struct {
			Nombre string          `json:"nombre"`
			Args   json.RawMessage `json:"args"`
		}
		if err := json.Unmarshal(p.Params, &ll); err != nil {
			ev.Resultado = "params ilegibles"
			out = respErr(p.ID, -32700, "params ilegibles")
			return
		}
		ev.Tool = ll.Nombre
		argsJSON = ll.Args
		h, ok := Registro[ll.Nombre]
		if !ok {
			ev.Resultado = "unknown_tool"
			out = respErr(p.ID, -32601, "unknown_tool")
			return
		}
		ev.Riesgo = h.Riesgo.String()
		if RequiereConfirmacion(h.Riesgo) {
			ev.Decision = "pendiente"
			ev.Resultado = "pendiente"
			out = respOK(p.ID, map[string]any{"estado": "pendiente", "nota": "riesgo alto: confirmar en la app"})
			return
		}
		res, err := h.Ejecuta(ll.Args)
		if err != nil {
			ev.Decision = "ejecutada"
			msg := err.Error()
			if len(msg) > 120 {
				msg = msg[:120]
			}
			ev.Resultado = "error: " + msg
			out = respErr(p.ID, -32000, err.Error())
			return
		}
		ev.Decision = "ejecutada"
		ev.Resultado = "ok"
		out = respOK(p.ID, map[string]any{"ok": res})
	default:
		out = respErr(p.ID, -32601, "metodo desconocido: "+p.Metodo)
	}
	return
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
