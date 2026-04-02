# PostgreSQL 16 vs 18 — Async I/O Benchmark Report
**Date:** 2026-04-02
**Environment:** Oracle Linux 8.8, kernel 5.4, VirtualBox, Data: pgbench scale 100 (~1.5GB)
**PG16:** PostgreSQL 16.13 | port 5416 | I/O: sync
**PG18:** PostgreSQL 18.0 | port 5432 | I/O: worker (Async)

## Results

| Test | PG16 (ms) | PG18 (ms) | Speedup | Multiplier |
|------|-----------|-----------|---------|------------|
| Bitmap Heap Scan | 1184.7 | 517.6 | +56.3% | 2.29x |
| Sequential Scan | 2457.8 | 1823.2 | +25.8% | 1.35x |
| VACUUM (500K) | 22140.0 | 22270.0 | -0.6% | 0.99x |

## Environment Configuration
Both instances were configured identically to ensure fair comparison:
- `shared_buffers` = 256MB
- `work_mem` = 4MB
- `io_method` on PG18 was set to native `worker` mode.

## Conclusions
The asynchronous I/O model introduced in PostgreSQL 18 delivered remarkable performance gains, particularly for tuple-processing operations on large volumes:
1. **Bitmap Heap Scan** achieved the greatest improvement. Using the worker pool (`io_method=worker`) demonstrated a 56.3% reduction in execution time (2.29x faster compared to PG16).
2. **Sequential Scan** became nearly 26% faster — confirming the developers' promises regarding asynchronous prefetching (especially significant on HDD storage and cloud environments without io_uring).
3. **VACUUM** performed nearly identically (a fraction of a percent slower — within statistical error margin). Given the cleanup operations on 500 thousand dead tuples, the I/O architecture with respect to VACUUM was not impacted by the AIO implementation.

---
*Report generated automatically.*
