-- ==============================================================================
-- Tytul:        02_benchmark_run.sql
-- Opis:         Glowny skrypt benchmarkowy — mierzy czas 3 typow operacji I/O:
--               sequential scan, bitmap heap scan, VACUUM.
--               Uruchom dwukrotnie: raz z io_method=sync, raz z io_method=worker.
-- Description [EN]: Main benchmark script — measures 3 I/O operation types:
--               sequential scan, bitmap heap scan, VACUUM.
--               Run twice: once with io_method=sync, once with io_method=worker.
--
-- Autor:        KCB Kris
-- Data:         2026-04-01
-- Wersja:       1.0
--
-- Wymagania [PL]:    - PostgreSQL 18.0
--                    - Schemat benchmark musi istniec (uruchom 01_setup_test_data.sql)
--                    - WAZNE: przed uruchomieniem wyczysc cache OS:
--                        sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
--                    - WAZNE: zmien io_method w postgresql.conf i zrestartuj PG
-- Requirements [EN]: - PostgreSQL 18.0
--                    - benchmark schema must exist (run 01_setup_test_data.sql first)
--                    - IMPORTANT: clear OS cache before running:
--                        sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
--                    - IMPORTANT: set io_method in postgresql.conf and restart PG
--
-- Uzycie [PL]:       psql -U postgres -v IO_METHOD=sync    -f 02_benchmark_run.sql
--                    psql -U postgres -v IO_METHOD=worker  -f 02_benchmark_run.sql
-- Usage [EN]:        psql -U postgres -v IO_METHOD=sync    -f 02_benchmark_run.sql
--                    psql -U postgres -v IO_METHOD=worker  -f 02_benchmark_run.sql
-- ==============================================================================

-- Ustaw zmienna IO_METHOD jesli nie podano przez -v
-- Set IO_METHOD variable if not provided via -v
\if :{?IO_METHOD}
\else
    \set IO_METHOD 'worker'
\endif

\echo ''
\echo '============================================================================'
\echo '  BENCHMARK: PostgreSQL 18 Async I/O'
\echo '  io_method: ' :IO_METHOD
\echo '============================================================================'

-- Weryfikacja aktualnego io_method
-- Verify current io_method
\echo ''
\echo '--- Weryfikacja konfiguracji / Configuration check ---'
SHOW io_method;
SHOW shared_buffers;
SELECT version();

-- Reset statystyk I/O dla czystego pomiaru
-- Reset I/O stats for clean measurement
SELECT pg_stat_reset_shared('io');

-- ============================================================================
-- SEKCJA 1: TEST A — Sequential Scan (pelny przeglad tabeli)
-- SECTION 1: TEST A — Sequential Scan (full table scan)
-- ============================================================================

\echo ''
\echo '============================================================================'
\echo '  TEST A: Sequential Scan — pelny przeglad 5M wierszy'
\echo '============================================================================'

-- Wymuszamy sequential scan (wylaczamy index scan na potrzeby testu)
-- Force sequential scan (disable index scan for this test)
SET enable_indexscan  = off;
SET enable_bitmapscan = off;

-- Pomiar 1: Agregacja na pelnej tabeli
-- Measurement 1: Aggregation on full table
\timing on

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    kategoria,
    COUNT(*)            AS liczba,
    AVG(wartosc)        AS srednia_wartosc,
    SUM(wartosc)        AS suma_wartosc
FROM benchmark.fakty
GROUP BY kategoria
ORDER BY liczba DESC;

\timing off

-- Zapis wynikow — uzytkownik wpisuje recznie lub uzywamy INSERT z \gset
-- Save results (manual entry or use psql \gset trick)
\echo ''
\echo '>>> Przepisz czas z powyzszego EXPLAIN ANALYZE (Execution Time: X ms)'
\echo '>>> do tabeli wynikow (skrypt 03_save_results.sql)'

-- ============================================================================
-- SEKCJA 2: TEST B — Bitmap Heap Scan (zakres dat, niska selektywnosc)
-- SECTION 2: TEST B — Bitmap Heap Scan (date range, low selectivity)
-- ============================================================================

\echo ''
\echo '============================================================================'
\echo '  TEST B: Bitmap Heap Scan — zakres dat (20% wierszy)'
\echo '============================================================================'

SET enable_indexscan  = on;
SET enable_bitmapscan = on;
SET enable_seqscan    = off;

\timing on

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    COUNT(*)            AS liczba_wierszy,
    AVG(wartosc)        AS srednia,
    MIN(data_zdarz)     AS pierwsza_data,
    MAX(data_zdarz)     AS ostatnia_data
FROM benchmark.fakty
WHERE data_zdarz BETWEEN '2021-01-01' AND '2021-12-31';

\timing off

SET enable_seqscan = on;

\echo ''
\echo '>>> Przepisz czas z powyzszego EXPLAIN ANALYZE'

-- ============================================================================
-- SEKCJA 3: TEST C — VACUUM (czyszczenie martwych krotek)
-- SECTION 3: TEST C — VACUUM (dead tuple cleanup)
-- ============================================================================

\echo ''
\echo '============================================================================'
\echo '  TEST C: VACUUM — generowanie i czyszczenie martwych krotek'
\echo '============================================================================'

-- Wygenerowanie martwych krotek (UPDATE 10% wierszy)
-- Generate dead tuples (UPDATE 10% of rows)
\echo '[C.1] Generowanie martwych krotek (UPDATE 500K wierszy)...'
UPDATE benchmark.fakty
SET wartosc = wartosc * 1.01
WHERE id % 10 = 0;

-- Pomiar VACUUM
-- VACUUM timing
\echo '[C.2] Pomiar VACUUM...'
\timing on

VACUUM (VERBOSE, ANALYZE) benchmark.fakty;

\timing off

\echo ''
\echo '>>> Przepisz czas VACUUM z powyzszego outputu'

-- ============================================================================
-- SEKCJA 4: Statystyki I/O po testach
-- SECTION 4: I/O statistics after tests
-- ============================================================================

\echo ''
\echo '============================================================================'
\echo '  STATYSTYKI I/O (pg_stat_io) — po wszystkich testach'
\echo '============================================================================'

SELECT
    backend_type        AS typ_backendu,
    object              AS obiekt,
    context             AS kontekst,
    reads               AS odczyty,
    read_time           AS czas_odczytu_ms,
    writes              AS zapisy,
    write_time          AS czas_zapisu_ms,
    hits                AS trafienia_cache,
    evictions           AS wyrzucenia_z_cache
FROM pg_stat_io
WHERE reads > 0
  AND backend_type IN ('client backend', 'autovacuum worker', 'background worker')
ORDER BY reads DESC
LIMIT 20;

\echo ''
\echo '============================================================================'
\echo '  KONIEC BENCHMARKU dla io_method = ' :IO_METHOD
\echo '  Zapisz wyniki: psql -U postgres -f 03_save_results.sql'
\echo '============================================================================'
\echo ''
