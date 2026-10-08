package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Raices permitidas del grupo archivos (D). Nada fuera de aqui.
var raicesArchivos = []string{"/sdcard/", "/data/adb/nagent/workspace/"}

// resolverRuta limpia, resuelve symlinks y exige prefijo permitido.
// Rechaza traversal, escapes y rutas absolutas fuera de raiz (R12).
func resolverRuta(ruta string) (string, error) {
	if ruta == "" || len(ruta) > 1024 {
		return "", fmt.Errorf("ruta invalida")
	}
	limpia := filepath.Clean(ruta)
	if !filepath.IsAbs(limpia) {
		return "", fmt.Errorf("solo rutas absolutas")
	}
	real, err := filepath.EvalSymlinks(limpia)
	if err != nil {
		// Si no existe aun (escritura nueva), valida el padre.
		real = limpia
	}
	for _, r := range raicesArchivos {
		if strings.HasPrefix(real+string(os.PathSeparator), r) || real == strings.TrimSuffix(r, "/") {
			return limpia, nil
		}
	}
	return "", fmt.Errorf("ruta fuera de raices permitidas")
}

// RegistrarArchivos instala el grupo archivos (D). Sin shell: Go os.
// borrar_archivo = Alto simulado (moveria a cuarentena en diseno real).
func RegistrarArchivos() {
	Registro["archivos_listar"] = Herramienta{
		Nombre: "archivos_listar", Riesgo: Bajo,
		Schema: `{"type":"object","properties":{"ruta":{"type":"string"},"limite":{"type":"integer","minimum":1,"maximum":200}},"required":["ruta"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				Ruta   string `json:"ruta"`
				Limite int    `json:"limite"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			p, err := resolverRuta(a.Ruta)
			if err != nil {
				return nil, err
			}
			ents, err := os.ReadDir(p)
			if err != nil {
				return nil, err
			}
			if a.Limite <= 0 {
				a.Limite = 200
			}
			var nombres []string
			for i, e := range ents {
				if i >= a.Limite {
					break
				}
				nombres = append(nombres, e.Name())
			}
			return map[string]any{"entradas": nombres}, nil
		},
	}
	Registro["archivos_leer"] = Herramienta{
		Nombre: "archivos_leer", Riesgo: Bajo,
		Schema: `{"type":"object","properties":{"ruta":{"type":"string"},"max_bytes":{"type":"integer","minimum":1,"maximum":262144}},"required":["ruta"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				Ruta     string `json:"ruta"`
				MaxBytes int    `json:"max_bytes"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			p, err := resolverRuta(a.Ruta)
			if err != nil {
				return nil, err
			}
			if a.MaxBytes <= 0 {
				a.MaxBytes = 262144
			}
			b, err := os.ReadFile(p)
			if err != nil {
				return nil, err
			}
			if len(b) > a.MaxBytes {
				b = b[:a.MaxBytes]
			}
			d := MarcarDato(string(b), "archivo:"+p)
			return map[string]string{"dato": d.Formatea()}, nil
		},
	}
	Registro["archivos_escribir"] = Herramienta{
		Nombre: "archivos_escribir", Riesgo: Medio,
		Schema: `{"type":"object","properties":{"ruta":{"type":"string"},"contenido":{"type":"string"}},"required":["ruta","contenido"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 4096,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				Ruta      string `json:"ruta"`
				Contenido string `json:"contenido"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			if len(a.Contenido) > 1024*1024 {
				return nil, fmt.Errorf("contenido > 1MB")
			}
			p, err := resolverRuta(a.Ruta)
			if err != nil {
				return nil, err
			}
			// Atomico: tmp + fsync + rename (nunca in-situ sobre FUSE).
			tmp := p + ".tmp-nagent"
			f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
			if err != nil {
				return nil, err
			}
			if _, err := f.WriteString(a.Contenido); err != nil {
				f.Close()
				return nil, err
			}
			if err := f.Sync(); err != nil {
				f.Close()
				return nil, err
			}
			f.Close()
			if err := os.Rename(tmp, p); err != nil {
				os.Remove(tmp)
				return nil, err
			}
			return map[string]int{"bytes": len(a.Contenido)}, nil
		},
	}
	Registro["remember"] = Herramienta{
		Nombre: "remember", Riesgo: Medio,
		Schema: `{"type":"object","properties":{"dominio":{"type":"string","enum":["user","agent"]},"clave":{"type":"string"},"valor":{"type":"string"}},"required":["dominio","clave","valor"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 4096,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			var a struct {
				Dominio string `json:"dominio"`
				Clave   string `json:"clave"`
				Valor   string `json:"valor"`
			}
			if err := json.Unmarshal(raw, &a); err != nil {
				return nil, fmt.Errorf("args: %w", err)
			}
			if len(a.Valor) > 4096 {
				return nil, fmt.Errorf("valor > 4KB")
			}
			if memGlobal == nil {
				return nil, fmt.Errorf("memoria no abierta")
			}
			if err := memGlobal.Guardar(a.Dominio, a.Clave, a.Valor); err != nil {
				return nil, err
			}
			return map[string]bool{"ok": true}, nil
		},
	}
	Registro["borrar_archivo"] = Herramienta{
		Nombre: "borrar_archivo", Riesgo: Alto,
		Schema: `{"type":"object","properties":{"ruta":{"type":"string"}},"required":["ruta"],"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 4096,
		Ejecuta: func(_ json.RawMessage) (any, error) {
			return nil, fmt.Errorf("riesgo alto: confirmar en la app")
		},
	}
}
