#!/bin/bash
# ==============================================================================
# Tytul:        run_benchmark.sh
# Opis:         Automatyczne wykonanie benchmarku Async I/O na dwoch instancjach
#               PostgreSQL (port 5416 = PG16 baseline, port 5432 = PG18 test).
#               Uruchamia 3 przebiegi Sequential Scan, 3 przebiegi Bitmap Heap Scan
#               i 1 przebieg VACUUM na kazdej instancji. Wyniki zapisuje do plikow JSON.
# Description [EN]: Automated I/O benchmark execution on two PostgreSQL instances
#               (port 5416 = PG16 baseline, port 5432 = PG18 test).
#               Runs 3 iterations of Sequential Scan, 3 of Bitmap Heap Scan,
#               and 1 VACUUM run per instance. Results saved to JSON files.
#
# Autor:        KCB Kris
# Data:         2026-04-01
# Wersja:       1.0
#
# Wymagania [PL]:    - PostgreSQL 16 na porcie 5416
#                    - PostgreSQL 18 na porcie 5432
#                    - Schemat benchmark musi istniec (uruchom sql/01_setup_test_data.sql)
#                    - psql w PATH
# Requirements [EN]: - PostgreSQL 16 on port 5416
#                    - PostgreSQL 18 on port 5432
#                    - benchmark schema must exist (run sql/01_setup_test_data.sql)
#                    - psql in PATH
#
# Uzycie [PL]:       bash agent/run_benchmark.sh
# Usage [EN]:        bash agent/run_benchmark.sh
# ==============================================================================

function run_query {
  local port=$1
  local q=$2
  psql -p $port -U postgres -t -c "$q"
}

for port in 5416 5432; do
  for run in 1 2 3; do
    echo "Port $port Run $run: Seq Scan"
    run_query $port "DISCARD ALL;"
    run_query $port "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT kategoria, COUNT(*), AVG(wartosc), SUM(wartosc) FROM benchmark.fakty GROUP BY kategoria ORDER BY COUNT(*) DESC;" > output_seq_${port}_${run}.json
  done
  
  for run in 1 2 3; do
    echo "Port $port Run $run: Bitmap Scan"
    run_query $port "DISCARD ALL;"
    run_query $port "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT COUNT(*), AVG(wartosc), MIN(data_zdarz), MAX(data_zdarz) FROM benchmark.fakty WHERE data_zdarz BETWEEN '2021-01-01' AND '2021-12-31';" > output_bit_${port}_${run}.json
  done
  
  echo "Port $port: Vacuum"
  run_query $port "UPDATE benchmark.fakty SET wartosc = wartosc * 1.01 WHERE id % 10 = 0;"
  psql -p $port -U postgres -c "VACUUM (ANALYZE, VERBOSE) benchmark.fakty;" > output_vac_${port}.txt 2>&1
done
