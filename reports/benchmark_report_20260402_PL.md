# PostgreSQL 16 vs 18 — Async I/O Benchmark
**Data:** 2026-04-02
**Środowisko:** Oracle Linux 8.8, kernel 5.4, VirtualBox, Dane: pgbench scale 100 (~1.5GB)
**PG16:** PostgreSQL 16.13 | port 5416 | I/O: sync
**PG18:** PostgreSQL 18.0 | port 5432 | I/O: worker (Async)

## Wyniki

| Test | PG16 (ms) | PG18 (ms) | Przyspieszenie | Mnożnik |
|------|-----------|-----------|----------------|---------|
| Bitmap Heap Scan | 1184.7 | 517.6 | +56.3% | 2.29x |
| Sequential Scan | 2457.8 | 1823.2 | +25.8% | 1.35x |
| VACUUM (500K) | 22140.0 | 22270.0 | -0.6% | 0.99x |

## Konfiguracja środowiska
Obie instancje były skonfigurowane tak samo, aby zapewnić miarodajność testów:
- `shared_buffers` = 256MB
- `work_mem` = 4MB
- `io_method` na PG18 zostało ustawione na natywny `worker`.

## Wnioski
Zastosowanie modelu asynchronicznego I/O wdrożonego w PostgreSQL 18 przyniosło rewelacyjne osiągnięcia, zwłaszcza jeśli chodzi o operację przeliczania krotek na wolumenach:
1. **Bitmap Heap Scan** zaliczył największy wzrost osiągów. Użycie puli workerów (`io_method=worker`) udowodniło redukcję czasu trwania o 56.3% (jest 2.29x szybsze w stosunku do PG 16).
2. **Sequential Scan** stał się szybszy o blisko 26% — potwierdza to obietnice twórców odnośnie prefetchingu asynchronicznego (szczególnie istotnego na nośnikach HDD i w chmurze bez io_uring).
3. **VACUUM** działa niemal identycznie (spadek wydajności ułamek procenta - granica błędu statystycznego). Biorąc pod uwagę operacje porządkowe na 500 tysiącach martwych krotek, architektura I/O pod względem vacuum nie ucierpiała przy implementacji AIO.

---
*Raport wygenerowany automatycznie.*
