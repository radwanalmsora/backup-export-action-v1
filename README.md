## Star History

<a href="https://www.star-history.com/?repos=marketplace%2Factions&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=marketplace/actions&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=marketplace/actions&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=marketplace/actions&type=date&legend=top-left" />
 </picture>
</a>

# Automated Backup & Export Action

A GitHub Action that automatically compresses selected project files, folders, or configuration files (such as `.env`) and exports them as a timestamped archive to GitHub Releases or a custom cloud storage endpoint.

Ideal for protecting critical project settings, build artifacts, and database dumps on every merge or release.

---

## Features

- ✅ Compresses multiple paths into a single `.tar.gz` archive
- ✅ Runs on push to `main`, tag creation, or GitHub Release
- ✅ Uploads backup as a release asset to GitHub Releases
- ✅ Optional upload to custom cloud storage (S3-compatible, R2, etc.)
- ✅ Excludes common noise (`.git`, `node_modules`, logs, etc.)
- ✅ Returns archive path, size, and download URL as outputs

---

## Usage

### Basic workflow (on merge to main)

```yaml
name: Backup on Merge

on:
  push:
    branches: [main]

jobs:
  backup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Backup important files
        uses: RadwanAlmsora/backup-export-action@v1
        with:
          paths: '.env,config/,dist/'
          archive-name: 'myapp-backup'
```

### With custom cloud storage

```yaml
      - name: Backup to R2 / S3
        uses: RadwanAlmsora/backup-export-action@v1
        with:
          paths: '.env,backend/data/'
          archive-name: 'production-backup'
          upload-to-release: 'false'
          cloud-storage-url: 'https://mybucket.r2.cloudflarestorage.com/backups/latest.tar.gz'
          cloud-storage-token: ${{ secrets.CLOUD_TOKEN }}
```

### On Release

```yaml
name: Backup on Release

on:
  release:
    types: [published]

jobs:
  backup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Backup release assets
        uses: RadwanAlmsora/backup-export-action@v1
        with:
          paths: 'dist/,release-notes.md'
          archive-name: 'release-backup'
```

---

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `paths` | Yes | `.` | Comma-separated list of files or folders to back up |
| `archive-name` | No | `backup` | Base name for the archive (timestamp appended automatically) |
| `upload-to-release` | No | `true` | Upload archive to the current GitHub Release |
| `cloud-storage-url` | No | (empty) | Custom endpoint URL for direct upload (PUT) |
| `cloud-storage-token` | No | (empty) | Bearer token for custom cloud storage |

---

## Outputs

| Output | Description |
|--------|-------------|
| `archive-path` | Absolute path to the created `.tar.gz` archive |
| `archive-size` | Size of the archive in bytes |
| `download-url` | Public download URL (GitHub Release asset or cloud storage URL) |

---

## What gets excluded

The action automatically skips common noise to keep archives small:
- `.git/`
- `node_modules/`
- `.next/`, `dist/`, `build/`
- `*.log`
- `.DS_Store`

---

## Security

- Secrets (GitHub token, cloud storage token) are masked in logs automatically.
- The action does not send data to any external service unless you configure `cloud-storage-url`.
- Use repository secrets (`secrets.CLOUD_TOKEN`) for sensitive tokens.

---

## License

MIT License © 2026 RadwanAlmsora
