-- ==============================================================================
-- Tytul:        03_save_results.sql
-- Opis:         Zapis wynikow benchmarku do tabeli benchmark.pomiary.
--               Edytuj wartosci ponizej po kazdym przebiegu (sync/worker/pg16).
-- Description [EN]: Saves benchmark results to benchmark.pomiary table.
--               Edit values below after each run (sync/worker/pg16).
--
-- Autor:        KCB Kris
-- Data:         2026-04-01
-- Wersja:       1.0
--
-- Uzycie [PL]:       psql -U postgres -f 03_save_results.sql
-- Usage [EN]:        psql -U postgres -f 03_save_results.sql
-- ==============================================================================

-- ============================================================================
-- SEKCJA: Wprowadz wyniki z EXPLAIN ANALYZE / Enter results from EXPLAIN ANALYZE
-- ============================================================================

-- EDYTUJ wartosci 'czas_ms' po kazdym przebiegu benchmarku
-- EDIT 'czas_ms' values after each benchmark run

INSERT INTO benchmark.pomiary (io_method, test_name, run_no, czas_ms, uwagi) VALUES

-- === URUCHOMIENIE 1: PG16 lub io_method=sync ===
-- Podmien 'pg16' na faktyczna wersje/konfiguracje
('pg16',   'seqscan_agregacja',  1,  0.000, 'PostgreSQL 16 — baseline'),
('pg16',   'bitmap_heap_scan',   1,  0.000, 'PostgreSQL 16 — baseline'),
('pg16',   'vacuum_5m',          1,  0.000, 'PostgreSQL 16 — baseline'),

-- === URUCHOMIENIE 2: PG18 io_method=worker ===
('worker', 'seqscan_agregacja',  1,  0.000, 'PostgreSQL 18 — async worker'),
('worker', 'bitmap_heap_scan',   1,  0.000, 'PostgreSQL 18 — async worker'),
('worker', 'vacuum_5m',          1,  0.000, 'PostgreSQL 18 — async worker');

-- Weryfikacja
SELECT
    io_method,
    test_name           AS test,
    run_no              AS przebieg,
    czas_ms             AS czas_ms,
    uwagi
FROM benchmark.pomiary
ORDER BY test_name, io_method, run_no;
