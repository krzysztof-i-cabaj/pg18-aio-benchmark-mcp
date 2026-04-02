# 🚀 PostgreSQL 16 vs 18 — Async I/O Benchmark

![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16.13-336791?logo=postgresql&logoColor=white)
![PostgreSQL 18](https://img.shields.io/badge/PostgreSQL-18.0-336791?logo=postgresql&logoColor=white)
![io_method](https://img.shields.io/badge/io__method-worker-10b981)
![Status](https://img.shields.io/badge/Status-Completed-success)
![AI Agent](https://img.shields.io/badge/AI_Agent-MCP-8b5cf6)
![License](https://img.shields.io/badge/License-MIT-yellow)

🇵🇱 [Wersja polska / Polish version](README_PL.md)

> **Bitmap Heap Scan 2.29x faster. Sequential Scan +26%. Zero SQL changes.**
> Measured on a real environment — PG16 vs PG18 Async I/O, fully automated by an AI Developer Agent (MCP).

📊 **[VIEW LIVE DASHBOARD (GitHub Pages)](https://krzysztof-i-cabaj.github.io/pg18-aio-benchmark-mcp/)**

---

## 📖 Table of Contents

1. [What is Async I/O in PostgreSQL 18?](#-what-is-async-io-in-postgresql-18)
2. [Benchmark Results](#-benchmark-results)
3. [How It Was Run — The AI Agent](#-how-it-was-run--the-ai-agent)
4. [MCP Configuration](#-mcp-configuration)
5. [How to Reproduce](#️-how-to-reproduce)
6. [Repository Structure](#-repository-structure)
7. [Author](#-author)

---

## 🔬 What is Async I/O in PostgreSQL 18?

Up to version 17, PostgreSQL used **synchronous I/O** — during every data block read from disk, the backend process was **blocked** and waited for the OS-level operation to complete. Only then could it continue processing.

### Old model (PG16, PG17 — Synchronous):

```
Thread --> requests block from disk --> [blocks and waits] --> receives data --> processes
```

### New model (PG18 — Async Worker):

```
Thread --> sends I/O request --> immediately processes other data
                              --> receives block when ready --> processes
```

### What does this mean in practice?

| Feature | PG16/17 (Sync) | PG18 (Async Worker) |
|:---|:---:|:---:|
| I/O model | Blocking | Non-blocking |
| Block prefetch | None | Yes (read-ahead) |
| Parallel I/O requests | No | Yes |
| Configuration parameter | — | `io_method = worker / io_uring` |

### Key parameter — `io_method`

PostgreSQL 18 introduces a new `postgresql.conf` parameter:

```ini
io_method = sync      # old model (default fallback)
io_method = worker    # new: async workers (works everywhere)
io_method = io_uring  # fastest: requires Linux kernel 5.1+ with io_uring
```

On systems without `io_uring` (e.g. older kernels, WSL2), `worker` mode is sufficient
— and still delivers measurable speedup, as confirmed by our tests.

---

## 📊 Benchmark Results

**Test environment:**
- System: Oracle Linux 8.8 (kernel 5.4), VirtualBox
- PostgreSQL 16.13 — port `5416` — `io_method = sync` (baseline)
- PostgreSQL 18.0 — port `5432` — `io_method = worker` (test)
- Parameters: `shared_buffers = 256MB`, `work_mem = 4MB` (identical!)
- Data: `pgbench -s 100` (~1.5 GB) + custom table `benchmark.fakty` (5M rows, 945 MB)
- Methodology: **3 runs per test**, buffer reset before each (`DISCARD ALL`)

### Results Table

| Test | PG16 (ms) | PG18 (ms) | Speedup | Multiplier |
|:---|---:|---:|:---:|:---:|
| **Bitmap Heap Scan** | 1184.7 | 517.6 | **+56.3%** | **2.29x** |
| **Sequential Scan (5M rows)** | 2457.8 | 1823.2 | **+25.8%** | **1.35x** |
| **VACUUM (500K dead tuples)** | 22 140 | 22 270 | -0.6% | ~1.0x |

### Conclusions

**Bitmap Heap Scan (+56%)** — the biggest AIO beneficiary. This operation reads many
non-contiguous blocks identified by a bitmap index. The async worker prefetches them
in parallel — instead of blocking on each block individually.

**Sequential Scan (+26%)** — full table scan benefits from read-ahead (prefetching
subsequent blocks before the current block finishes processing).

**VACUUM (~0%)** — within statistical error margin. VACUUM is a complex operation
(dead tuple identification, writes, visibility map updates) — the I/O gain alone
is marginal relative to the overall cost.

> **Fair note:** Tests were conducted on a virtual environment (VirtualBox).
> On physical hardware with fast NVMe or in the cloud, results may be even better.

---

## 🤖 How It Was Run — The AI Agent

The entire benchmark — from environment setup to report generation —
was **fully automated by an AI Developer Agent**.

### Approach:

```
[User + AI Agent (MCP)]
         |
         +--> Environment verification PG16 / PG18
         +--> Data generation (pgbench + custom 5M row table)
         +--> Test execution (3 runs * 3 tests * 2 databases = 18 measurements)
         +--> EXPLAIN JSON result parsing (Python)
         +--> INSERT into benchmark.pomiary table
         +--> SQL — speedup calculation
         +--> Report generation: Markdown + HTML Dashboard
```

### Automation files (`agent/` directory):

| File | Description |
|:---|:---|
| `benchmark_agent.md` | Prompt defining the AI Agent's tasks (step-by-step instructions) |
| `run_benchmark.sh` | Bash script running all test queries |
| `parse_results.py` | EXPLAIN JSON results parser → SQL INSERT |
| `insert_results.sql` | Generated INSERT statements with measurement data |
| `report_query.sql` | SQL query calculating % speedup between PG16 and PG18 |

---

## 🔗 MCP Configuration

**MCP (Model Context Protocol)** is a standard that enables AI Agents
to communicate directly with external systems — including databases.

### How to connect an AI Agent to PostgreSQL:

**1. Install the MCP package for PostgreSQL:**

```bash
npx -y mcp-postgres-server
```

**2. Configure `.mcp.json`** (or `mcpServers` in client settings):

```json
{
  "mcpServers": {
    "postgres16": {
      "command": "npx",
      "args": ["-y", "mcp-postgres-server"],
      "env": {
        "POSTGRES_CONNECTION_STRING": "postgresql://postgres:YOUR_PASSWORD@HOST:5416/postgres"
      }
    },
    "postgres18": {
      "command": "npx",
      "args": ["-y", "mcp-postgres-server"],
      "env": {
        "POSTGRES_CONNECTION_STRING": "postgresql://postgres:YOUR_PASSWORD@HOST:5432/postgres"
      }
    }
  }
}
```

> **Security:** Store passwords in environment variables or in a
> `mcp_env.sh` file with `chmod 600` permissions. Never commit passwords to Git.

Example `mcp_env.sh`:

```bash
export PG16_URI="postgresql://postgres@127.0.0.1:5416/postgres"
export PG18_URI="postgresql://postgres@127.0.0.1:5432/postgres"
```

---

## 🛠️ How to Reproduce

### Requirements
- Two PostgreSQL instances (16 and 18) running simultaneously on different ports
- Linux kernel 5.1+ (for `io_uring`) or any kernel (for `io_method = worker`)
- ~4 GB free disk space
- `pgbench` available in PATH or via full path (`/usr/pgsql-16/bin/pgbench`)

Detailed installation guide for Oracle Linux 8.8 → see [`INSTALL_PG16.md`](./INSTALL_PG16.md)

### Step 1 — Generate test data

```bash
# pgbench data (~1.5 GB)
/usr/pgsql-16/bin/pgbench -i -s 100 -p 5416 -U postgres postgres
/usr/pgsql-18/bin/pgbench -i -s 100 -p 5432 -U postgres postgres

# Custom fact table (5M rows, 945 MB)
psql -p 5416 -U postgres -f sql/01_setup_test_data.sql
psql -p 5432 -U postgres -f sql/01_setup_test_data.sql
```

### Step 2 — Clear OS cache (optional, for cleaner results)

```bash
sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
```

### Step 3 — Run the benchmark

```bash
# Manual SQL script execution:
psql -p 5416 -U postgres -f sql/02_benchmark_run.sql
psql -p 5432 -U postgres -f sql/02_benchmark_run.sql

# Or automated script:
bash agent/run_benchmark.sh
```

### Step 4 — Parse results and generate report

```bash
python3 agent/parse_results.py
psql -p 5432 -U postgres -f agent/insert_results.sql
psql -p 5432 -U postgres -f agent/report_query.sql
```

---

## 📂 Repository Structure

```
.
├── README.md                    <- this file (English)
├── README_PL.md                 <- Polish version
├── INSTALL_PG16.md              <- PG16 installation guide (alongside PG18)
├── INSTALL_PG16_PL.md           <- installation guide (Polish)
├── LICENSE                      <- MIT License
├── .mcp.json                    <- MCP configuration for AI Agent (template)
├── mcp_env.sh                   <- environment variables (template, no passwords)
│
├── sql/
│   ├── 01_setup_test_data.sql   <- benchmark schema + 5M row table
│   ├── 02_benchmark_run.sql     <- main benchmark script (seq scan, bitmap, vacuum)
│   ├── 03_save_results.sql      <- save results to benchmark.pomiary
│   └── 04_compare_results.sql   <- PG16 vs PG18 comparison with % speedup
│
├── agent/
│   ├── benchmark_agent.md       <- AI Agent prompt (main "work instructions")
│   ├── run_benchmark.sh         <- test automation script
│   ├── parse_results.py         <- JSON → SQL INSERT parser
│   ├── insert_results.sql       <- generated measurement data
│   └── report_query.sql         <- comparison query
│
├── reports/
│   └── benchmark_report_20260402.md    <- results report
│
└── docs/
    └── index.html               <- interactive dashboard (GitHub Pages)
```

---

## 👤 Author

**KCB Kris** — DBA Oracle & PostgreSQL

LinkedIn: [krzysztof-cabaj-16b6a52](https://www.linkedin.com/in/krzysztof-cabaj-16b6a52/)

---

*Project created: 2026-04-01 | Benchmark executed: 2026-04-02*
*Automation: AI Developer Agent + MCP PostgreSQL*
