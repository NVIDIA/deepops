package main

import "testing"

func TestParseNodeStates(t *testing.T) {
	input := "allocated,3\nidle,10\nmixed,2\ndrained*,1\ndown~,4\nmaint,1\n\nnot-a-state-line\n"
	states := ParseNodeStates(input)
	expect := map[string]float64{
		"alloc": 3, "idle": 10, "mix": 2, "drain": 1, "down": 4,
		"maint": 1, "comp": 0, "err": 0, "fail": 0,
	}
	for k, v := range expect {
		if states[k] != v {
			t.Errorf("state %s: got %v want %v", k, states[k], v)
		}
	}
}

func TestParseNodeStatesLongNamesIrrelevant(t *testing.T) {
	// State aggregation uses %T,%D so node name length can never matter,
	// but flag suffixes on states must still strip.
	states := ParseNodeStates("idle*,5\nallocated#,2\n")
	if states["idle"] != 5 || states["alloc"] != 2 {
		t.Errorf("suffix stripping failed: %+v", states)
	}
}

func TestParseCPUs(t *testing.T) {
	cpus, err := ParseCPUs("3/13/0/16\n")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cpus["alloc"] != 3 || cpus["idle"] != 13 || cpus["other"] != 0 || cpus["total"] != 16 {
		t.Errorf("bad parse: %+v", cpus)
	}
	if _, err := ParseCPUs("garbage"); err == nil {
		t.Error("expected error on malformed input")
	}
}

func TestParseQueueStates(t *testing.T) {
	input := "PENDING\nPENDING\nRUNNING\nCOMPLETED\nFAILED\nNODE_FAIL\nUNKNOWN_STATE\n\n"
	q := ParseQueueStates(input)
	if q["pending"] != 2 || q["running"] != 1 || q["completed"] != 1 ||
		q["failed"] != 1 || q["node_fail"] != 1 || q["timeout"] != 0 {
		t.Errorf("bad parse: %+v", q)
	}
}

func TestParseScheduler(t *testing.T) {
	// Shape observed from sdiag on Slurm 26.05.
	input := `*******************************************************
sdiag output at Wed Jul 15 17:48:55 2026 (1784137735)
Data since      Wed Jul 15 17:28:49 2026 (1784136529)
*******************************************************
Server thread count:  3
Agent queue size:     0

Main schedule statistics (microseconds):
	Last cycle:   289
	Max cycle:    1691
	Total cycles: 25
	Mean cycle:   513

Backfilling stats
	Total backfilled jobs (since last slurm start): 0
	Last cycle when: Wed Jul 15 17:47:21 2026 (1784137641)
	Last cycle:   45
	Mean cycle:   60
	Last depth cycle: 0
	Depth Mean:   4
`
	s := ParseScheduler(input)
	expect := map[string]float64{
		"threads": 3, "queue_size": 0, "last_cycle": 289, "mean_cycle": 513,
		"backfill_last_cycle": 45, "backfill_mean_cycle": 60, "backfill_depth_mean": 4,
	}
	for k, v := range expect {
		if s[k] != v {
			t.Errorf("scheduler %s: got %v want %v", k, s[k], v)
		}
	}
}

func TestParseSchedulerIdleClusterEmitsFullSet(t *testing.T) {
	// Zero-cycle clusters omit Mean cycle / Depth Mean lines entirely;
	// every scheduler gauge must still exist with value 0.
	s := ParseScheduler("Server thread count:  3\nBackfilling stats\n\tTotal cycles: 0\n\tLast cycle: 0\n")
	for _, k := range []string{"threads", "queue_size", "last_cycle", "mean_cycle",
		"backfill_last_cycle", "backfill_mean_cycle", "backfill_depth_mean"} {
		if _, ok := s[k]; !ok {
			t.Errorf("missing scheduler gauge %s on idle cluster", k)
		}
	}
}

func TestParseSchedulerLastCycleWhenNotConfused(t *testing.T) {
	// "Last cycle when:" carries a timestamp and must not overwrite
	// "Last cycle:".
	s := ParseScheduler("Backfilling stats\n\tLast cycle when: Wed Jul 15 17:47:21 2026 (1784137641)\n\tLast cycle:   45\n")
	if s["backfill_last_cycle"] != 45 {
		t.Errorf("Last cycle when: leaked into backfill_last_cycle: %+v", s)
	}
}

func TestMetricsOutputFormat(t *testing.T) {
	m := &metricsBuilder{}
	m.gauge("slurm_nodes_idle", "Count of nodes by state (idle)", 5)
	out := m.String()
	want := "# HELP slurm_nodes_idle Count of nodes by state (idle)\n# TYPE slurm_nodes_idle gauge\nslurm_nodes_idle 5\n"
	if out != want {
		t.Errorf("exposition format mismatch:\ngot:  %q\nwant: %q", out, want)
	}
}
