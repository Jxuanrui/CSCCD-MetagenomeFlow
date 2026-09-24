# antiSMASH 8.0.4 metagenome-scale pathology: diagnosis and the chunked-execution workaround

## Timeline (2026-09-19/20, Project01 v8 re-run)

1. **Symptom**: script 28 antismash processes ran 3.8h wall with only ~2.5min CPU; output dirs empty; hmmsearch children lived for seconds then vanished.
2. **Elimination**: standalone hmmsearch passed => toolchain fine. `conda run` vs PATH-direct invocation identical => wrapper innocent. `prodigal` vs `prodigal-m` identical => genefinding innocent. `--genefinding-gff3` pre-computed genes: no improvement.
3. **Root cause**: sampling live worker tmpdirs showed each hmmsearch spawn carried only **2-17 records** — antismash 8.0.4 micro-batches hmm_detection, reloading the full HMM db per spawn (~1.5s fixed cost), ~0.6-1 record/s on a 48k-record assembly.
4. **Dead end avoided**: pre-filtering >=5kb would lose 40% of v7 regions (measured on intact Sample10 output: 155/262 region-contigs were >=5kb).
5. **Fix**: chunked execution — filter >=1000bp (antismash's own hard minimum, output-equivalent), split 24 ways, 12 concurrent x 4 cpus, merge region .gbk + records JSON. 25 min/sample; 240/240 chunks zero failures across 10 samples (37k-105k records each).

## Result

v8 = 3,364 regions vs v7 2,378 (+41.5%, strict superset incl. terpene-precursor); 28b novelty scoring passed 10/10. Full numbers: agents/provenance/20260919_28_antismash8_rerun_all.json.

## Lessons

- A "0% CPU parent with transient children" pattern means the parent delegates work that dies instantly — check the children's working directory and input sizes, not the parent's CPU.
- Orphaned batch cascades (secondary.sh) survive child kills: always kill the top ancestor.
- Benchmark your tool version on REAL input sizes: D1's 527kb-contig control validated correctness but could never expose a per-record spawning pathology.
- Chunking + concurrency is the general escape hatch for per-record process-spawning pathologies — but preserve the tool's own input contract (>=1000bp) so outputs stay equivalent.
