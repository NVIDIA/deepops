// deepops-slurm-exporter exposes Slurm cluster state as Prometheus metrics.
//
// It is a dependency-free replacement for the previously used third-party
// exporter, emitting the metric names consumed by the DeepOps Grafana
// dashboard (slurm_nodes_*, slurm_queue_*, slurm_scheduler_*) plus the
// aggregate CPU gauges (slurm_cpus_*). Metrics are collected by executing
// the Slurm client tools on each scrape, with explicit no-truncation output
// formats so long node names and non-C locales cannot corrupt parsing.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"
)

var commandTimeout = 30 * time.Second

// runCommand executes a Slurm client tool and returns its stdout.
func runCommand(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), commandTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).Output()
	if err != nil {
		return "", fmt.Errorf("%s: %w", name, err)
	}
	return string(out), nil
}

// ParseNodeStates aggregates `sinfo -h -o %T,%D` output into the dashboard's
// node state gauges. State names may carry suffix flags (*, ~, #, $, @, +)
// and long forms (allocated, drained); matching is by prefix category.
func ParseNodeStates(input string) map[string]float64 {
	states := map[string]float64{
		"alloc": 0, "comp": 0, "down": 0, "drain": 0, "err": 0,
		"fail": 0, "idle": 0, "maint": 0, "mix": 0,
	}
	for _, line := range strings.Split(input, "\n") {
		parts := strings.Split(strings.TrimSpace(line), ",")
		if len(parts) != 2 {
			continue
		}
		state := strings.ToLower(strings.TrimRight(parts[0], "*~#$@+^-"))
		count, err := strconv.ParseFloat(parts[1], 64)
		if err != nil {
			continue
		}
		switch {
		case strings.HasPrefix(state, "alloc"):
			states["alloc"] += count
		case strings.HasPrefix(state, "comp"):
			states["comp"] += count
		case strings.HasPrefix(state, "down"):
			states["down"] += count
		case strings.HasPrefix(state, "drain"):
			states["drain"] += count
		case strings.HasPrefix(state, "err"):
			states["err"] += count
		case strings.HasPrefix(state, "fail"):
			states["fail"] += count
		case strings.HasPrefix(state, "idle"):
			states["idle"] += count
		case strings.HasPrefix(state, "maint"):
			states["maint"] += count
		case strings.HasPrefix(state, "mix"):
			states["mix"] += count
		}
	}
	return states
}

// ParseCPUs parses `sinfo -h -o %C` (allocated/idle/other/total).
func ParseCPUs(input string) (map[string]float64, error) {
	fields := strings.Split(strings.TrimSpace(input), "/")
	if len(fields) != 4 {
		return nil, fmt.Errorf("unexpected %%C output: %q", strings.TrimSpace(input))
	}
	keys := []string{"alloc", "idle", "other", "total"}
	cpus := map[string]float64{}
	for i, k := range keys {
		v, err := strconv.ParseFloat(fields[i], 64)
		if err != nil {
			return nil, fmt.Errorf("unexpected %%C field %q: %w", fields[i], err)
		}
		cpus[k] = v
	}
	return cpus, nil
}

// ParseQueueStates counts `squeue -a -r -h -o %T --states=all` job states
// into the dashboard's queue gauges.
func ParseQueueStates(input string) map[string]float64 {
	queue := map[string]float64{
		"pending": 0, "running": 0, "suspended": 0, "cancelled": 0,
		"completing": 0, "completed": 0, "failed": 0, "timeout": 0,
		"node_fail": 0, "preempted": 0,
	}
	for _, line := range strings.Split(input, "\n") {
		state := strings.ToLower(strings.TrimSpace(line))
		if state == "" {
			continue
		}
		if _, ok := queue[state]; ok {
			queue[state]++
		}
	}
	return queue
}

// ParseScheduler extracts the dashboard's scheduler gauges from `sdiag`
// text output. Main and backfilling sections repeat the same field names,
// so section context is tracked explicitly.
func ParseScheduler(input string) map[string]float64 {
	// Pre-initialize every gauge: on an idle cluster sdiag omits the mean
	// and depth lines entirely (no cycles yet), and the dashboard expects
	// the series to exist with value 0 rather than be absent.
	sched := map[string]float64{
		"threads": 0, "queue_size": 0, "last_cycle": 0, "mean_cycle": 0,
		"backfill_last_cycle": 0, "backfill_mean_cycle": 0, "backfill_depth_mean": 0,
	}
	backfill := false
	numberAfterColon := func(line string) (float64, bool) {
		idx := strings.LastIndex(line, ":")
		if idx < 0 {
			return 0, false
		}
		fields := strings.Fields(line[idx+1:])
		if len(fields) == 0 {
			return 0, false
		}
		v, err := strconv.ParseFloat(fields[0], 64)
		if err != nil {
			return 0, false
		}
		return v, true
	}
	for _, line := range strings.Split(input, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "Backfilling stats") {
			backfill = true
		}
		switch {
		case strings.HasPrefix(trimmed, "Server thread count:"):
			if v, ok := numberAfterColon(trimmed); ok {
				sched["threads"] = v
			}
		case strings.HasPrefix(trimmed, "Agent queue size:"):
			if v, ok := numberAfterColon(trimmed); ok {
				sched["queue_size"] = v
			}
		case strings.HasPrefix(trimmed, "Last cycle:"):
			if v, ok := numberAfterColon(trimmed); ok {
				if backfill {
					sched["backfill_last_cycle"] = v
				} else {
					sched["last_cycle"] = v
				}
			}
		case strings.HasPrefix(trimmed, "Mean cycle:"):
			if v, ok := numberAfterColon(trimmed); ok {
				if backfill {
					sched["backfill_mean_cycle"] = v
				} else {
					sched["mean_cycle"] = v
				}
			}
		case strings.HasPrefix(trimmed, "Depth Mean:"):
			if v, ok := numberAfterColon(trimmed); ok {
				sched["backfill_depth_mean"] = v
			}
		}
	}
	return sched
}

type metricsBuilder struct {
	b strings.Builder
}

func (m *metricsBuilder) gauge(name, help string, value float64) {
	fmt.Fprintf(&m.b, "# HELP %s %s\n# TYPE %s gauge\n%s %g\n", name, help, name, name, value)
}

func (m *metricsBuilder) gaugeSet(prefix, help string, values map[string]float64) {
	keys := make([]string, 0, len(values))
	for k := range values {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		m.gauge(prefix+k, help+" ("+k+")", values[k])
	}
}

func (m *metricsBuilder) String() string { return m.b.String() }

// collect gathers all metrics; collector failures are reported through
// slurm_exporter_collector_errors rather than failing the whole scrape.
func collect() string {
	m := &metricsBuilder{}
	errors := 0

	if out, err := runCommand("sinfo", "-h", "-o", "%T,%D"); err == nil {
		m.gaugeSet("slurm_nodes_", "Count of nodes by state", ParseNodeStates(out))
	} else {
		log.Printf("node collector: %v", err)
		errors++
	}

	if out, err := runCommand("sinfo", "-h", "-o", "%C"); err == nil {
		if cpus, perr := ParseCPUs(out); perr == nil {
			m.gaugeSet("slurm_cpus_", "Aggregate CPUs by allocation state", cpus)
		} else {
			log.Printf("cpu collector: %v", perr)
			errors++
		}
	} else {
		log.Printf("cpu collector: %v", err)
		errors++
	}

	if out, err := runCommand("squeue", "-a", "-r", "-h", "-o", "%T", "--states=all"); err == nil {
		m.gaugeSet("slurm_queue_", "Count of jobs by state", ParseQueueStates(out))
	} else {
		log.Printf("queue collector: %v", err)
		errors++
	}

	if out, err := runCommand("sdiag"); err == nil {
		m.gaugeSet("slurm_scheduler_", "Slurm scheduler statistics", ParseScheduler(out))
	} else {
		log.Printf("scheduler collector: %v", err)
		errors++
	}

	m.gauge("slurm_exporter_collector_errors",
		"Number of collectors that failed during this scrape", float64(errors))
	return m.String()
}

func main() {
	listen := flag.String("listen-address", ":8080", "address to serve /metrics on")
	flag.Parse()

	http.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprint(w, collect())
	})
	log.Printf("deepops-slurm-exporter listening on %s", *listen)
	log.Fatal(http.ListenAndServe(*listen, nil))
}
