# linux-health-report

A small, local-first Bash utility that prints a quick snapshot of the root filesystem, memory usage, load average, and any services you choose to inspect. It is designed for fast troubleshooting and for shell-based automation on Linux machines.

This repository is intentionally simple: no daemon, no background agent, and no elevated privileges required for the default checks. Everything runs from a single script and uses standard OS commands that are already available on most Linux systems.

## Why this project exists

- Quick health check without opening a full monitoring stack
- Read-only snapshot of disk, memory, load, and selected services
- Easy to run during SSH sessions, incident triage, and lightweight system audits
- No cloud dependency or remote telemetry

## Quick start

```bash
./health-report
./health-report --service ssh --service cron
./health-report --json --service ssh
```

Use `--service` once per unit you want to inspect. The script only checks the names you pass in. It does not discover unrelated services.

## Example output

```text
Linux health report
Root disk: 25% used (250000 KiB used of 1000000 KiB, 750000 KiB available)
Memory: 1024 MiB used of 4096 MiB (2800 MiB available)
Load average: 0.12, 0.08, 0.04
Services: none requested
```

## Behavior and limits

The script reads `df`, `free`, and `uptime` and calls `systemctl is-active` only for the service names you provide. It never calls `sudo`, never changes service state, and never writes anything except the output you request.

This is a point-in-time summary, not a full monitor or diagnostics tool. It reports the root filesystem and selected system metrics; it does not inspect processes, logs, or explain why a service is unhealthy.

## Checks

```bash
bash -n health-report
bash tests/test_health_report.sh
```

The test suite uses small mock commands and a Python standard-library JSON parser so the project stays easy to validate in CI or on a local Linux box.
