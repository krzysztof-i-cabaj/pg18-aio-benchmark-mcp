# Installing PostgreSQL 16 alongside PG18 on Oracle Linux 8.8

**Environment:** Oracle Linux 8.8 | VirtualBox
**Goal:** PG16 on port **5416** (baseline) + PG18 on port **5432** (test)
**Author:** KCB Kris | Date: 2026-04-01

🇵🇱 [Wersja polska / Polish version](INSTALL_PG16_PL.md)

---

## 🔍 Before installation — check current state

```bash
# What is currently installed?
rpm -qa | grep postgresql

# What port does PG18 use?
sudo -u postgres psql -c "SHOW port;"

# Check PG18 version
sudo -u postgres psql -c "SELECT version();"

# Check PG18 data directory
sudo -u postgres psql -c "SHOW data_directory;"
```

Make sure PG18 is running on port **5432** — we will install PG16 on **5416**.

---

## 📦 STEP 1: Add PGDG repository (PostgreSQL 16)

```bash
# Add official PostgreSQL Global Development Group repository
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Disable postgresql module from AppStream (to avoid conflicts with PGDG)
sudo dnf -qy module disable postgresql

# Verify repository is available
sudo dnf repolist | grep pgdg
```

Expected output — you should see:
```
pgdg16    PostgreSQL 16 for RHEL/Rocky/AlmaLinux 8
pgdg18    PostgreSQL 18 for RHEL/Rocky/AlmaLinux 8
```

---

## 📦 STEP 2: Install PostgreSQL 16 packages

```bash
# Install PG16 server and client
sudo dnf install -y postgresql16-server postgresql16

# Verify installed packages
rpm -qa | grep postgresql16

# Check PG16 binary location
/usr/pgsql-16/bin/postgres --version
```

Expected output:
```
postgres (PostgreSQL) 16.x
```

---

## 🗄️ STEP 3: Initialize PG16 cluster (custom paths — same as PG18)

Instead of `postgresql-16-setup initdb` (default paths `/var/lib/pgsql/16/data/`),
we use direct `initdb` with dedicated directories — identical approach as PG18.

```bash
# Create data and WAL directories
sudo mkdir -p /postgres/16/data
sudo mkdir -p /postgres/16/wal
sudo chown -R postgres:postgres /postgres/16/

# Initialize — identical syntax as PG18
sudo -u postgres /usr/pgsql-16/bin/initdb \
  -D /postgres/16/data \
  -X /postgres/16/wal \
  -E UTF8 \
  -W

# Verify directory exists with correct owner
ls -la /postgres/16/data/
ls -la /postgres/16/wal/
```

> **NOTE:** The `-W` flag forces superuser password prompt during initdb.
> The `-X` flag moves WAL to a separate path (same as PG18: `/postgres/18/wal`).

---

## ⚙️ STEP 4: Configure postgresql.conf for PG16

```bash
# Edit PG16 configuration
sudo nano /postgres/16/data/postgresql.conf
```

Find and change (or add) the following parameters:

```ini
# -----------------------------------------------
# PORT — critical! PG18 occupies 5432
# -----------------------------------------------
port = 5416

# -----------------------------------------------
# Memory — set IDENTICALLY to PG18 (for fair benchmark)
# -----------------------------------------------
shared_buffers = 256MB
work_mem = 4MB
maintenance_work_mem = 64MB

# -----------------------------------------------
# I/O — PG16 uses synchronous I/O (no io_method parameter)
# There is no io_method parameter in PG16 — this IS the baseline
# -----------------------------------------------

# -----------------------------------------------
# Statistics — needed for benchmark
# -----------------------------------------------
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
track_io_timing = on

# -----------------------------------------------
# Logging (optional, helpful for diagnostics)
# -----------------------------------------------
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
```

Save the file (Ctrl+O, Enter, Ctrl+X in nano).

> **IMPORTANT:** Check PG18 values and set identical ones in PG16:
> ```bash
> sudo -u postgres psql -c "SHOW shared_buffers; SHOW work_mem;"
> ```

---

## 🔐 STEP 5: Configure pg_hba.conf for PG16

```bash
sudo nano /postgres/16/data/pg_hba.conf
```

Make sure the following entries exist (usually present after initdb):

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
```

> We use `trust` only locally on a test environment — never in production!

---

## 🚀 STEP 6: Configure systemd and start PG16

Since we use a non-standard PGDATA (`/postgres/16/data` instead of `/var/lib/pgsql/16/data`),
we need to override the systemd service configuration.

```bash
# Override PGDATA in systemd service (creates override.conf)
sudo systemctl edit postgresql-16
```

In the editor, type exactly:

```ini
[Service]
Environment=PGDATA=/postgres/16/data
```

Save and close the editor. Verify the override was saved:

```bash
cat /etc/systemd/system/postgresql-16.service.d/override.conf
```

Now start the service:

```bash
# Reload systemd configuration (after editing)
sudo systemctl daemon-reload

# Enable autostart and start PG16
sudo systemctl enable postgresql-16
sudo systemctl start postgresql-16

# Check status
sudo systemctl status postgresql-16

# Verify PG16 is listening on port 5416
sudo ss -tlnp | grep 5416
```

Expected `ss` output:
```
LISTEN   0   128   0.0.0.0:5416   0.0.0.0:*   users:(("postgres",pid=XXXX,...))
```

---

## ✅ STEP 7: Verify both instances

```bash
# Connect to PG16 (port 5416)
psql -U postgres -p 5416 -c "SELECT version(); SHOW port;"

# Connect to PG18 (port 5432)
psql -U postgres -p 5432 -c "SELECT version(); SHOW port; SHOW io_method;"
```

Expected output:
```
-- PG16:
PostgreSQL 16.x on x86_64-pc-linux-gnu ...
 port
------
 5416

-- PG18:
PostgreSQL 18.0 on x86_64-pc-linux-gnu ...
 port
------
 5432

 io_method
-----------
 worker
```

---

## 🔧 STEP 8: Install pg_stat_statements on PG16

```bash
psql -U postgres -p 5416 -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
psql -U postgres -p 5416 -c "SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';"
```

---

## 🌐 STEP 9: Environment helper scripts

Scripts to easily switch between PG16 and PG18 instances in a terminal session.

### pg16-env.sh

```bash
#!/bin/bash
# pg16-env.sh — set environment for PG16

PG_VERSION=16
PG_BASE=/usr/pgsql-${PG_VERSION}
PG_DATA=/postgres/${PG_VERSION}/data
PG_WAL=/postgres/${PG_VERSION}/wal
PG_PORT=5416

export PATH="${PG_BASE}/bin:$PATH"
export PGDATA="${PG_DATA}"
export PGPORT="${PG_PORT}"

echo "=== PostgreSQL ${PG_VERSION} environment ==="
echo "PATH   : $PATH"
echo "PGDATA : $PGDATA"
echo "PGPORT : $PGPORT"
echo "Binary : $(which initdb) → $(initdb --version)"
```

### pg18-env.sh

```bash
#!/bin/bash
# pg18-env.sh — set environment for PG18

PG_VERSION=18
PG_BASE=/usr/pgsql-${PG_VERSION}
PG_DATA=/postgres/${PG_VERSION}/data
PG_WAL=/postgres/${PG_VERSION}/wal
PG_PORT=5432

export PATH="${PG_BASE}/bin:$PATH"
export PGDATA="${PG_DATA}"
export PGPORT="${PG_PORT}"

echo "=== PostgreSQL ${PG_VERSION} environment ==="
echo "PATH   : $PATH"
echo "PGDATA : $PGDATA"
echo "PGPORT : $PGPORT"
echo "Binary : $(which initdb) → $(initdb --version)"
```

Usage:

```bash
# Switch to PG16
source pg16-env.sh
psql -U postgres -c "SELECT version();"

# Switch to PG18
source pg18-env.sh
psql -U postgres -c "SELECT version();"
```

---

## 📋 Summary — two instances ready for benchmark

| | PostgreSQL 16 | PostgreSQL 18 |
|---|---|---|
| **Port** | 5416 | 5432 |
| **I/O model** | synchronous (no AIO) | Async Worker |
| **Data dir** | `/postgres/16/data` | `/postgres/18/data` |
| **WAL dir** | `/postgres/16/wal` | `/postgres/18/wal` |
| **Binary dir** | `/usr/pgsql-16/bin` | `/usr/pgsql-18/bin` |
| **Service** | `postgresql-16` | `postgresql-18` |
| **systemd override** | `PGDATA=/postgres/16/data` | `PGDATA=/postgres/18/data` |
| **Env script** | `source pg16-env.sh` | `source pg18-env.sh` |
| **Benchmark role** | BASELINE | TEST |

---

## ➡️ Next step

```bash
# Run test data setup on PG16
psql -U postgres -p 5416 -f sql/01_setup_test_data.sql

# Run test data setup on PG18
psql -U postgres -p 5432 -f sql/01_setup_test_data.sql
```

Then run the benchmark: `sql/02_benchmark_run.sql`

---

## 🔧 Troubleshooting

### Error: port 5416 already in use
```bash
sudo ss -tlnp | grep 5416
# If something occupies the port — identify it and stop it or change port
```

### Error: "initdb: error: directory ... exists"
```bash
# Data directory already exists — remove and reinitialize
sudo rm -rf /postgres/16/data/*
sudo rm -rf /postgres/16/wal/*
sudo -u postgres /usr/pgsql-16/bin/initdb \
  -D /postgres/16/data \
  -X /postgres/16/wal \
  -E UTF8 \
  -W
```

### Error: "could not connect to server"
```bash
# Check PG16 logs
sudo journalctl -u postgresql-16 -n 50
sudo tail -50 /postgres/16/data/log/postgresql-$(date +%Y-%m-%d).log
```

### Error: PG16 won't start after PGDATA change
```bash
# Check if systemd override is correct
cat /etc/systemd/system/postgresql-16.service.d/override.conf
# Should contain:
# [Service]
# Environment=PGDATA=/postgres/16/data

# Reload systemd and restart
sudo systemctl daemon-reload
sudo systemctl restart postgresql-16
```

### Verify PGDG has PG16 for OL8
```bash
sudo dnf info postgresql16-server
```
