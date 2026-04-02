-- ==============================================================================
-- Tytul:        04_compare_results.sql
-- Opis:         Porownanie wynikow benchmarku: PG16 vs PG18 Async I/O.
--               Oblicza przyspieszenie procentowe i bezwzgledne dla kazdego testu.
--               Wyniki nadaja sie bezposrednio do publikacji na LinkedIn.
-- Description [EN]: Benchmark results comparison: PG16 vs PG18 Async I/O.
--               Calculates percentage and absolute speedup for each test.
--               Results are ready to share directly on LinkedIn.
--
-- Autor:        KCB Kris
-- Data:         2026-04-01
-- Wersja:       1.0
--
-- Uzycie [PL]:       psql -U postgres -f 04_compare_results.sql
-- Usage [EN]:        psql -U postgres -f 04_compare_results.sql
-- ==============================================================================

\pset format aligned
\pset border 2
\pset linestyle unicode
\pset null '—'

\echo ''
\echo '============================================================================'
\echo '  WYNIKI BENCHMARKU: PostgreSQL 16 vs PostgreSQL 18 Async I/O'
\echo '  Srodowisko: Oracle Linux 8.8, kernel 5.4, VirtualBox'
\echo '============================================================================'
\echo ''

-- ============================================================================
-- SEKCJA 1: Surowe wyniki / Raw results
-- ============================================================================

\echo '--- Surowe wyniki pomiarow / Raw measurements ---'

SELECT
    test_name                               AS test,
    io_method                               AS konfiguracja,
    ROUND(AVG(czas_ms), 1)                  AS sredni_czas_ms,
    COUNT(*)                                AS liczba_przebiegow
FROM benchmark.pomiary
WHERE czas_ms > 0
GROUP BY test_name, io_method
ORDER BY test_name, io_method;

-- ============================================================================
-- SEKCJA 2: Porownanie PG16 vs PG18 / PG16 vs PG18 comparison
-- ============================================================================

\echo ''
\echo '--- Porownanie PG16 vs PG18 / Speedup comparison ---'

WITH
srednie AS (
    SELECT
        test_name,
        io_method,
        ROUND(AVG(czas_ms), 1) AS sredni_czas_ms
    FROM benchmark.pomiary
    WHERE czas_ms > 0
    GROUP BY test_name, io_method
),
baseline AS (
    SELECT test_name, sredni_czas_ms AS czas_pg16
    FROM srednie
    WHERE io_method = 'pg16'
),
test_run AS (
    SELECT test_name, io_method, sredni_czas_ms AS czas_pg18
    FROM srednie
    WHERE io_method != 'pg16'
)
SELECT
    t.test_name                                             AS test,
    t.io_method                                             AS pg18_tryb,
    b.czas_pg16                                             AS pg16_ms,
    t.czas_pg18                                             AS pg18_ms,
    ROUND(b.czas_pg16 - t.czas_pg18, 1)                    AS roznica_ms,
    ROUND((b.czas_pg16 - t.czas_pg18) / b.czas_pg16 * 100, 1) AS przyspieszenie_procent,
    ROUND(b.czas_pg16 / NULLIF(t.czas_pg18, 0), 2)         AS mnoznik_x
FROM test_run t
JOIN baseline b USING (test_name)
ORDER BY przyspieszenie_procent DESC;

-- ============================================================================
-- SEKCJA 3: Podsumowanie dla LinkedIn / LinkedIn summary
-- ============================================================================

\echo ''
\echo '============================================================================'
\echo '  PODSUMOWANIE DLA LINKEDIN / LINKEDIN SUMMARY'
\echo '============================================================================'

WITH
srednie AS (
    SELECT
        test_name,
        io_method,
        ROUND(AVG(czas_ms), 1) AS sredni_czas_ms
    FROM benchmark.pomiary
    WHERE czas_ms > 0
    GROUP BY test_name, io_method
),
baseline AS (
    SELECT test_name, sredni_czas_ms AS czas_pg16
    FROM srednie WHERE io_method = 'pg16'
),
test_run AS (
    SELECT test_name, sredni_czas_ms AS czas_pg18
    FROM srednie WHERE io_method != 'pg16'
)
SELECT
    CASE t.test_name
        WHEN 'seqscan_agregacja' THEN '📊 Sequential Scan (5M rows)'
        WHEN 'bitmap_heap_scan'  THEN '🔍 Bitmap Heap Scan (date range)'
        WHEN 'vacuum_5m'         THEN '🧹 VACUUM (500K dead tuples)'
    END                                                     AS operacja,
    b.czas_pg16 || ' ms'                                    AS "PG16 [ms]",
    t.czas_pg18 || ' ms'                                    AS "PG18 [ms]",
    '+' || ROUND((b.czas_pg16 - t.czas_pg18) / b.czas_pg16 * 100, 0) || '%' AS przyspieszenie
FROM test_run t
JOIN baseline b USING (test_name)
ORDER BY (b.czas_pg16 - t.czas_pg18) / b.czas_pg16 DESC;

\echo ''
\echo '  Srodowisko / Environment:'
\echo '  - Oracle Linux 8.8, kernel 5.4'
\echo '  - VirtualBox'
\echo '  - PG16 (sync I/O) vs PG18 (Async I/O — worker mode)'
\echo '  - Tabela: 5M wierszy, ~500 MB'
\echo '============================================================================'
\echo ''
