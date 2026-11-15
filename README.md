# WireGuard peer monitor

A Bash script that checks WireGuard peers and logs changes in recent handshake activity. Optional Discord webhook notifications are supported. Peers are compared by public key, so endpoint and port changes do not by themselves cause disconnect/reconnect alerts.

## Requirements

Linux, Bash, WireGuard tools (`wg`), `logger`, `awk`, `sort`, `comm`, `curl`, and `jq`. The monitor needs permission to run `wg show` and to write state files under `/run`.

## Configuration and use

1. Optionally edit `PEER_NAMES` in `wg-monitor.sh` to map peer public keys to friendly names.
2. Optionally supply `DISCORD_WEBHOOK_URL` as an environment variable. Keep the URL secret and out of Git. With no URL, Discord notifications are disabled.
3. Run `./wg-monitor.sh` to check all interfaces, or `./wg-monitor.sh wg0` to check one interface. Schedule it at your desired interval using a systemd timer or cron. Ensure the service environment contains the webhook variable if Discord notifications are desired.

The first run initializes state without reporting existing peers as new connections. State is stored under `/run` and is lost on reboot. A peer with no handshake in the last 300 seconds is treated as disconnected. WireGuard is quiet when idle, so this is an inactivity heuristic, not proof the tunnel was disabled. Adjust `INACTIVE_THRESHOLD` as needed.

## Security

Do not commit real webhook URLs or sensitive local configuration. Discord webhook URLs grant posting access; rotate any exposed webhook.
