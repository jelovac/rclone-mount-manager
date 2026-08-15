# Service Behavior

`rclone-mount-manager` leaves service lifecycle work to systemd.

The script handles rclone details:

- Load config.
- Check dependencies.
- Check remote availability.
- Create mount, log, and state directories.
- Start each `rclone mount`.
- Stop mounts in reverse order.
- Fall back to lazy FUSE unmount when normal unmount does not finish.

Systemd handles:

- Starting on login or boot.
- Restarting after failure.
- Running the foreground manager process.
- Sending stop signals during logout or shutdown.

## Installed Units

User mode installs:

```text
~/.config/systemd/user/rclone-mount-manager.service
```

System mode installs:

```text
/etc/systemd/system/rclone-mount-manager.service
```

Both units run:

```text
ExecStart=<binary> run
Restart=on-failure
RestartSec=10
KillMode=mixed
TimeoutStopSec=45
```

The system unit also waits for `network-online.target`.

The foreground manager owns shutdown. Systemd signals that process first, and
the manager stops all mount supervisors before unmounting the configured mounts.
The units limit manager-level restart attempts to five starts in five minutes.

## Startup

On startup, the manager:

1. Loads the config.
2. Validates `MOUNTS` and `REMOTES`.
3. Creates required directories.
4. Starts one independent supervisor for each mount.
5. Each supervisor checks its remote unless `CONNECTIVITY_CHECK=off`.
6. Each supervisor starts its mount and waits up to
   `START_TIMEOUT_SECONDS` for it to become active.

Remote checks and mount starts run independently. A slow or unavailable remote
does not delay other configured mounts.

## Supervised Mode

The systemd service uses `run`, not `start`.

In `run` mode, every mount has its own long-running supervisor. A supervisor
checks both the mount point and its recorded rclone process every
`HEALTH_CHECK_INTERVAL_SECONDS`.

When one mount fails, its supervisor:

1. Records the failure for `status`.
2. Unmounts or terminates only that mount.
3. Waits for the configured retry delay.
4. Starts only that mount again.

The default retry delays are 10, 30, 60, and 300 seconds. Further failures use
the final delay. The failure count resets after the mount remains healthy for
`RETRY_RESET_SECONDS`.

Healthy mount processes are not stopped or restarted. If every mount is down,
the manager remains active in a degraded state and continues paced retries.
Systemd restarts the service only if the manager itself fails, not when an
individual mount fails.

## Per-Mount Controls

The running manager checks its owner-only control directory on every health
cycle. A restart or retry request stops only the selected supervisor, cleans up
that mount, and starts a new supervisor immediately.

A paused mount has no supervisor and is not retried. Pause markers are stored
outside the runtime directory, so paused mounts remain paused across manager
and system restarts until explicitly resumed.

## Stop

On an explicit service stop or shutdown, the manager terminates the independent
supervisors and unmounts configured mounts in reverse order.

For each mount it tries:

1. Normal FUSE unmount.
2. Lazy FUSE unmount if the normal unmount times out.
3. `SIGTERM` to the recorded rclone process if a pid file exists.

The normal wait time is controlled by:

```bash
STOP_TIMEOUT_SECONDS=20
```

## Manual Start

`rclone-mount start` starts mounts using `rclone mount --daemon`.

This is useful for manual testing. For automatic service use, prefer systemd.
