# linux-health-report

A small Bash snapshot of the root filesystem, memory, load average, and any services you name. It does not need root privileges or a background agent.

## Requirements

- Linux with Bash 3.2 or newer
- `df`, `free`, and `uptime`
- `systemctl` only when checking services
- Python 3 to run the JSON-parsing test suite

## Run

```bash
./health-report
./health-report --service ssh --service cron
./health-report --json --service ssh
```

Pass `--service` once for each unit you want checked; the command does not discover or query other services. The default output is plain text. `--json` writes the same snapshot as JSON, using `null` for values a command could not provide.

Example output (the numbers below come from the test fixture):

```text
Linux health report
Root disk: 25% used (250000 KiB used of 1000000 KiB, 750000 KiB available)
Memory: 1024 MiB used of 4096 MiB (2800 MiB available)
Load average: 0.12, 0.08, 0.04
Services: none requested
```

## Behavior and limits

The script reads `df`, `free`, and `uptime`; service checks call only `systemctl is-active` for the names supplied. It never calls `sudo` or changes service or system settings. If a metric command fails, that metric is marked unavailable. On a machine without systemd, requested service states are unavailable.

The report is a point-in-time summary, not a monitor or diagnostic. It reports the root filesystem and does not list processes, inspect logs, or explain why a service is down. It expects the usual Linux `df -P -k`, `free -m`, and `uptime` output formats.

## Checks

```bash
bash -n health-report
bash tests/test_health_report.sh
```

The test suite substitutes small mock commands and parses JSON with Python's standard library. A direct Linux smoke test has not been run in this development environment, which is macOS; the Linux command behavior is covered with those mocks.
