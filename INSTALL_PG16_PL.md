# Instrukcja instalacji PostgreSQL 16 obok PG18 na Oracle Linux 8.8

**Środowisko:** Oracle Linux 8.8 | VirtualBox
**Cel:** PG16 na porcie **5416** (baseline) + PG18 na porcie **5432** (test)
**Autor:** KCB Kris | Data: 2026-04-01

🇬🇧 [English version](INSTALL_PG16.md)

---

## 🔍 Przed instalacją — sprawdź stan obecny

```bash
# Co jest zainstalowane?
rpm -qa | grep postgresql

# Jaki port zajmuje PG18?
sudo -u postgres psql -c "SHOW port;"

# Sprawdz wersje PG18
sudo -u postgres psql -c "SELECT version();"

# Sprawdz data directory PG18
sudo -u postgres psql -c "SHOW data_directory;"
```

Upewnij się, że PG18 działa na porcie **5432** — PG16 zainstalujemy na **5416**.

---

## 📦 KROK 1: Dodaj repozytorium PGDG (PostgreSQL 16)

```bash
# Dodaj oficjalne repozytorium PostgreSQL Global Development Group
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Wylacz modul postgresql z AppStream (zeby nie kolidowal z PGDG)
sudo dnf -qy module disable postgresql

# Sprawdz ze repozytorium jest dostepne
sudo dnf repolist | grep pgdg
```

Oczekiwany wynik — powinienes zobaczyc m.in.:
```
pgdg16    PostgreSQL 16 for RHEL/Rocky/AlmaLinux 8
pgdg18    PostgreSQL 18 for RHEL/Rocky/AlmaLinux 8
```

---

## 📦 KROK 2: Instalacja pakietow PostgreSQL 16

```bash
# Instalacja serwera i klienta PG16
sudo dnf install -y postgresql16-server postgresql16

# Weryfikacja — sprawdz zainstalowane pakiety
rpm -qa | grep postgresql16

# Sprawdz gdzie jest binary PG16
/usr/pgsql-16/bin/postgres --version
```

Oczekiwany wynik:
```
postgres (PostgreSQL) 16.x
```

---

## 🗄️ KROK 3: Inicjalizacja klastra PG16 (custom paths — jak PG18)

Zamiast `postgresql-16-setup initdb` (domyslne sciezki `/var/lib/pgsql/16/data/`),
uzywamy bezposredniego `initdb` z dedykowanymi katalogami — identycznie jak PG18.

```bash
# Utworz katalogi na dane i WAL
sudo mkdir -p /postgres/16/data
sudo mkdir -p /postgres/16/wal
sudo chown -R postgres:postgres /postgres/16/

# Inicjalizacja — identyczna skladnia jak przy PG18
sudo -u postgres /usr/pgsql-16/bin/initdb \
  -D /postgres/16/data \
  -X /postgres/16/wal \
  -E UTF8 \
  -W

# Sprawdz ze katalog istnieje i ma poprawnego wlasciciela
ls -la /postgres/16/data/
ls -la /postgres/16/wal/
```

> **UWAGA:** Flaga `-W` wymusza podanie hasla superusera podczas initdb.
> Flaga `-X` przenosi WAL na osobna sciezke (jak przy PG18: `/postgres/18/wal`).

---

## ⚙️ KROK 4: Konfiguracja postgresql.conf dla PG16

```bash
# Edytuj konfiguracje PG16
sudo nano /postgres/16/data/postgresql.conf
```

Znajdz i zmien (lub dodaj) nastepujace parametry:

```ini
# -----------------------------------------------
# PORT — kluczowe! PG18 zajmuje 5432
# -----------------------------------------------
port = 5416

# -----------------------------------------------
# Pamiec — ustaw IDENTYCZNIE jak PG18 (dla fair benchmark)
# -----------------------------------------------
shared_buffers = 256MB
work_mem = 4MB
maintenance_work_mem = 64MB

# -----------------------------------------------
# I/O — PG16 uzywa synchronicznego I/O (brak io_method)
# Nie ma parametru io_method w PG16 — to jest wlasnie baseline
# -----------------------------------------------

# -----------------------------------------------
# Statystyki — potrzebne do benchmarku
# -----------------------------------------------
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
track_io_timing = on

# -----------------------------------------------
# Logi (opcjonalnie, pomocne przy diagnozie)
# -----------------------------------------------
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
```

Zapisz plik (Ctrl+O, Enter, Ctrl+X w nano).

> **WAZNE:** Sprawdz jakie wartosci ma PG18 i ustaw identyczne w PG16:
> ```bash
> sudo -u postgres psql -c "SHOW shared_buffers; SHOW work_mem;"
> ```

---

## 🔐 KROK 5: Konfiguracja pg_hba.conf dla PG16

```bash
sudo nano /postgres/16/data/pg_hba.conf
```

Upewnij sie ze sa wpisy (zazwyczaj juz sa po initdb):

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
```

> Uzywamy `trust` tylko lokalnie na srodowisku testowym — nigdy na produkcji!

---

## 🚀 KROK 6: Konfiguracja systemd i uruchomienie PG16

Poniewaz uzywamy niestandardowego PGDATA (`/postgres/16/data` zamiast `/var/lib/pgsql/16/data`),
musimy nadpisac konfiguracje serwisu systemd.

```bash
# Nadpisz PGDATA w usludze systemd (tworzy override.conf)
sudo systemctl edit postgresql-16
```

W edytorze wpisz dokladnie:

```ini
[Service]
Environment=PGDATA=/postgres/16/data
```

Zapisz i zamknij edytor. Sprawdz ze override zostal zapisany:

```bash
cat /etc/systemd/system/postgresql-16.service.d/override.conf
```

Teraz uruchom serwis:

```bash
# Przeladuj konfiguracje systemd (po edycji)
sudo systemctl daemon-reload

# Wlacz autostart i uruchom PG16
sudo systemctl enable postgresql-16
sudo systemctl start postgresql-16

# Sprawdz status
sudo systemctl status postgresql-16

# Sprawdz ze PG16 nasluchuje na porcie 5416
sudo ss -tlnp | grep 5416
```

Oczekiwany wynik `ss`:
```
LISTEN   0   128   0.0.0.0:5416   0.0.0.0:*   users:(("postgres",pid=XXXX,...))
```

---

## ✅ KROK 7: Weryfikacja obu instancji

```bash
# Polaczenie z PG16 (port 5416)
psql -U postgres -p 5416 -c "SELECT version(); SHOW port;"

# Polaczenie z PG18 (port 5432)
psql -U postgres -p 5432 -c "SELECT version(); SHOW port; SHOW io_method;"
```

Oczekiwany wynik:
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

## 🔧 KROK 8: Instalacja pg_stat_statements na PG16

```bash
psql -U postgres -p 5416 -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
psql -U postgres -p 5416 -c "SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';"
```

---

## 🌐 KROK 9: Skrypty srodowiskowe (env)

Skrypty ulatwiajace przelaczanie miedzy instancjami PG16 i PG18 w sesji terminala.

### pg16-env.sh

```bash
#!/bin/bash
# pg16-env.sh — ustaw srodowisko dla PG16

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
# pg18-env.sh — ustaw srodowisko dla PG18

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

Uzycie:

```bash
# Przelacz na PG16
source pg16-env.sh
psql -U postgres -c "SELECT version();"

# Przelacz na PG18
source pg18-env.sh
psql -U postgres -c "SELECT version();"
```

---

## 📋 Podsumowanie — dwie instancje gotowe do benchmarku

| | PostgreSQL 16 | PostgreSQL 18 |
|---|---|---|
| **Port** | 5416 | 5432 |
| **I/O model** | synchroniczny (brak AIO) | Async Worker |
| **Data dir** | `/postgres/16/data` | `/postgres/18/data` |
| **WAL dir** | `/postgres/16/wal` | `/postgres/18/wal` |
| **Binary dir** | `/usr/pgsql-16/bin` | `/usr/pgsql-18/bin` |
| **Serwis** | `postgresql-16` | `postgresql-18` |
| **systemd override** | `PGDATA=/postgres/16/data` | `PGDATA=/postgres/18/data` |
| **Env script** | `source pg16-env.sh` | `source pg18-env.sh` |
| **Rola w benchmarku** | BASELINE | TEST |

---

## ➡️ Nastepny krok

```bash
# Uruchom setup danych testowych na PG16
psql -U postgres -p 5416 -f sql/01_setup_test_data.sql

# Uruchom setup danych testowych na PG18
psql -U postgres -p 5432 -f sql/01_setup_test_data.sql
```

Nastepnie uruchom benchmark: `sql/02_benchmark_run.sql`

---

## 🔧 Rozwiazywanie problemow / Troubleshooting

### Blad: port 5416 zajety
```bash
sudo ss -tlnp | grep 5416
# Jesli cos zajmuje port — sprawdz co to i zatrzymaj lub zmien port na 5416
```

### Blad: "initdb: error: directory ... exists"
```bash
# Data directory juz istnieje — usun i zainicjalizuj ponownie
sudo rm -rf /postgres/16/data/*
sudo rm -rf /postgres/16/wal/*
sudo -u postgres /usr/pgsql-16/bin/initdb \
  -D /postgres/16/data \
  -X /postgres/16/wal \
  -E UTF8 \
  -W
```

### Blad: "could not connect to server"
```bash
# Sprawdz logi PG16
sudo journalctl -u postgresql-16 -n 50
sudo tail -50 /postgres/16/data/log/postgresql-$(date +%Y-%m-%d).log
```

### Blad: PG16 nie startuje po zmianie PGDATA
```bash
# Sprawdz czy systemd override jest poprawny
cat /etc/systemd/system/postgresql-16.service.d/override.conf
# Powinien zawierac:
# [Service]
# Environment=PGDATA=/postgres/16/data

# Przeladuj systemd i uruchom ponownie
sudo systemctl daemon-reload
sudo systemctl restart postgresql-16
```

### Sprawdz czy PGDG ma PG16 dla OL8
```bash
sudo dnf info postgresql16-server
```
