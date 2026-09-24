# Yan2024 Adapted Code Layout

This directory reorganizes selected materials from the upstream `Cultivated-Gut-Fungi` repository without changing the original clone in `../original/`.

- `profiling/`: core profiling scripts copied from `original/Fungi_profile_algo/bin/`. Absolute server paths were replaced with `${PROJ_DIR}`-based defaults and environment variable overrides where needed.
- `downstream/`: gut fungi profile tables copied from `original/Gut_fungi_profile/`.
- `annotation/`: genome annotation result directories copied from `original/Genome_annotation/`, including `SMGCs`, `cazy`, `eggNOG`, `gtf`, `kegg`, and `pfam`.

For `profiling/flow_fungi.map.sh`, you can override default resource locations with:

- `PROJ_DIR`
- `DB_INDEX`
- `DB_HUMAN`
- `DB_UHGG`
- `DB_RRNA`
- `GENE2LEN`
- `GENE2CLU`
