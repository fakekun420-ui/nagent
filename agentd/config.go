package main

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Config refleja config.yaml. Todo con default seguro si falta.
type Config struct {
	DNS struct {
		Servidores []string `yaml:"servidores"`
		DoH        string   `yaml:"doh"`
	} `yaml:"dns"`
	Auth struct {
		TokenPath string `yaml:"token_path"`
	} `yaml:"auth"`
	Router struct {
		NivelDefecto int    `yaml:"nivel_defecto"`
		RemotoURL    string `yaml:"remoto_url"`
	} `yaml:"router"`
	Ciclo struct {
		InactividadMin int    `yaml:"inactividad_min"`
		Binario        string `yaml:"binario"`
		Puerto         int    `yaml:"puerto"`
		CtxSize        int    `yaml:"ctx_size"`
		Afinidad       string `yaml:"afinidad"`
	} `yaml:"ciclo"`
	Binarios struct {
		LlamaServer string `yaml:"llama_server"`
		ShaLlama    string `yaml:"sha_llama"`
		Modelo      string `yaml:"modelo"`
		ShaModelo   string `yaml:"sha_modelo"`
	} `yaml:"binarios"`
	Memoria struct {
		UserDB  string `yaml:"user_db"`
		AgentDB string `yaml:"agent_db"`
	} `yaml:"memoria"`
}

// Cargar lee y valida lo minimo (rutas no vacias).
func Cargar(ruta string) (Config, error) {
	var c Config
	f, err := os.Open(ruta)
	if err != nil {
		return c, fmt.Errorf("abrir config %s: %w", ruta, err)
	}
	defer f.Close()
	if err := yaml.NewDecoder(f).Decode(&c); err != nil {
		return c, fmt.Errorf("parsear config %s: %w", ruta, err)
	}
	if c.Auth.TokenPath == "" {
		return c, fmt.Errorf("config: auth.token_path vacio")
	}
	if c.Ciclo.InactividadMin <= 0 {
		c.Ciclo.InactividadMin = 5
	}
	return c, nil
}

// MustCargar aborta si la config no vale (el daemon no arranca a ciegas).
func MustCargar(ruta string) Config {
	c, err := Cargar(ruta)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	return c
}
