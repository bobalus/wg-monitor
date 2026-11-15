# WireGuard peer monitor

A Bash script that checks WireGuard peers and logs changes in recent handshake activity. Optional Discord webhook notifications are supported. Peers are compared by public key, so endpoint and port changes do not by themselves cause disconnect/reconnect alerts.

## Requirements

Linux, Bash, WireGuard tools (`wg`), `logger`, `awk`, `sort`, `comm`, `curl`, and `jq`. The monitor needs permission to run `wg show` and to write state files under `/run`.

## Configuration and use

1. Copy `wg-monitor.conf.example` to `wg-monitor.conf` alongside the script and run `chmod 600 wg-monitor.conf`.
2. Edit the configuration to set the optional Discord webhook and map WireGuard public keys to friendly names. Keep this file private and out of Git.
3. Run `./wg-monitor.sh` to check all interfaces, or `./wg-monitor.sh wg0` to check one interface. Schedule it at your desired interval with a systemd timer or cron. The executing user must be able to read the config and run `wg show`.

The script automatically sources `wg-monitor.conf` alongside itself for each interface; cron does not need to source or export it. Set `WG_MONITOR_CONFIG` to an alternate absolute path if needed. An unreadable or missing config stops the monitor. The file is Bash code executed with the monitor's privileges: use only a trusted file and protect both it and its parent directory from untrusted writes. The webhook may be empty to disable Discord; omit `PEER_NAMES` or leave its associative array empty to label peers `Unknown peer`.

The first run initializes state without reporting existing peers as new connections. State is stored under `/run` and is lost on reboot. A peer with no handshake in the last 300 seconds is treated as disconnected. WireGuard is quiet when idle, so this is an inactivity heuristic, not proof the tunnel was disabled. Adjust `INACTIVE_THRESHOLD` as needed.

## Run every minute with cron

On the WireGuard host, install the script and its private `wg-monitor.conf` together in a trusted directory. For example, if they are in `/root/server-scripts/`, make the script executable and ensure root can read the config. Edit root's personal crontab with `sudo crontab -e` and add:

```cron
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * /root/server-scripts/wg-monitor.sh >>/root/server-scripts/wg-monitor.log 2>&1
```

Adjust paths for your installation. The no-argument invocation automatically checks all WireGuard interfaces; do not add a separate per-interface loop as well, or the checks may overlap. For one interface instead, append its name, for example `wg0`. To specify a config elsewhere, add a crontab environment line such as `WG_MONITOR_CONFIG=/root/server-scripts/wg-monitor.conf`.

Inspect the schedule and logs with `sudo crontab -l`, `sudo systemctl status cron --no-pager`, `sudo journalctl -u cron --since "15 minutes ago" --no-pager`, and `sudo tail -n 50 /root/server-scripts/wg-monitor.log`. Arrange log rotation if retaining the file. If you prefer to discard output after testing, replace the redirection with `>/dev/null 2>&1`; this hides errors. A cron launch or an empty log does not prove Discord delivery: the script suppresses webhook delivery errors. Monitor syslog for messages tagged `wireguard-monitor`.

The first run initializes a separate state file per interface without sending initial notifications. An interface that disappears entirely will not generate individual peer disconnect notifications. The five-minute inactivity threshold plus the scheduling interval determines when inactivity is noticed.

For `/etc/crontab` or a file under `/etc/cron.d/`, include the user field instead; the job line becomes:

```cron
* * * * * root /root/server-scripts/wg-monitor.sh >>/root/server-scripts/wg-monitor.log 2>&1
```

## Security

Do not commit real webhook URLs or sensitive local configuration. Discord webhook URLs grant posting access; rotate any exposed webhook.
