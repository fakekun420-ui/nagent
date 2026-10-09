package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// allowSettings es la allowlist de claves legibles (D grupo sistema).
var allowSettings = map[string]bool{
	"system:screen_brightness":      true,
	"system:screen_brightness_mode": true,
	"system:screen_off_timeout":     true,
	"global:airplane_mode_on":       true,
	"global:zen_mode":               true,
	"secure:default_input_method":   true,
}

// RegistrarSistema instala el grupo sistema (lectura Bajo, cambios Medio).
func RegistrarSistema() {
	Registro["estado_sistema"] = Herramienta{
		Nombre: "estado_sistema", Riesgo: Bajo,
		Schema:  `{"type":"object","properties":{},"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: func(_ json.RawMessage) (any, error) {
			out, err := runCapped(30*time.Second, 64*1024, "dumpsys", "power")
			if err != nil {
				return nil, err
			}
			return map[string]string{"salida": strings.TrimSpace(out)}, nil
		},
	}
	Registro["ajuste_get"] = Herramienta{
		Nombre: "ajuste_get", Riesgo: Bajo,
		Schema:  `{"type":"object","properties":{"ns":{"type":"string","enum":["system","secure","global"]},"key":{"type":"string"}},"required":["ns","key"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				NS  string `json:"ns"`
				Key string `json:"key"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			if !esClaveSettings(a.NS, a.Key) {
				return nil, fmt.Errorf("clave fuera de allowlist: %s:%s", a.NS, a.Key)
			}
			out, err := runCapped(30*time.Second, 4096, "settings", "get", a.NS, a.Key)
			if err != nil {
				return nil, err
			}
			return map[string]string{"valor": strings.TrimSpace(out)}, nil
		},
	}
	Registro["brillo_set"] = Herramienta{
		Nombre: "brillo_set", Riesgo: Medio,
		Schema:  `{"type":"object","properties":{"valor":{"type":"integer","minimum":0,"maximum":255}},"required":["valor"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 4096,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				Valor int `json:"valor"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			if a.Valor < 0 || a.Valor > 255 {
				return nil, fmt.Errorf("brillo fuera de rango 0-255")
			}
			if _, err := runCapped(30*time.Second, 4096, "settings", "put", "system", "screen_brightness_mode", "0"); err != nil {
				return nil, err
			}
			out, err := runCapped(30*time.Second, 4096, "settings", "put", "system", "screen_brightness", fmt.Sprint(a.Valor))
			if err != nil {
				return nil, err
			}
			return map[string]string{"salida": strings.TrimSpace(out)}, nil
		},
	}
	Registro["volumen_tecla"] = Herramienta{
		Nombre: "volumen_tecla", Riesgo: Medio,
		Schema:  `{"type":"object","properties":{"dir":{"type":"string","enum":["subir","bajar"]},"pasos":{"type":"integer","minimum":1,"maximum":5}},"required":["dir"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 4096,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				Dir   string `json:"dir"`
				Pasos int    `json:"pasos"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			cod := "24"
			if a.Dir == "bajar" {
				cod = "25"
			}
			if a.Pasos < 1 {
				a.Pasos = 1
			}
			if a.Pasos > 5 {
				a.Pasos = 5
			}
			for i := 0; i < a.Pasos; i++ {
				if _, err := runCapped(30*time.Second, 4096, "input", "keyevent", cod); err != nil {
					return nil, err
				}
			}
			return map[string]int{"pasos": a.Pasos}, nil
		},
	}
}

// esClaveSettings dice si ns:key esta en allowlist de lectura.
func esClaveSettings(ns, key string) bool {
	return allowSettings[ns+":"+key]
}
