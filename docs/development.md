# Development

## Repository Layout

```text
bin/rclone-mount-manager          Main command
install.sh                        Installer
uninstall.sh                      Uninstaller
config/user.conf.example          User config template
config/system.conf.example        System config template
systemd/user/*.service            User systemd unit template
systemd/system/*.service          System unit template
tests/test.sh                     Shell tests
```

## Tests

Run the test suite:

```bash
make test
```

This runs shell syntax checks and `tests/test.sh`.

## Linting

Optional checks:

```bash
make lint
make format-check
```

`make lint` uses `shellcheck` when it is installed.

`make format-check` uses `shfmt` when it is installed.

## Manual Test Flow

Use a dry run before installing:

```bash
./install.sh --user --dry-run --enable
```

Use a temporary config to test command behavior:

```bash
RMM_CONFIG_FILE=/path/to/config bin/rclone-mount-manager print-config
RMM_CONFIG_FILE=/path/to/config bin/rclone-mount-manager doctor
```

For service testing, install in user mode first. It avoids root-owned files and
is easier to remove:

```bash
./install.sh --user --start
./uninstall.sh --user
```

## Documentation

Keep the root README short. Put detailed notes in `docs/`.

When behavior changes, update the docs page that matches the change:

- Setup changes go in [setup.md](setup.md).
- Config changes go in [configuration.md](configuration.md).
- Command changes go in [commands.md](commands.md).
- Service lifecycle changes go in [service-behavior.md](service-behavior.md).
- Security changes go in [security.md](security.md).
- Failure modes go in [troubleshooting.md](troubleshooting.md).
