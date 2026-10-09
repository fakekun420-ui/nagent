package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

// Herramienta es una funcion tipada con schema. Sin shell generica (R18):
// solo existe tras --unsafe, desactivado por defecto.
type Herramienta struct {
	Nombre  string
	Riesgo  Nivel
	Schema  string
	Timeout time.Duration
	MaxOut  int
	Ejecuta func(args json.RawMessage) (any, error)
}

// Registro de herramientas de riesgo bajo (v0.1.0).
var Registro = map[string]Herramienta{}

// RegistrarBajoRiesgo instala las 3 herramientas iniciales.
func RegistrarBajoRiesgo() {
	Registro["estado_bateria"] = Herramienta{
		Nombre: "estado_bateria", Riesgo: Bajo,
		Schema:  `{"type":"object","properties":{},"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: toolBateria,
	}
	Registro["listar_apps"] = Herramienta{
		Nombre: "listar_apps", Riesgo: Bajo,
		Schema:  `{"type":"object","properties":{"filtro":{"type":"string"}},"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: toolApps,
	}
	Registro["leer_memoria"] = Herramienta{
		Nombre: "leer_memoria", Riesgo: Bajo,
		Schema:  `{"type":"object","properties":{"dominio":{"type":"string","enum":["user","agent"]},"clave":{"type":"string"}},"required":["dominio","clave"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: toolMemoria,
	}
}

func runCapped(timeout time.Duration, maxOut int, name string, arg ...string) (string, error) {
	cmd := exec.Command(name, arg...)
	type res struct {
		out string
		err error
	}
	ch := make(chan res, 1)
	go func() {
		b, err := cmd.Output()
		if len(b) > maxOut {
			b = b[:maxOut]
		}
		ch <- res{string(b), err}
	}()
	select {
	case r := <-ch:
		return r.out, r.err
	case <-time.After(timeout):
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
		return "", fmt.Errorf("timeout tras %s", timeout)
	}
}

func toolBateria(_ json.RawMessage) (any, error) {
	out, err := runCapped(30*time.Second, 64*1024, "dumpsys", "battery")
	if err != nil {
		return nil, err
	}
	return map[string]string{"salida": strings.TrimSpace(out)}, nil
}

func toolApps(args json.RawMessage) (any, error) {
	var a struct {
		Filtro string `json:"filtro"`
	}
	if len(args) > 0 {
		if err := json.Unmarshal(args, &a); err != nil {
			return nil, fmt.Errorf("args: %w", err)
		}
	}
	out, err := runCapped(30*time.Second, 64*1024, "pm", "list", "packages")
	if err != nil {
		return nil, err
	}
	if a.Filtro == "" {
		return map[string]string{"salida": strings.TrimSpace(out)}, nil
	}
	var keep []string
	for _, l := range strings.Split(out, "\n") {
		if strings.Contains(l, a.Filtro) {
			keep = append(keep, l)
		}
	}
	return map[string]string{"salida": strings.Join(keep, "\n")}, nil
}

func toolMemoria(args json.RawMessage) (any, error) {
	return MemoriaLeer(args)
}

// ListaJSON serializa el catalogo con riesgo (R6).
func ListaJSON() string {
	type item struct {
		Nombre string `json:"nombre"`
		Riesgo string `json:"riesgo"`
		Schema string `json:"schema"`
	}
	var l []item
	for _, h := range Registro {
		l = append(l, item{h.Nombre, h.Riesgo.String(), h.Schema})
	}
	b, _ := json.Marshal(l)
	return string(b)
}

// Despachar valida riesgo alto (siempre pendiente, R7) y ejecuta lo demas.
func Despachar(r *http.Request) string {
	var ll struct {
		Nombre string          `json:"nombre"`
		Args   json.RawMessage `json:"args"`
	}
	b, err := io.ReadAll(io.LimitReader(r.Body, 65*1024))
	if err != nil {
		return `{"error":"peticion ilegible"}`
	}
	if len(b) >= 65*1024 {
		return `{"error":"peticion demasiado grande"}`
	}
	if err := json.Unmarshal(b, &ll); err != nil {
		return `{"error":"peticion ilegible"}`
	}
	h, ok := Registro[ll.Nombre]
	if !ok {
		return `{"error":"unknown_tool"}`
	}
	if RequiereConfirmacion(h.Riesgo) {
		return `{"estado":"pendiente","nota":"riesgo alto: confirmar en la app"}`
	}
	res, err := h.Ejecuta(ll.Args)
	if err != nil {
		return fmt.Sprintf(`{"error":%q}`, err.Error())
	}
	b, _ := json.Marshal(map[string]any{"ok": res})
	return string(b)
}
