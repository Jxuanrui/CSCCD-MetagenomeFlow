# Adaptation Log

Scope: path fixes only in `adapted/`. The upstream clone in `original/` was left unchanged.

## Modified files

- `adapted/profiling/GPA.py`
  - Replaced the original absolute Miniconda Python shebang with `#!/usr/bin/env python3`.
- `adapted/profiling/combine_file_zy_folder_allsample.py`
  - Replaced the original absolute Miniconda Python shebang with `#!/usr/bin/env python3`.
- `adapted/profiling/flow_fungi.map.sh`
  - Replaced the upstream default fungi index path under `/share/data1/...` with a `${PROJ_DIR}`-based default overrideable by `DB_INDEX`.
  - Replaced the upstream human, UHGG, and fungal rRNA reference paths under `/share/data1/...` with `${PROJ_DIR}`-based defaults overrideable by `DB_HUMAN`, `DB_UHGG`, and `DB_RRNA`.
  - Replaced local default `gene2len` and `gene2clu` file references with `${PROJ_DIR}`-based defaults overrideable by `GENE2LEN` and `GENE2CLU`.
  - Updated the file existence check so it validates the substituted `gene2len` and `gene2clu` paths.

## Files not adapted

- None identified within the copied `profiling/`, `downstream/`, and `annotation/` scope.

## Notes

- External reference indexes and database files expected by `profiling/flow_fungi.map.sh` are not bundled in `adapted/profiling/`; provide them via the documented `${PROJ_DIR}` layout or the environment variables above.
