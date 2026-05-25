# Install and dependencies

## `install.sh` overview

```bash
./install.sh              # script only → $HOME/bin/nginx-glance.sh
./install.sh --plasmoid   # script + Plasma applet (if kpackagetool6 exists)
INSTALL_DIR=~/.local/bin ./install.sh
```

Flow:

1. Parse arguments (`--plasmoid`, `--help`)
2. **`check_dependencies`**
3. **`install_script`** — `install -m 755 nginx-glance.sh` → target
4. **`install_plasmoid`** (optional)

## Dependency check

### Required CLI (install aborts if missing)

| Command | Typical Debian package |
|---------|------------------------|
| `bash` | bash |
| `curl` | curl |
| `systemctl` | systemd |
| `ss` | iproute2 |
| `awk`, `sed`, `grep`, `head`, `df` | coreutils |
| `free` | procps |

Hints printed as:

```text
sudo apt install curl iproute2 procps coreutils systemd
```

### Recommended (warnings only)

| Check | Warning if |
|-------|------------|
| `nginx` on PATH | Binary not found |
| `/etc/nginx/sites-enabled` | Directory missing |
| `nginx.service` unit | Not listed in systemd |

Install **continues** — useful for dev machines using `testdata/` only.

### Plasmoid note (`--plasmoid`)

If `kpackagetool6` missing:

- Script install still succeeds
- Manual instructions printed for `plasma-sdk` / `kpackagetool6 --install plasmoid`

## Post-install

```text
Installed script: $HOME/bin/nginx-glance.sh
Run: $HOME/bin/nginx-glance.sh --text
Or:  $HOME/bin/nginx-glance.sh --json   (Plasma widget)
```

## Plasmoid install logic

- Lists installed applets; **upgrades** if `org.nginxglance.nginxglance` exists
- Otherwise **installs** fresh package from `./plasmoid`

## Uninstall

```bash
rm -f ~/bin/nginx-glance.sh
kpackagetool6 --type Plasma/Applet --remove org.nginxglance.nginxglance
```

Remove widget from desktop manually if still placed.

## Distribution zip

Local archive (not in git) can include full tree:

```bash
zip -r nginx-glance.zip README.md CHANGELOG.md docs nginx-glance.sh install.sh .gitignore plasmoid testdata
```

## Related

- [status.md](status.md) — upgrade checklist after `git pull`
- [ADR-0007](adr/0007-portable-install-to-home-bin.md)
- [ADR-0001](adr/0001-read-only-local-status.md)
