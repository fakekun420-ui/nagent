package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// RegistrarApps instala el grupo apps (D). Accion Alto = solo pendiente.
func RegistrarApps() {
	Registro["lanzar_app"] = Herramienta{
		Nombre: "lanzar_app", Riesgo: Medio,
		Schema: `{"type":"object","properties":{"paquete":{"type":"string"},"actividad":{"type":"string"}},"required":["paquete"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				Paquete   string `json:"paquete"`
				Actividad string `json:"actividad"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			if !esPaquete(a.Paquete) {
				return nil, fmt.Errorf("paquete invalido")
			}
			dest := a.Paquete
			if a.Actividad != "" {
				if !esPaquete(a.Actividad) {
					return nil, fmt.Errorf("actividad invalida")
				}
				dest = a.Paquete + "/" + a.Actividad
			}
			out, err := runCapped(30*time.Second, 64*1024, "am", "start", "-n", dest)
			if err != nil {
				return nil, err
			}
			return map[string]string{"salida": strings.TrimSpace(out)}, nil
		},
	}
	Registro["abrir_url"] = Herramienta{
		Nombre: "abrir_url", Riesgo: Medio,
		Schema: `{"type":"object","properties":{"url":{"type":"string"}},"required":["url"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				URL string `json:"url"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			if !strings.HasPrefix(a.URL, "https://") && !strings.HasPrefix(a.URL, "http://") {
				return nil, fmt.Errorf("solo esquemas http/https")
			}
			out, err := runCapped(30*time.Second, 64*1024, "am", "start", "-a", "android.intent.action.VIEW", "-d", a.URL)
			if err != nil {
				return nil, err
			}
			return map[string]string{"salida": strings.TrimSpace(out)}, nil
		},
	}
	Registro["ui_tecla"] = Herramienta{
		Nombre: "ui_tecla", Riesgo: Medio,
		Schema: `{"type":"object","properties":{"codigo":{"type":"string"}},"required":["codigo"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 4096,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				Codigo string `json:"codigo"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			if a.Codigo == "" || len(a.Codigo) > 32 {
				return nil, fmt.Errorf("codigo invalido")
			}
			out, err := runCapped(30*time.Second, 4096, "input", "keyevent", a.Codigo)
			if err != nil {
				return nil, err
			}
			return map[string]string{"salida": strings.TrimSpace(out)}, nil
		},
	}
	// Riesgo alto: registradas para que existan en tools/list, pero
	// DespacharRPC jamas las ejecuta (devuelve pendiente, R7).
	for _, n := range []string{"forzar_detencion", "instalar_app"} {
		n := n
		Registro[n] = Herramienta{
			Nombre: n, Riesgo: Alto,
			Schema:  `{"type":"object","properties":{"paquete":{"type":"string"}},"required":["paquete"],"additionalProperties":false}`,
			Timeout: 30 * time.Second, MaxOut: 4096,
			Ejecuta: func(_ json.RawMessage) (any, error) {
				return nil, fmt.Errorf("riesgo alto: confirmar en la app")
			},
		}
	}
}

// esPaquete valida nombre de paquete/actividad (letras, digitos, punto, guion).
func esPaquete(s string) bool {
	if s == "" || len(s) > 256 {
		return false
	}
	for _, r := range s {
		if !(r == '.' || r == '_' || r == '-' || r == '/' ||
			(r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')) {
			return false
		}
	}
	return true
}
