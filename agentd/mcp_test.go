package main

import (
	"encoding/json"
	"strings"
	"testing"
)

// Todo sin red ni dispositivo: logica pura (Actions corre go test).

func TestRPCDesconocido(t *testing.T) {
	RegistrarBajoRiesgo()
	RegistrarSistema()
	r := DespacharRPC(PeticionRPC{JSONRPC: "2.0", ID: 1, Metodo: "tools/call",
		Params: json.RawMessage(`{"nombre":"no_existe","args":{}}`)})
	if r.Error == nil || r.Error.Codigo != -32601 {
		t.Fatalf("unknown_tool esperado, real %+v", r.Error)
	}
}

func TestRPCAltoEsPendiente(t *testing.T) {
	RegistrarApps()
	RegistrarComunicacion()
	RegistrarArchivos()
	for _, n := range []string{"forzar_detencion", "instalar_app", "iniciar_llamada", "enviar_sms", "borrar_archivo"} {
		r := DespacharRPC(PeticionRPC{JSONRPC: "2.0", ID: 1, Metodo: "tools/call",
			Params: json.RawMessage(`{"nombre":"` + n + `","args":{"paquete":"x"}}`)})
		if r.Error != nil {
			t.Fatalf("%s: error en vez de pendiente", n)
		}
		m, ok := r.Result.(map[string]any)
		if !ok || m["estado"] != "pendiente" {
			t.Fatalf("%s debe ser pendiente, real %v", n, r.Result)
		}
	}
}

func TestAllowlistSettings(t *testing.T) {
	if !esClaveSettings("system", "screen_brightness") {
		t.Fatal("screen_brightness debe estar permitida")
	}
	if esClaveSettings("secure", "android_id") {
		t.Fatal("android_id fuera de allowlist debe rechazarse")
	}
	if esClaveSettings("system", "../../x") {
		t.Fatal("traversal en clave debe rechazarse")
	}
}

func TestTraversalArchivos(t *testing.T) {
	for _, p := range []string{
		"/sdcard/../../data/privado",
		"/data/data/com.otro/files/x",
		"/etc/passwd",
		"/data/adb/nagent/../../modules/x",
	} {
		if _, err := resolverRuta(p); err == nil {
			t.Fatalf("traversal aceptado: %s", p)
		}
	}
	if _, err := resolverRuta("/sdcard/legitimo/nota.txt"); err != nil {
		t.Fatalf("ruta legitima rechazada: %v", err)
	}
}

func TestPaquete(t *testing.T) {
	if !esPaquete("com.ejemplo.app") {
		t.Fatal("paquete valido rechazado")
	}
	if esPaquete("com.ejemplo;rm -rf") {
		t.Fatal("paquete con shell aceptado")
	}
	if esPaquete("") {
		t.Fatal("paquete vacio aceptado")
	}
}

func TestCatalogoTraeRiesgo(t *testing.T) {
	RegistrarBajoRiesgo()
	c := CatalogoMCP()
	if len(c) == 0 {
		t.Fatal("catalogo vacio")
	}
	for _, e := range c {
		if e["riesgo"] == "" || e["nombre"] == "" {
			t.Fatalf("entrada sin riesgo/nombre: %v", e)
		}
	}
}

func TestDatoDelimitadoMemoria(t *testing.T) {
	d := MarcarDato("hola", "archivo:/sdcard/x.txt")
	if !strings.HasPrefix(d.Formatea(), "<untrusted") {
		t.Fatal("sin delimitador untrusted")
	}
}
