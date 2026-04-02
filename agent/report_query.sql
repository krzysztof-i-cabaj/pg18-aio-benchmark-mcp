WITH srednie AS (
    SELECT test_name, io_method, ROUND(AVG(czas_ms), 1) AS avg_ms
    FROM benchmark.pomiary WHERE czas_ms > 0
    GROUP BY test_name, io_method
),
baseline AS (SELECT test_name, avg_ms AS ms_pg16 FROM srednie WHERE io_method = 'sync'),
test_run AS (SELECT test_name, avg_ms AS ms_pg18 FROM srednie WHERE io_method = 'worker')
SELECT
    t.test_name,
    b.ms_pg16,
    t.ms_pg18,
    ROUND((b.ms_pg16 - t.ms_pg18) / b.ms_pg16 * 100, 1) AS speedup_pct,
    ROUND(b.ms_pg16 / t.ms_pg18, 2) AS speedup_x
FROM test_run t JOIN baseline b USING (test_name)
ORDER BY speedup_pct DESC;
