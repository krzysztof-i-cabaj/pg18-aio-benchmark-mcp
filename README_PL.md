# 🚀 PostgreSQL 16 vs 18 — Benchmark Asynchronicznego I/O

![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16.13-336791?logo=postgresql&logoColor=white)
![PostgreSQL 18](https://img.shields.io/badge/PostgreSQL-18.0-336791?logo=postgresql&logoColor=white)
![io_method](https://img.shields.io/badge/io__method-worker-10b981)
![Status](https://img.shields.io/badge/Status-Completed-success)
![AI Agent](https://img.shields.io/badge/AI_Agent-MCP-8b5cf6)
![License](https://img.shields.io/badge/License-MIT-yellow)

🇬🇧 [English version](README.md)

> **Bitmap Heap Scan 2.29x szybciej. Sequential Scan +26%. Zero zmian w SQL.**
> Zmierzone na własnym środowisku — PG16 vs PG18 Async I/O, zautomatyzowane przez AI Developer Agenta (MCP).

📊 **[LIVE DASHBOARD — Interaktywny raport wyników (GitHub Pages)](https://krzysztof-i-cabaj.github.io/pg18-aio-benchmark-mcp/)**

---

## 📖 Spis Treści

1. [Czym jest Async I/O w PostgreSQL 18?](#-czym-jest-async-io-w-postgresql-18)
2. [Wyniki Benchmarku](#-wyniki-benchmarku)
3. [Jak to zostało uruchomione — rola AI Agenta](#-jak-to-zostało-uruchomione--rola-ai-agenta)
4. [Konfiguracja MCP (połączenie AI z bazą)](#-konfiguracja-mcp)
5. [Jak odtworzyć test we własnym środowisku](#️-jak-odtworzyć-test)
6. [Struktura Repozytorium](#-struktura-repozytorium)
7. [Autor](#-autor)

---

## 🔬 Czym jest Async I/O w PostgreSQL 18?

Do wersji 17 włącznie PostgreSQL używał **synchronicznego I/O** — podczas każdego odczytu bloku danych z dysku wątek procesu był **blokowany** i czekał na zakończenie operacji systemowej. Dopiero po jej zakończeniu mógł kontynuować przetwarzanie.

### Stary model (PG16, PG17 — Synchroniczny):

```
Wątek --> żąda bloku z dysku --> [blokuje się i czeka] --> otrzymuje dane --> przetwarza
```

### Nowy model (PG18 — Asynchroniczny Worker):

```
Wątek --> wysyła żądanie I/O --> natychmiast przetwarza inne dane
                             --> otrzymuje blok gdy gotowy --> przetwarza
```

### Co to oznacza w praktyce?

| Cecha | PG16/17 (Sync) | PG18 (Async Worker) |
|:---|:---:|:---:|
| Model I/O | Blokujący | Nieblokujący |
| Prefetch bloków | Brak | Tak (z wyprzedzeniem) |
| Równoległe żądania I/O | Nie | Tak |
| Parametr konfiguracyjny | — | `io_method = worker / io_uring` |

### Klucz — parametr `io_method`

PostgreSQL 18 wprowadza nowy parametr `postgresql.conf`:

```ini
io_method = sync      # stary model (domyślny fallback)
io_method = worker    # nowy: asynchroniczne workery (działa wszędzie)
io_method = io_uring  # najszybszy: wymaga Linux kernel 5.1+ z io_uring
```

Na systemach bez `io_uring` (np. starsze kernele, WSL2) wystarczy `worker`
— i tak daje mierzalne przyspieszenie, co potwierdzają nasze testy.

---

## 📊 Wyniki Benchmarku

**Środowisko testowe:**
- System: Oracle Linux 8.8 (kernel 5.4), VirtualBox
- PostgreSQL 16.13 — port `5416` — `io_method = sync` (baseline)
- PostgreSQL 18.0 — port `5432` — `io_method = worker` (test)
- Parametry: `shared_buffers = 256MB`, `work_mem = 4MB` (identyczne!)
- Dane: `pgbench -s 100` (~1.5 GB) + własna tabela `benchmark.fakty` (5 mln wierszy, 945 MB)
- Metodologia: **3 przebiegi każdego testu**, reset buforów przed każdym (`DISCARD ALL`)

### Tabela Wyników

| Test | PG16 (ms) | PG18 (ms) | Przyspieszenie | Mnożnik |
|:---|---:|---:|:---:|:---:|
| **Bitmap Heap Scan** | 1184.7 | 517.6 | **+56.3%** | **2.29x** |
| **Sequential Scan 5M wierszy** | 2457.8 | 1823.2 | **+25.8%** | **1.35x** |
| **VACUUM 500K martwych krotek** | 22 140 | 22 270 | -0.6% | ~1.0x |

### Wnioski

**Bitmap Heap Scan (+56%)** — największy beneficjent AIO. Operacja polega na czytaniu
wielu nieciągłych bloków wskazanych przez indeks bitmapowy. Async worker prefetchuje
je równolegle — zamiast czekać na każdy blok z osobna.

**Sequential Scan (+26%)** — pełny skan tabeli przyspiesza dzięki read-ahead (prefetch
kolejnych bloków zanim bieżący blok zostanie przetworzony).

**VACUUM (~0%)** — wynik w granicach błędu statystycznego. VACUUM jest operacją
złożoną (identyfikacja martwych krotek, zapis, aktualizacja VM) — zysk z samego I/O
jest marginalny względem całości.

> **Uczciwa uwaga:** Testy były prowadzone na środowisku wirtualnym (VirtualBox).
> Na sprzęcie fizycznym z szybkim NVMe lub na chmurze wyniki mogą być jeszcze lepsze.

---

## 🤖 Jak to zostało uruchomione — rola AI Agenta

Cały benchmark — od konfiguracji środowiska po generowanie raportów —
został **zautomatyzowany przez AI Developer Agenta**.

### Zastosowane podejście:

```
[Użytkownik + AI Agent (MCP)]
         |
         +--> Weryfikacja środowiska PG16 / PG18
         +--> Generowanie danych (pgbench + własna tabela 5M wierszy)
         +--> Wykonanie testów (3 przebiegi * 3 testy * 2 bazy = 18 pomiarów)
         +--> Parsowanie wyników EXPLAIN JSON (Python)
         +--> INSERT do tabeli benchmark.pomiary
         +--> SQL - obliczenie przyspieszenia
         +--> Generowanie raportu Markdown + HTML Dashboard
```

### Pliki automatyzacji (katalog `agent/`):

| Plik | Opis |
|:---|:---|
| `benchmark_agent.md` | Prompt definiujący zadania dla AI Agenta (instrukcja krok po kroku) |
| `run_benchmark.sh` | Skrypt bash uruchamiający wszystkie zapytania testowe |
| `parse_results.py` | Parser wyników EXPLAIN JSON → SQL INSERT |
| `insert_results.sql` | Wygenerowane instrukcje INSERT z danymi pomiarowymi |
| `report_query.sql` | Zapytanie SQL obliczające % przyspieszenia między PG16 a PG18 |

---

## 🔗 Konfiguracja MCP

**MCP (Model Context Protocol)** to standard umożliwiający AI Agentom
bezpośrednią komunikację z zewnętrznymi systemami — w tym z bazami danych.

### Jak połączyć AI Agenta z bazą PostgreSQL:

**1. Zainstaluj pakiet MCP dla PostgreSQL:**

```bash
npx -y mcp-postgres-server
```

**2. Skonfiguruj plik `.mcp.json`** (lub `mcpServers` w ustawieniach klienta):

```json
{
  "mcpServers": {
    "postgres16": {
      "command": "npx",
      "args": ["-y", "mcp-postgres-server"],
      "env": {
        "POSTGRES_CONNECTION_STRING": "postgresql://postgres:HASLO@HOST:5416/postgres"
      }
    },
    "postgres18": {
      "command": "npx",
      "args": ["-y", "mcp-postgres-server"],
      "env": {
        "POSTGRES_CONNECTION_STRING": "postgresql://postgres:HASLO@HOST:5432/postgres"
      }
    }
  }
}
```

> **Bezpieczeństwo:** Hasła przechowuj w zmiennych środowiskowych lub w pliku
> `mcp_env.sh` z uprawnieniami `chmod 600`. Nigdy nie commituj haseł do Git.

Przykładowy `mcp_env.sh`:

```bash
export PG16_URI="postgresql://postgres@127.0.0.1:5416/postgres"
export PG18_URI="postgresql://postgres@127.0.0.1:5432/postgres"
```

---

## 🛠️ Jak odtworzyć test

### Wymagania
- Dwie instancje PostgreSQL (16 i 18) działające jednocześnie na różnych portach
- Linux kernel 5.1+ (dla `io_uring`) lub dowolny kernel (dla `io_method = worker`)
- ~4 GB wolnego miejsca na dysku
- `pgbench` dostępny w PATH lub przez pełną ścieżkę (`/usr/pgsql-16/bin/pgbench`)

Szczegółowa instrukcja dla Oracle Linux 8.8 → patrz [`INSTALL_PG16_PL.md`](./INSTALL_PG16_PL.md)

### Krok 1 — Generowanie danych

```bash
# Dane pgbench (~1.5 GB)
/usr/pgsql-16/bin/pgbench -i -s 100 -p 5416 -U postgres postgres
/usr/pgsql-18/bin/pgbench -i -s 100 -p 5432 -U postgres postgres

# Własna tabela faktów (5 mln wierszy, 945 MB)
psql -p 5416 -U postgres -f sql/01_setup_test_data.sql
psql -p 5432 -U postgres -f sql/01_setup_test_data.sql
```

### Krok 2 — Wyczyszczenie cache OS (opcjonalne, dla czystszych wyników)

```bash
sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
```

### Krok 3 — Uruchomienie benchmarku

```bash
# Ręcznie skrypt SQL:
psql -p 5416 -U postgres -f sql/02_benchmark_run.sql
psql -p 5432 -U postgres -f sql/02_benchmark_run.sql

# Lub zautomatyzowany skrypt:
bash agent/run_benchmark.sh
```

### Krok 4 — Parsowanie wyników i raport

```bash
python3 agent/parse_results.py
psql -p 5432 -U postgres -f agent/insert_results.sql
psql -p 5432 -U postgres -f agent/report_query.sql
```

---

## 📂 Struktura Repozytorium

```
.
├── README.md                    <- English version
├── README_PL.md                 <- ten plik (wersja polska)
├── INSTALL_PG16.md              <- instrukcja instalacji PG16 obok PG18 (EN)
├── INSTALL_PG16_PL.md           <- instrukcja instalacji (PL)
├── LICENSE                      <- licencja MIT
├── .mcp.json                    <- konfiguracja MCP dla AI Agenta (szablon)
├── mcp_env.sh                   <- zmienne środowiskowe (szablon bez haseł)
│
├── sql/
│   ├── 01_setup_test_data.sql   <- schemat benchmark + tabela 5M wierszy
│   ├── 02_benchmark_run.sql     <- główny skrypt pomiarowy (seq scan, bitmap, vacuum)
│   ├── 03_save_results.sql      <- zapis wyników do benchmark.pomiary
│   └── 04_compare_results.sql   <- porównanie PG16 vs PG18 z % przyspieszenia
│
├── agent/
│   ├── benchmark_agent.md       <- prompt AI Agenta (główne "instrukcje robocze")
│   ├── run_benchmark.sh         <- skrypt automatyzujący testy
│   ├── parse_results.py         <- parser JSON → SQL INSERT
│   ├── insert_results.sql       <- wygenerowane dane pomiarowe
│   └── report_query.sql         <- zapytanie porównawcze
│
├── reports/
│   └── benchmark_report_20260402.md    <- raport wynikowy
│
└── docs/
    └── index.html               <- interaktywny dashboard (GitHub Pages)
```

---

## 👤 Autor

**KCB Kris** — DBA Oracle & PostgreSQL

LinkedIn: [krzysztof-cabaj-16b6a52](https://www.linkedin.com/in/krzysztof-cabaj-16b6a52/)

---

*Projekt stworzony: 2026-04-01 | Benchmark wykonany: 2026-04-02*
*Środowisko automatyzacji: AI Developer Agent + MCP PostgreSQL*
