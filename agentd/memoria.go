package main

import (
	"database/sql"
	"encoding/json"
	"fmt"

	_ "modernc.org/sqlite"
)

// Memoria guarda pares clave-valor en dos dominios SQLite (C7, driver puro Go).
type Memoria struct {
	user  *sql.DB
	agent *sql.DB
}

const esquema = `CREATE TABLE IF NOT EXISTS kv (clave TEXT PRIMARY KEY, valor TEXT NOT NULL);`

// AbrirMemoria abre (o crea) user.db y agent.db con el esquema minimo.
func AbrirMemoria(userPath, agentPath string) (*Memoria, error) {
	u, err := sql.Open("sqlite", userPath)
	if err != nil {
		return nil, fmt.Errorf("abrir user.db: %w", err)
	}
	a, err := sql.Open("sqlite", agentPath)
	if err != nil {
		u.Close()
		return nil, fmt.Errorf("abrir agent.db: %w", err)
	}
	for _, db := range []*sql.DB{u, a} {
		if _, err := db.Exec(esquema); err != nil {
			u.Close()
			a.Close()
			return nil, fmt.Errorf("esquema: %w", err)
		}
	}
	return &Memoria{user: u, agent: a}, nil
}

// Cerrar cierra ambas bases.
func (m *Memoria) Cerrar() {
	m.user.Close()
	m.agent.Close()
}

func (m *Memoria) base(dominio string) (*sql.DB, error) {
	switch dominio {
	case "user":
		return m.user, nil
	case "agent":
		return m.agent, nil
	default:
		return nil, fmt.Errorf("dominio %q: solo user|agent", dominio)
	}
}

// Guardar escribe un par (usado por remember, Bloque D).
func (m *Memoria) Guardar(dominio, clave, valor string) error {
	db, err := m.base(dominio)
	if err != nil {
		return err
	}
	_, err = db.Exec(`INSERT INTO kv(clave, valor) VALUES(?, ?)
		ON CONFLICT(clave) DO UPDATE SET valor=excluded.valor`, clave, valor)
	return err
}

// MemoriaLeer es la herramienta leer_memoria (dominio+clave, sin SQL libre).
func MemoriaLeer(args json.RawMessage) (any, error) {
	var a struct {
		Dominio string `json:"dominio"`
		Clave   string `json:"clave"`
	}
	if err := json.Unmarshal(args, &a); err != nil {
		return nil, fmt.Errorf("args: %w", err)
	}
	if memGlobal == nil {
		return nil, fmt.Errorf("memoria no abierta")
	}
	db, err := memGlobal.base(a.Dominio)
	if err != nil {
		return nil, err
	}
	var v string
	if err := db.QueryRow(`SELECT valor FROM kv WHERE clave = ?`, a.Clave).Scan(&v); err != nil {
		return nil, fmt.Errorf("leer: %w", err)
	}
	return map[string]string{"valor": v}, nil
}

// memGlobal la fija main al arrancar (nil = herramienta no disponible).
var memGlobal *Memoria
