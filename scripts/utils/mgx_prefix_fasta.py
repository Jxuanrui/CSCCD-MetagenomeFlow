#!/usr/bin/env python3
"""mgx_prefix_fasta.py — T-20: build a project-unique canonical fungal gene FASTA.

Usage: mgx_prefix_fasta.py <prodigal_dir> <out_faa> <out_map_tsv>

Reads every per-sample *.faa under <prodigal_dir> (sample = directory name),
prefixes each header with "SAMPLE__" and writes:
  <out_faa>     canonical combined FASTA (SAMPLE__raw_gene_id), sequences verbatim
  <out_map_tsv> canonical_gene_id | raw_gene_id | sample_id | source_file | sequence_hash

The map table is the single source of identity; downstream consumers must join
through it (or use the canonical key as-is) instead of re-deriving the sample
by splitting on "__". sequence_hash = md5 of the whitespace-stripped amino-acid
string, so "same raw id, different sequence" is detectable.
"""
import glob
import hashlib
import os
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    src_dir, out_faa, out_map = sys.argv[1:4]
    if not os.path.isdir(src_dir):
        print(f"[ERROR] prodigal dir missing: {src_dir}", file=sys.stderr)
        return 1
    faa_files = sorted(glob.glob(os.path.join(src_dir, "*", "*.faa")))
    if not faa_files:
        print(f"[ERROR] no per-sample .faa under {src_dir}", file=sys.stderr)
        return 1

    n = 0
    with open(out_faa, "w") as fa, open(out_map, "w") as fm:
        fm.write("canonical_gene_id\traw_gene_id\tsample_id\tsource_file\tsequence_hash\n")
        for faa in faa_files:
            sample = os.path.basename(os.path.dirname(faa))
            with open(faa) as fh:
                raw_id, seq_chunks = None, []
                def flush():
                    nonlocal raw_id, seq_chunks, n
                    if raw_id is None:
                        return
                    seq = "".join(seq_chunks)
                    digest = hashlib.md5(seq.encode()).hexdigest()
                    fa.write(f">{sample}__{raw_id}\n{seq}\n")
                    fm.write(f"{sample}__{raw_id}\t{raw_id}\t{sample}\t{faa}\t{digest}\n")
                    n += 1
                    raw_id, seq_chunks = None, []
                for line in fh:
                    line = line.strip()
                    if line.startswith(">"):
                        flush()
                        raw_id = line[1:].split()[0] if line[1:].split() else ""
                    elif line:
                        seq_chunks.append("".join(line.split()))
                flush()

    print(f"[mgx_prefix_fasta] sequences: {n} | map: {out_map}")
    return 0 if n else 1


if __name__ == "__main__":
    sys.exit(main())
