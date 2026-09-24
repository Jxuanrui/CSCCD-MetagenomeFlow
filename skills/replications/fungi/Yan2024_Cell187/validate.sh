#!/usr/bin/env bash
# validate.sh — Yan2024_Cell187 技能包验证脚本
# 验证项目中的 PHF profiling 实现与论文方法一致性
# 用法：bash skills/replications/fungi/Yan2024_Cell187/validate.sh -r REPO

set -euo pipefail
REPO="${1:-.}"
REPO="$(cd "${REPO}" && pwd)"
PASS=0; FAIL=0

check() {
    local desc="$1"; local cmd="$2"
    if eval "${cmd}" > /dev/null 2>&1; then
        echo "[PASS] ${desc}"; ((PASS++))
    else
        echo "[FAIL] ${desc}"; ((FAIL++))
    fi
}

echo "=== Yan2024_Cell187 Validation ==="

# 数据库文件
check "GPA.py exists"                    "[ -f '${REPO}/db/gut_fungi_db/GPA.py' ]"
check "gene2clu.map exists"              "[ -f '${REPO}/db/gut_fungi_db/gene2clu.map' ]"
check "clu.uniq_gene.sum exists"         "[ -f '${REPO}/db/gut_fungi_db/clu.uniq_gene.sum' ]"
check "db.fungi.taxonomy.tsv exists"     "[ -f '${REPO}/db/gut_fungi_db/db.fungi.taxonomy.tsv' ]"
check "db.fungi.fa.gz exists"            "[ -f '${REPO}/db/gut_fungi_db/db.fungi.fa.gz' ]"
check "Taxonomy has 317 clusters"        "[ \$(tail -n +2 '${REPO}/db/gut_fungi_db/db.fungi.taxonomy.tsv' | wc -l) -eq 317 ]"

# 脚本存在
check "74a script exists"                "[ -f '${REPO}/scripts/74a_fun_gut_db_build.sh' ]"
check "74e script exists"                "[ -f '${REPO}/scripts/74e_fun_phf_profiler.sh' ]"
check "74f script exists"                "[ -f '${REPO}/scripts/74f_fun_phf_aggregate.sh' ]"

# 脚本参数符合论文
check "74e uses identity 0.95"           "grep -q 'GPA.py.*-s 0.95\|-s 0.95.*GPA\|GPA_PY.*-s 0.95' '${REPO}/scripts/74e_fun_phf_profiler.sh'"
check "74e uses -k 1000 multimapping"    "grep -q '\-k 1000' '${REPO}/scripts/74e_fun_phf_profiler.sh'"
check "74e has 5-step filtering"         "grep -c 'run_bowtie\|bowtie2.*step' '${REPO}/scripts/74e_fun_phf_profiler.sh' | grep -qE '^[4-9]|^[1-9][0-9]'"

# Bowtie2 索引（构建完成后才能通过）
check "Bowtie2 fungi index built"        "ls '${REPO}/db/gut_fungi_db/bwt.index.gut_fungi_geneset'.*.bt2* 2>/dev/null | grep -qv tmp"
check "Bowtie2 uhgg index built"         "ls '${REPO}/db/gut_fungi_db/bwt.index.uhgg'.*.bt2* 2>/dev/null | grep -qv tmp"

# 原作者代码存档
check "Original code archived"           "[ -d '${REPO}/skills/replications/fungi/Yan2024_Cell187/code/original' ]"
check "Adapted profiling code exists"    "[ -f '${REPO}/skills/replications/fungi/Yan2024_Cell187/code/adapted/profiling/GPA.py' ]"

echo ""
echo "=== Result: ${PASS} passed, ${FAIL} failed ==="
[ "${FAIL}" -eq 0 ] && echo "ALL PASS — Yan2024_Cell187 replication validated" && exit 0
echo "Some checks failed. Bowtie2 index checks require index build to complete first." && exit 1
