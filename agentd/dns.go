package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"
)

// NuevoResolver devuelve un Resolver Go puro contra los servidores dados
// (en Android no hay /etc/resolv.conf, C1).
func NuevoResolver(servidores []string) *net.Resolver {
	if len(servidores) == 0 {
		servidores = []string{"8.8.8.8", "1.1.1.1"}
	}
	return &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, _, _ string) (net.Conn, error) {
			d := net.Dialer{Timeout: 5 * time.Second}
			return d.DialContext(ctx, "udp", servidores[0]+":53")
		},
	}
}

// ResolverDoH es el respaldo por TLS cuando el UDP falla (C1).
func ResolverDoH(ctx context.Context, nombre, dohURL string) ([]string, error) {
	if dohURL == "" {
		return nil, fmt.Errorf("sin DoH configurado")
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "GET", dohURL+"?name="+nombre+"&type=A", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/dns-json")
	cl := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12}}}
	resp, err := cl.Do(req)
	if err != nil {
		return nil, fmt.Errorf("doh: %w", err)
	}
	defer resp.Body.Close()
	var j struct {
		Answer []struct {
			Data string `json:"data"`
		} `json:"Answer"`
	}
	dec := json.NewDecoder(resp.Body)
	if err := dec.Decode(&j); err != nil {
		return nil, fmt.Errorf("doh parse: %w", err)
	}
	var ips []string
	for _, a := range j.Answer {
		if strings.Count(a.Data, ".") == 3 {
			ips = append(ips, a.Data)
		}
	}
	if len(ips) == 0 {
		return nil, fmt.Errorf("doh sin respuestas A para %s", nombre)
	}
	return ips, nil
}
