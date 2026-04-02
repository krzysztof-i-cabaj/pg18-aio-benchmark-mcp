# Prompt agenta benchmarkowego / Benchmark Agent Prompt

## Cel / Goal

Jesteś agentem DBA automatyzującym benchmark wydajnościowy PostgreSQL 16 vs PostgreSQL 18.
Masz dostęp do dwóch instancji PostgreSQL przez MCP:
- **postgres16** — PostgreSQL 16 na porcie 5416 (baseline, synchroniczny I/O)
- **postgres18** — PostgreSQL 18 na porcie 5432 (test, Async I/O worker mode)

---

## Zadania do wykonania / Tasks

### ETAP 1 — Weryfikacja środowiska

1. Połącz się z **postgres16** i wykonaj:
   ```sql
   SELECT version();
   SHOW port;
   SHOW shared_buffers;
   SHOW work_mem;
   ```

2. Połącz się z **postgres18** i wykonaj:
   ```sql
   SELECT version();
   SHOW port;
   SHOW shared_buffers;
   SHOW work_mem;
   SHOW io_method;
   ```

3. Potwierdź że obie instancje mają **identyczne** `shared_buffers` i `work_mem`.
   Jeśli różne — zapisz to w raporcie jako ograniczenie benchmarku.

---

### ETAP 2 — Przygotowanie schematu testowego (jeśli nie istnieje)

Na **obu instancjach** sprawdź czy schemat `benchmark` istnieje:
```sql
SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'benchmark';
```

Jeśli nie istnieje — poinformuj użytkownika żeby uruchomił ręcznie:
```bash
psql -U postgres -p 5416 -f sql/01_setup_test_data.sql
psql -U postgres -p 5432 -f sql/01_setup_test_data.sql
```
i poczekaj na potwierdzenie.

---

### ETAP 3 — Benchmark Sequential Scan

Wykonaj na **postgres16**, powtórz 3 razy, zapisz każdy wynik:
```sql
-- Reset buforów przed każdym testem
DISCARD ALL;

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT kategoria, COUNT(*), AVG(wartosc), SUM(wartosc)
FROM benchmark.fakty
GROUP BY kategoria
ORDER BY COUNT(*) DESC;
```

Powtórz identycznie na **postgres18**.

Wyodrębnij z wyniku JSON:
- `Execution Time` (ms)
- `Shared Hit Blocks`
- `Shared Read Blocks`

---

### ETAP 4 — Benchmark Bitmap Heap Scan

Na **obu instancjach**, 3 razy:
```sql
DISCARD ALL;

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT COUNT(*), AVG(wartosc), MIN(data_zdarz), MAX(data_zdarz)
FROM benchmark.fakty
WHERE data_zdarz BETWEEN '2021-01-01' AND '2021-12-31';
```

---

### ETAP 5 — Benchmark VACUUM

Na **obu instancjach**:

```sql
-- Wygeneruj martwe krotki
UPDATE benchmark.fakty SET wartosc = wartosc * 1.01 WHERE id % 10 = 0;
```

Zmierz czas VACUUM:
```sql
VACUUM (ANALYZE, VERBOSE) benchmark.fakty;
```

Zapisz czas z outputu VACUUM (`system usage: CPU ...`).

---

### ETAP 6 — Zapis wyników do tabeli

Na **obu instancjach** zapisz wyniki do `benchmark.pomiary`:
```sql
INSERT INTO benchmark.pomiary (io_method, test_name, run_no, czas_ms, shared_hit, shared_read, uwagi)
VALUES (:io_method, :test_name, :run_no, :czas_ms, :shared_hit, :shared_read, :uwagi);
```

---

### ETAP 7 — Generowanie raportu

Wykonaj na **postgres18** (ma oba zestawy danych lub użyj wyników z ETAP 3-5):

```sql
WITH srednie AS (
    SELECT test_name, io_method, ROUND(AVG(czas_ms), 1) AS avg_ms
    FROM benchmark.pomiary WHERE czas_ms > 0
    GROUP BY test_name, io_method
),
baseline AS (SELECT test_name, avg_ms AS ms_pg16 FROM srednie WHERE io_method = 'pg16'),
test_run AS (SELECT test_name, avg_ms AS ms_pg18 FROM srednie WHERE io_method = 'worker')
SELECT
    t.test_name,
    b.ms_pg16,
    t.ms_pg18,
    ROUND((b.ms_pg16 - t.ms_pg18) / b.ms_pg16 * 100, 1) AS speedup_pct,
    ROUND(b.ms_pg16 / t.ms_pg18, 2) AS speedup_x
FROM test_run t JOIN baseline b USING (test_name)
ORDER BY speedup_pct DESC;
```

---

### ETAP 8 — Raport Markdown

Wygeneruj plik `reports/benchmark_report_YYYYMMDD.md` z:

```markdown
# PostgreSQL 16 vs 18 — Async I/O Benchmark
**Data:** {data}
**Środowisko:** Oracle Linux 8.8, kernel 5.4, VirtualBox
**PG16:** {wersja} | port 5416 | I/O: sync
**PG18:** {wersja} | port 5432 | I/O: worker (Async)

## Wyniki

| Test | PG16 (ms) | PG18 (ms) | Przyspieszenie |
|------|-----------|-----------|----------------|
| Sequential Scan | X | Y | +Z% |
| Bitmap Heap Scan | X | Y | +Z% |
| VACUUM (500K) | X | Y | +Z% |

## Konfiguracja środowiska
{shared_buffers, work_mem, io_method}

## Wnioski
{auto-generated based on results}
```

---

### ETAP 9 — Draft posta LinkedIn

Wygeneruj plik `linkedin/post_draft.md` z gotowym postem LinkedIn:

```
🚀 PostgreSQL 18 Async I/O — zmierzyłem to sam

[hook oparty na najlepszym wyniku benchmarku]

📊 Wyniki (PG16 vs PG18, identyczne środowisko):
• Sequential Scan 5M wierszy: Xms → Yms (+Z%)
• Bitmap Heap Scan: Xms → Yms (+Z%)
• VACUUM 500K martwych krotek: Xms → Yms (+Z%)

[Jak to działa — 3 zdania o AIO worker mode]

[Co to oznacza dla DBA — praktyczne wnioski]

🔧 Benchmark zautomatyzowany przez Claude Code + MCP PostgreSQL
Skrypty dostępne na GitHub: [link]

#PostgreSQL #DBA #PostgreSQL18 #DatabasePerformance #AsyncIO #AIAgent
```

---

## Zasady / Rules

- Każdy wynik zapisuj z dokładnością do 1 ms
- Każdy test powtarzaj **3 razy** — używaj średniej (ignoruj pierwsze "zimne" uruchomienie)
- Jeśli wynik jest nieoczekiwany (PG18 wolniejszy) — zapisz to uczciwie w raporcie
- Na końcu zapisz wszystkie pliki do katalogu projektu
