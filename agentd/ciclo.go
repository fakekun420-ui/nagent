package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// Ciclo gestiona la vida de llama-server: carga bajo demanda y descarga
// tras N minutos de inactividad (C9). Sin busqueda por nombre: PID propio
// comprobado por comm (mismo patron que spike.sh parar_server).
type Ciclo struct {
	cfg      Config
	cmd      *exec.Cmd
	pid      int
	ultimo   time.Time
	oomAllow []string
}

// NuevoCiclo crea el gestor con la config.
func NuevoCiclo(cfg Config) *Ciclo {
	return &Ciclo{cfg: cfg, ultimo: time.Now(), oomAllow: []string{"-1000", "0", "100", "500"}}
}

// VerificarComm lee /proc/pid/comm y exige el binario final.
func VerificarComm(pid int, esperado string) bool {
	b, err := os.ReadFile(fmt.Sprintf("/proc/%d/comm", pid))
	if err != nil {
		return false
	}
	return strings.TrimSpace(string(b)) == esperado
}

// Cargar lanza llama-server con taskset y afinidad de la config.
func (c *Ciclo) Cargar(modelo string) error {
	if c.cmd != nil && c.cmd.Process != nil {
		return fmt.Errorf("ya cargado (pid %d)", c.pid)
	}
	c.cmd = exec.Command("taskset", c.cfg.Ciclo.Afinidad,
		c.cfg.Binarios.LlamaServer,
		"-m", modelo,
		"--port", fmt.Sprint(c.cfg.Ciclo.Puerto),
		"-c", fmt.Sprint(c.cfg.Ciclo.CtxSize),
		"--np", "1")
	if err := c.cmd.Start(); err != nil {
		c.cmd = nil
		return fmt.Errorf("lanzar llama-server: %w", err)
	}
	c.pid = c.cmd.Process.Pid
	time.Sleep(3 * time.Second)
	if !VerificarComm(c.pid, "llama-server") {
		_ = c.cmd.Process.Kill()
		c.cmd = nil
		return fmt.Errorf("PID %d no es llama-server (comm distinto)", c.pid)
	}
	if err := os.WriteFile(fmt.Sprintf("/proc/%d/oom_score_adj", c.pid), []byte("500"), 0644); err != nil {
		_ = c.cmd.Process.Kill()
		c.cmd = nil
		return fmt.Errorf("oom_score_adj: %w", err)
	}
	c.ultimo = time.Now()
	return nil
}

// Tocar actualiza el ultimo uso (cada inferencia lo llama).
func (c *Ciclo) Tocar() { c.ultimo = time.Now() }

// DescargarSiOcioso mata el servidor si supera los minutos de inactividad.
func (c *Ciclo) DescargarSiOcioso() bool {
	if c.cmd == nil || c.cmd.Process == nil {
		return false
	}
	if time.Since(c.ultimo) < time.Duration(c.cfg.Ciclo.InactividadMin)*time.Minute {
		return false
	}
	_ = c.cmd.Process.Kill()
	c.cmd = nil
	return true
}
