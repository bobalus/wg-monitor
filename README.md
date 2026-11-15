# WireGuard peer monitor

A Bash script that checks WireGuard peers and logs changes in recent handshake activity. Optional Discord webhook notifications are supported. Peers are compared by public key, so endpoint and port changes do not by themselves cause disconnect/reconnect alerts.

## Requirements

Linux, Bash, WireGuard tools (`wg`), `logger`, `awk`, `sort`, `comm`, `curl`, and `jq`. The monitor needs permission to run `wg show` and to write state files under `/run`.

## Configuration and use

1. Copy `wg-monitor.conf.example` to `wg-monitor.conf` alongside the script and run `chmod 600 wg-monitor.conf`.
2. Edit the configuration to set the optional Discord webhook and map WireGuard public keys to friendly names. Keep this file private and out of Git.
3. Run `./wg-monitor.sh` to check all interfaces, or `./wg-monitor.sh wg0` to check one interface. Schedule it at your desired interval with a systemd timer or cron. The executing user must be able to read the config and run `wg show`.

The config file is sourced as Bash code: only use a trusted file in a trusted directory. Set `WG_MONITOR_CONFIG` to an alternate absolute path if needed. The default is `wg-monitor.conf` alongside the script. An unreadable or missing config stops the monitor.

The first run initializes state without reporting existing peers as new connections. State is stored under `/run` and is lost on reboot. A peer with no handshake in the last 300 seconds is treated as disconnected. WireGuard is quiet when idle, so this is an inactivity heuristic, not proof the tunnel was disabled. Adjust `INACTIVE_THRESHOLD` as needed.

## Security

Do not commit real webhook URLs or sensitive local configuration. Discord webhook URLs grant posting access; rotate any exposed webhook.
