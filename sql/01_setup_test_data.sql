-- ==============================================================================
-- Tytul:        01_setup_test_data.sql
-- Opis:         Przygotowanie danych testowych do benchmarku Async I/O PG18.
--               Tworzy schemat benchmark, tabelę faktów (5M wierszy) oraz
--               tabelę do zapisywania wyników pomiarów.
-- Description [EN]: Creates benchmark schema, a large fact table (5M rows),
--               and a results table to store timing measurements.
--
-- Autor:        KCB Kris
-- Data:         2026-04-01
-- Wersja:       1.0
--
-- Wymagania [PL]:    - PostgreSQL 18.0
--                    - Uprawnienia: SUPERUSER lub CREATEDB
--                    - Wolne miejsce na dysku: ~600 MB
-- Requirements [EN]: - PostgreSQL 18.0
--                    - Privileges: SUPERUSER or CREATEDB
--                    - Free disk space: ~600 MB
--
-- Uzycie [PL]:       psql -U postgres -f 01_setup_test_data.sql
-- Usage [EN]:        psql -U postgres -f 01_setup_test_data.sql
--
-- UWAGA: Skrypt DROP-uje istniejący schemat benchmark (jesli istnieje).
-- NOTE:  Script DROPs existing benchmark schema (if exists).
-- ==============================================================================

\echo ''
\echo '============================================================================'
\echo '  SETUP: Przygotowanie danych testowych / Test data setup'
\echo '  PostgreSQL 18 — Async I/O Benchmark'
\echo '============================================================================'
\echo ''

-- ============================================================================
-- SEKCJA 1: Schemat i czyszczenie / Schema and cleanup
-- ============================================================================

\echo '[1/4] Tworzenie schematu benchmark...'

DROP SCHEMA IF EXISTS benchmark CASCADE;
CREATE SCHEMA benchmark;

-- ============================================================================
-- SEKCJA 2: Tabela wynikow pomiarow / Benchmark results table
-- ============================================================================

\echo '[2/4] Tworzenie tabeli wynikow...'

CREATE TABLE benchmark.pomiary (
    id              SERIAL PRIMARY KEY,
    io_method       TEXT        NOT NULL,           -- 'sync' lub 'worker'
    test_name       TEXT        NOT NULL,           -- nazwa testu
    run_no          INT         NOT NULL DEFAULT 1, -- numer przebiegu (1-3)
    czas_ms         NUMERIC(12,3),                  -- czas wykonania [ms]
    wiersze         BIGINT,                         -- liczba zwroconych wierszy
    shared_hit      BIGINT,                         -- bufory z cache
    shared_read     BIGINT,                         -- bufory z dysku
    uwagi           TEXT,                           -- dodatkowe uwagi
    ts              TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE benchmark.pomiary IS
    'Wyniki pomiarow benchmarku Async I/O: sync vs worker (PG18)';

-- ============================================================================
-- SEKCJA 3: Tabela faktow do testow seqscan / Fact table for seqscan tests
-- ============================================================================

\echo '[3/4] Generowanie tabeli faktow (5M wierszy) — to moze chwile zajac...'

CREATE TABLE benchmark.fakty (
    id          BIGSERIAL   PRIMARY KEY,
    kategoria   INT         NOT NULL,           -- 1-100, niska selektywnosc
    wartosc     NUMERIC(15,4),
    opis        TEXT,
    data_zdarz  DATE        NOT NULL,
    flaga       BOOLEAN     NOT NULL DEFAULT false
);

-- Wypelnienie 5 milionami wierszy
-- Generating 5 million rows
INSERT INTO benchmark.fakty (kategoria, wartosc, opis, data_zdarz, flaga)
SELECT
    (random() * 99 + 1)::INT,
    (random() * 1000000)::NUMERIC(15,4),
    repeat('lorem ipsum dolor sit amet consectetur ', (random()*3+1)::INT),
    '2020-01-01'::DATE + (random() * 1825)::INT,
    random() > 0.95
FROM generate_series(1, 5000000);

-- Indeks do testow bitmap heap scan
-- Index for bitmap heap scan tests
CREATE INDEX idx_fakty_kategoria ON benchmark.fakty (kategoria);
CREATE INDEX idx_fakty_data      ON benchmark.fakty (data_zdarz);

-- Zbierz statystyki
ANALYZE benchmark.fakty;

-- ============================================================================
-- SEKCJA 4: Weryfikacja / Verification
-- ============================================================================

\echo '[4/4] Weryfikacja...'

SELECT
    'benchmark.fakty'                   AS tabela,
    COUNT(*)                            AS liczba_wierszy,
    pg_size_pretty(pg_total_relation_size('benchmark.fakty')) AS rozmiar
FROM benchmark.fakty

UNION ALL

SELECT
    'benchmark.pomiary',
    COUNT(*),
    pg_size_pretty(pg_total_relation_size('benchmark.pomiary'))
FROM benchmark.pomiary;

\echo ''
\echo '============================================================================'
\echo '  GOTOWE. Nastepny krok:'
\echo ''
\echo '  1. Ustaw io_method = sync w postgresql.conf'
\echo '  2. Zrestartuj PostgreSQL: sudo systemctl restart postgresql-18'
\echo '  3. Uruchom: psql -U postgres -f 02_benchmark_run.sql'
\echo '============================================================================'
\echo ''
