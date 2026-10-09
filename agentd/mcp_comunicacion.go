package main

import (
	"encoding/json"
	"fmt"
	"time"
)

// RegistrarComunicacion instala el grupo comunicacion (D).
// Enviar/llamar = Alto simulado: nunca se ejecutan en pruebas (R7).
func RegistrarComunicacion() {
	Registro["leer_notificaciones"] = Herramienta{
		Nombre: "leer_notificaciones", Riesgo: Bajo,
		Schema:  `{"type":"object","properties":{"limite":{"type":"integer","minimum":1,"maximum":20}},"additionalProperties":false}`,
		Timeout: 30 * time.Second, MaxOut: 64 * 1024,
		Ejecuta: func(raw json.RawMessage) (any, error) {
			out, err := runCapped(30*time.Second, 64*1024, "dumpsys", "notification")
			if err != nil {
				return nil, err
			}
			if len(out) > 32*1024 {
				out = out[:32*1024]
			}
			d := MarcarDato(out, "notificaciones")
			return map[string]string{"dato": d.Formatea()}, nil
		},
	}
	for _, n := range []string{"iniciar_llamada", "enviar_sms"} {
		n := n
		Registro[n] = Herramienta{
			Nombre: n, Riesgo: Alto,
			Schema:  `{"type":"object","properties":{"destino":{"type":"string"},"cuerpo":{"type":"string"}},"required":["destino"],"additionalProperties":false}`,
			Timeout: 30 * time.Second, MaxOut: 4096,
			Ejecuta: func(_ json.RawMessage) (any, error) {
				return nil, fmt.Errorf("riesgo alto: confirmar en la app")
			},
		}
	}
}
