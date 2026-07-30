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
ExecStop=<binary> stop
Restart=on-failure
RestartSec=10
TimeoutStopSec=45
```

The system unit also waits for `network-online.target`.

## Startup

On startup, the manager:

1. Loads the config.
2. Validates `MOUNTS` and `REMOTES`.
3. Creates required directories.
4. Checks each remote unless `CONNECTIVITY_CHECK=off`.
5. Starts each mount.
6. Waits up to `START_TIMEOUT_SECONDS` for each mount point to become active.

If a mount fails and `ROLLBACK_ON_START_FAILURE=true`, mounts started during
that startup attempt are unmounted.

## Supervised Mode

The systemd service uses `run`, not `start`.

In `run` mode, rclone is started in the foreground and the manager keeps
running. Every 5 seconds it checks that each mount point is still mounted. If
one mount disappears, the manager stops the rest and exits with failure.

Because the unit has `Restart=on-failure`, systemd can retry.

## Stop

On stop, the manager unmounts configured mounts in reverse order.

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
