package main

// Nivel de riesgo de una herramienta (C4). Alto = confirmacion humana
// obligatoria en la app, sin excepcion (R6-R9).
type Nivel int

const (
	Bajo Nivel = iota
	Medio
	Alto
)

func (n Nivel) String() string {
	switch n {
	case Bajo:
		return "bajo"
	case Medio:
		return "medio"
	default:
		return "alto"
	}
}

// Clasificar devuelve el nivel de una herramienta del Registro.
func Clasificar(nombre string) Nivel {
	if h, ok := Registro[nombre]; ok {
		return h.Riesgo
	}
	return Alto // desconocido = alto por defecto (fail-closed)
}

// RequiereConfirmacion: solo Alto confirma, siempre (R7).
func RequiereConfirmacion(n Nivel) bool { return n == Alto }

// Acciones de riesgo alto (lista cerrada, R6).
var accionesAltas = []string{
	"enviar_sms", "iniciar_llamada", "borrar_archivo",
	"instalar_app", "forzar_detencion", "enviar_dinero",
}

// EsAlto dice si un nombre pertenece a la lista cerrada de riesgo alto.
func EsAlto(nombre string) bool {
	for _, a := range accionesAltas {
		if a == nombre {
			return true
		}
	}
	return false
}

// DatoNoConfiable delimita texto de pantalla, notificaciones, mensajes y
// archivos: es DATO, nunca instruccion (C5, R10-R12).
type DatoNoConfiable struct {
	Texto string
	Origen string
}

// MarcarDato envuelve texto externo como no confiable.
func MarcarDato(texto, origen string) DatoNoConfiable {
	return DatoNoConfiable{Texto: texto, Origen: origen}
}

// Formatea delimita el dato para que no se mezcle con el prompt del sistema.
func (d DatoNoConfiable) Formatea() string {
	return "<untrusted origin=\"" + d.Origen + "\">" + d.Texto + "</untrusted>"
}
