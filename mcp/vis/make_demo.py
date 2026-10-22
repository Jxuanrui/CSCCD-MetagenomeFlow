#!/usr/bin/env python3
"""Fabricate a fully synthetic 24-sample demo project (Project/VisDemo).

All tables are generated from seeded pseudo-random numbers (stdlib `random`,
no real sequencing data, no real project data).  The output layout matches the
input contracts of the existing pipeline plotting scripts:

  result/metaphlan4/merged/taxonomy.tsv          91/92/93/94/96_stat_ml, 99a/99b
  result/virus/votu/table/vOTU_table_ann.txt     91 (gene-level TPM -> vOTU)
  result/virus/votu/vclust/clusters.tsv          91 (gene -> vOTU mapping)
  result/virus/votu/genomad/virus_taxonomy.tsv   91/92 (virus taxonomy)
  result/virus/votu/votu_table.tsv               93/96 (vOTU x sample counts)
  result/fungi/metaphlan4/{S}/{S}_profile.txt    91/93/96 (per-sample fungi)
  result/humann3/{S}/{S}_path{abundance,coverage}.tsv   96b
  result/integration/bacteria/{kegg_ko,cog}_abundance.tsv  96 network
  result/stat/metadata.tsv + metadata.csv        all -m consumers
  result/demo/krona_counts.tsv                   ktImportText
  temp/01_qc/*.json                              00_multiqc_report.sh

Usage: python3 make_demo.py [--out Project/VisDemo] [--seed 42]
"""

import argparse
import json
import math
import os
import random
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RSCRIPT = os.path.join(REPO, "envs", "r_stat", "bin", "Rscript")

SAMPLES = ["S%02d" % i for i in range(1, 25)]
GROUPS = {s: "control" if i < 12 else "treat" for i, s in enumerate(SAMPLES, 1)}

# ---------------------------------------------------------------- bacteria ----
# (phylum, class, order, family, genus, species)
SPECIES = [
    # Firmicutes / Clostridia / Eubacteriales
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Roseburia", "Roseburia intestinalis"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Roseburia", "Roseburia hominis"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Eubacterium", "Eubacterium rectale"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Anaerostipes", "Anaerostipes hadrus"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Blautia", "Blautia obeum"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Blautia", "Blautia wexlerae"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Dorea", "Dorea longicatena"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Coprococcus", "Coprococcus comes"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Lachnospira", "Lachnospira eligens"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Fusicatenibacter", "Fusicatenibacter saccharivorans"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Lachnospiraceae", "Agathobacter", "Agathobacter butyriciproducens"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Oscillospiraceae", "Faecalibacterium", "Faecalibacterium prausnitzii"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Oscillospiraceae", "Ruminococcus", "Ruminococcus bromii"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Oscillospiraceae", "Ruminococcus", "Ruminococcus gnavus"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Oscillospiraceae", "Subdoligranulum", "Subdoligranulum variabile"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Oscillospiraceae", "Flavonifractor", "Flavonifractor plautii"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Oscillospiraceae", "Pseudoflavonifractor", "Pseudoflavonifractor capillosus"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Oscillospiraceae", "Butyricicoccus", "Butyricicoccus pullicaecorum"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Oscillospiraceae", "Intestinimonas", "Intestinimonas butyriciproducens"),
    ("Firmicutes", "Clostridia", "Eubacteriales", "Oscillospiraceae", "Anaerobutyricum", "Anaerobutyricum hallii"),
    ("Firmicutes", "Clostridia", "Christensenellales", "Christensenellaceae", "Christensenella", "Christensenella minuta"),
    ("Firmicutes", "Clostridia", "Peptostreptococcales", "Peptostreptococcaceae", "Peptostreptococcus", "Peptostreptococcus anaerobius"),
    ("Firmicutes", "Clostridia", "Peptostreptococcales", "Peptostreptococcaceae", "Parvimonas", "Parvimonas micra"),
    ("Firmicutes", "Clostridia", "Clostridiales", "Clostridiaceae", "Clostridium", "Clostridium perfringens"),
    ("Firmicutes", "Clostridia", "Clostridiales", "Clostridiaceae", "Clostridium", "Clostridium bolteae"),
    # Firmicutes / Bacilli
    ("Firmicutes", "Bacilli", "Lactobacillales", "Lactobacillaceae", "Lactobacillus", "Lactobacillus gasseri"),
    ("Firmicutes", "Bacilli", "Lactobacillales", "Lactobacillaceae", "Limosilactobacillus", "Limosilactobacillus reuteri"),
    ("Firmicutes", "Bacilli", "Lactobacillales", "Lactobacillaceae", "Lacticaseibacillus", "Lacticaseibacillus rhamnosus"),
    ("Firmicutes", "Bacilli", "Lactobacillales", "Lactobacillaceae", "Lactiplantibacillus", "Lactiplantibacillus plantarum"),
    ("Firmicutes", "Bacilli", "Lactobacillales", "Streptococcaceae", "Streptococcus", "Streptococcus salivarius"),
    ("Firmicutes", "Bacilli", "Lactobacillales", "Streptococcaceae", "Streptococcus", "Streptococcus parasanguinis"),
    ("Firmicutes", "Bacilli", "Lactobacillales", "Enterococcaceae", "Enterococcus", "Enterococcus faecalis"),
    ("Firmicutes", "Bacilli", "Lactobacillales", "Enterococcaceae", "Enterococcus", "Enterococcus faecium"),
    ("Firmicutes", "Bacilli", "Erysipelotrichales", "Erysipelotrichaceae", "Holdemania", "Holdemania filiformis"),
    ("Firmicutes", "Bacilli", "Erysipelotrichales", "Erysipelotrichaceae", "Turicibacter", "Turicibacter sanguinis"),
    # Firmicutes / Negativicutes
    ("Firmicutes", "Negativicutes", "Veillonellales", "Veillonellaceae", "Dialister", "Dialister invisus"),
    ("Firmicutes", "Negativicutes", "Veillonellales", "Veillonellaceae", "Megasphaera", "Megasphaera elsdenii"),
    ("Firmicutes", "Negativicutes", "Veillonellales", "Veillonellaceae", "Veillonella", "Veillonella parvula"),
    ("Firmicutes", "Negativicutes", "Veillonellales", "Veillonellaceae", "Phascolarctobacterium", "Phascolarctobacterium succinatutens"),
    # Bacteroidota
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Bacteroidaceae", "Bacteroides", "Bacteroides vulgatus"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Bacteroidaceae", "Bacteroides", "Bacteroides thetaiotaomicron"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Bacteroidaceae", "Bacteroides", "Bacteroides uniformis"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Bacteroidaceae", "Bacteroides", "Bacteroides ovatus"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Bacteroidaceae", "Bacteroides", "Bacteroides fragilis"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Bacteroidaceae", "Bacteroides", "Bacteroides dorei"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Bacteroidaceae", "Bacteroides", "Bacteroides cellulosilyticus"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Bacteroidaceae", "Bacteroides", "Bacteroides massiliensis"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Bacteroidaceae", "Bacteroides", "Bacteroides stercoris"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Prevotellaceae", "Prevotella", "Prevotella copri"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Prevotellaceae", "Prevotella", "Prevotella timonensis"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Tannerellaceae", "Parabacteroides", "Parabacteroides distasonis"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Tannerellaceae", "Parabacteroides", "Parabacteroides merdae"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Rikenellaceae", "Alistipes", "Alistipes finegoldii"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Rikenellaceae", "Alistipes", "Alistipes putredinis"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Rikenellaceae", "Alistipes", "Alistipes shahii"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Barnesiellaceae", "Barnesiella", "Barnesiella intestinihominis"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Odoribacteraceae", "Odoribacter", "Odoribacter splanchnicus"),
    ("Bacteroidota", "Bacteroidia", "Bacteroidales", "Muribaculaceae", "Muribaculum", "Muribaculum intestinale"),
    # Actinobacteriota
    ("Actinobacteriota", "Actinomycetia", "Bifidobacteriales", "Bifidobacteriaceae", "Bifidobacterium", "Bifidobacterium longum"),
    ("Actinobacteriota", "Actinomycetia", "Bifidobacteriales", "Bifidobacteriaceae", "Bifidobacterium", "Bifidobacterium adolescentis"),
    ("Actinobacteriota", "Actinomycetia", "Bifidobacteriales", "Bifidobacteriaceae", "Bifidobacterium", "Bifidobacterium bifidum"),
    ("Actinobacteriota", "Actinomycetia", "Bifidobacteriales", "Bifidobacteriaceae", "Bifidobacterium", "Bifidobacterium breve"),
    ("Actinobacteriota", "Actinomycetia", "Bifidobacteriales", "Bifidobacteriaceae", "Bifidobacterium", "Bifidobacterium catenulatum"),
    ("Actinobacteriota", "Actinomycetia", "Bifidobacteriales", "Bifidobacteriaceae", "Bifidobacterium", "Bifidobacterium pseudolongum"),
    ("Actinobacteriota", "Coriobacteriia", "Coriobacteriales", "Eggerthellaceae", "Eggerthella", "Eggerthella lenta"),
    ("Actinobacteriota", "Coriobacteriia", "Coriobacteriales", "Eggerthellaceae", "Slackia", "Slackia isoflavoniconvertens"),
    ("Actinobacteriota", "Coriobacteriia", "Coriobacteriales", "Eggerthellaceae", "Olsenella", "Olsenella uli"),
    ("Actinobacteriota", "Coriobacteriia", "Coriobacteriales", "Eggerthellaceae", "Gordonibacter", "Gordonibacter pamelaeae"),
    # Proteobacteria
    ("Proteobacteria", "Gammaproteobacteria", "Enterobacterales", "Enterobacteriaceae", "Escherichia", "Escherichia coli"),
    ("Proteobacteria", "Gammaproteobacteria", "Enterobacterales", "Enterobacteriaceae", "Klebsiella", "Klebsiella pneumoniae"),
    ("Proteobacteria", "Gammaproteobacteria", "Enterobacterales", "Enterobacteriaceae", "Enterobacter", "Enterobacter cloacae"),
    ("Proteobacteria", "Gammaproteobacteria", "Enterobacterales", "Enterobacteriaceae", "Salmonella", "Salmonella enterica"),
    ("Proteobacteria", "Betaproteobacteria", "Burkholderiales", "Sutterellaceae", "Sutterella", "Sutterella wadsworthensis"),
    ("Proteobacteria", "Betaproteobacteria", "Burkholderiales", "Sutterellaceae", "Parasutterella", "Parasutterella excrementihominis"),
    ("Proteobacteria", "Deltaproteobacteria", "Desulfovibrionales", "Desulfovibrionaceae", "Desulfovibrio", "Desulfovibrio piger"),
    ("Proteobacteria", "Gammaproteobacteria", "Pasteurellales", "Pasteurellaceae", "Haemophilus", "Haemophilus parainfluenzae"),
    # Verrucomicrobiota / Fusobacteriota / Cyanobacteria / Synergistota
    ("Verrucomicrobiota", "Verrucomicrobiae", "Verrucomicrobiales", "Akkermansiaceae", "Akkermansia", "Akkermansia muciniphila"),
    ("Fusobacteriota", "Fusobacteriia", "Fusobacteriales", "Fusobacteriaceae", "Fusobacterium", "Fusobacterium nucleatum"),
    ("Fusobacteriota", "Fusobacteriia", "Fusobacteriales", "Fusobacteriaceae", "Fusobacterium", "Fusobacterium varium"),
    ("Fusobacteriota", "Fusobacteriia", "Fusobacteriales", "Fusobacteriaceae", "Fusobacterium", "Fusobacterium gonidiaformans"),
    ("Cyanobacteria", "Melainabacteria", "Gastranaerophilales", "CAJFWI01", "CAJFWI01", "Cyanobacteria bacterium"),
    ("Synergistota", "Synergistia", "Synergistales", "Synergistaceae", "Synergistes", "Synergistes jonesii"),
]

# Realistic mean relative abundance (% of community) for the dominant members.
BASE_ABUNDANCE = {
    "Bacteroides vulgatus": 5.2, "Bacteroides thetaiotaomicron": 3.4,
    "Bacteroides uniformis": 2.1, "Bacteroides ovatus": 1.6,
    "Faecalibacterium prausnitzii": 3.1, "Eubacterium rectale": 2.2,
    "Roseburia intestinalis": 1.7, "Prevotella copri": 2.4,
    "Bifidobacterium longum": 1.4, "Bifidobacterium adolescentis": 0.9,
    "Akkermansia muciniphila": 0.8, "Ruminococcus bromii": 1.3,
    "Blautia obeum": 1.0, "Parabacteroides distasonis": 0.9,
    "Escherichia coli": 0.7, "Bacteroides fragilis": 0.6,
    "Ruminococcus gnavus": 0.8, "Anaerostipes hadrus": 0.7,
    "Lactobacillus gasseri": 0.4, "Dialister invisus": 0.5,
}
# Fold-change (treat / control); enriched taxa give the volcano a real signal.
TREAT_FOLD = {
    "Akkermansia muciniphila": 5.5, "Faecalibacterium prausnitzii": 4.0,
    "Roseburia intestinalis": 3.5, "Eubacterium rectale": 3.2,
    "Bifidobacterium longum": 6.0, "Bifidobacterium adolescentis": 4.5,
    "Blautia obeum": 3.0, "Anaerostipes hadrus": 3.8,
    "Parabacteroides distasonis": 3.1, "Lactobacillus gasseri": 7.5,
    "Bacteroides vulgatus": 0.35, "Prevotella copri": 0.25,
    "Dialister invisus": 0.4,
}

# ------------------------------------------------------------------- virus ----
# (order, family, genus) pools for geNomad-style Caudoviricetes lineages.
VIRUS_TAXA = [
    ("Crassvirales", "Crassviridae", "Certevirus"),
    ("Crassvirales", "Crassviridae", "Corrovirus"),
    ("Crassvirales", "Intestiviridae", "Kaposhuvirus"),
    ("Crassvirales", "Intestiviridae", "Loockvirus"),
    ("Chasevirales", "Chaseviridae", "Chasevirus"),
    ("Chasevirales", "Demerecviridae", "Deejvirus"),
    ("Kirjokansvirales", "Straboviridae", "Tequatrovirus"),
    ("Kirjokansvirales", "Straboviridae", "Tevenvirus"),
    ("Kirjokansvirales", "Schitoviridae", "Pootvirus"),
    ("Vinavirales", "Peduoviridae", "Hpunavirus"),
    ("Vinavirales", "Zinderviridae", "Zindervirus"),
    ("Caudovirales", "Ackermannviridae", "Agmunervirus"),
    ("Caudovirales", "Autographiviridae", "Peduovirus" ),
    ("Caudovirales", "Mesyanzhinovviridae", "Moorenavirus"),
    ("Caudovirales", "Casjensviridae", "Siltvirus"),
    ("Caudovirales", "Guelinviridae", "Septimatrevirus"),
]

# ------------------------------------------------------------------- fungi ----
# (phylum, class, order, family, genus, species, ncbi_tax_id)
FUNGI = [
    ("Ascomycota", "Saccharomycetes", "Saccharomycetales", "Saccharomycetaceae", "Saccharomyces", "Saccharomyces cerevisiae", 4932),
    ("Ascomycota", "Saccharomycetes", "Saccharomycetales", "Debaryomycetaceae", "Debaryomyces", "Debaryomyces hansenii", 4959),
    ("Ascomycota", "Saccharomycetes", "Saccharomycetales", "Debaryomycetaceae", "Candida", "Candida tropicalis", 5482),
    ("Ascomycota", "Saccharomycetes", "Saccharomycetales", "Pichiaceae", "Pichia", "Pichia kudriavzevii", 4909),
    ("Ascomycota", "Saccharomycetes", "Saccharomycetales", "Metschnikowiaceae", "Candida", "Candida albicans", 5476),
    ("Ascomycota", "Saccharomycetes", "Saccharomycetales", "Metschnikowiaceae", "Candida", "Candida glabrata", 5478),
    ("Ascomycota", "Saccharomycetes", "Saccharomycetales", "Metschnikowiaceae", "Candida", "Candida parapsilosis", 5480),
    ("Ascomycota", "Eurotiomycetes", "Eurotiales", "Aspergillaceae", "Aspergillus", "Aspergillus fumigatus", 746128),
    ("Ascomycota", "Eurotiomycetes", "Eurotiales", "Aspergillaceae", "Aspergillus", "Aspergillus niger", 5062),
    ("Ascomycota", "Eurotiomycetes", "Eurotiales", "Aspergillaceae", "Penicillium", "Penicillium roqueforti", 5078),
    ("Ascomycota", "Dothideomycetes", "Capnodiales", "Cladosporiaceae", "Cladosporium", "Cladosporium cladosporioides", 5080),
    ("Ascomycota", "Sordariomycetes", "Hypocreales", "Nectriaceae", "Fusarium", "Fusarium oxysporum", 5507),
    ("Basidiomycota", "Malasseziomycetes", "Malasseziales", "Malasseziaceae", "Malassezia", "Malassezia restricta", 428136),
    ("Basidiomycota", "Malasseziomycetes", "Malasseziales", "Malasseziaceae", "Malassezia", "Malassezia globosa", 428134),
    ("Basidiomycota", "Microbotryomycetes", "Sporidiobolales", "Sporidiobolaceae", "Rhodotorula", "Rhodotorula mucilaginosa", 5533),
    ("Basidiomycota", "Tremellomycetes", "Tremellales", "Tremellaceae", "Cryptococcus", "Cryptococcus neoformans", 5207),
    ("Mucoromycota", "Mucoromycetes", "Mucorales", "Mucoraceae", "Mucor", "Mucor circinelloides", 5470),
]
FUNGAL_TREAT_FOLD = {
    "Candida albicans": 4.0, "Saccharomyces cerevisiae": 3.0,
    "Pichia kudriavzevii": 3.5, "Malassezia restricta": 0.3,
}

# ---------------------------------------------------------------- humann3 -----
PATHWAYS = [
    "GLYCOCAT-PWY: superpathway of glycan degradation",
    "PWY-5340: superpathway of L-lysine, L-threonine and L-methionine biosynthesis I",
    "PWY-7219: superpathway of L-lysine, L-threonine and L-methionine biosynthesis II",
    "ARGSYN-PWY: L-ornithine biosynthesis II",
    "ARGSYNBS-PWY: L-ornithine biosynthesis I",
    "GLUCONEO-PWY: gluconeogenesis I",
    "GLYCOLYSIS: glycolysis I (from glucose 6-phosphate)",
    "GLYCOLYSIS-TCA-GLUCONEO-PWY: glycolysis, TCA cycle and gluconeogenesis",
    "PENTOSE-P-PWY: pentose phosphate pathway",
    "NONOXIPENT-PWY: pentose phosphate pathway (non-oxidative phase)",
    "TCA: TCA cycle I (prokaryotic)",
    "ANAEROFRUCAT-PWY: superpathway of glycolysis and fermentation",
    "FERMENTATION-PWY: superpathway of fermentation",
    "PWY-6572: superpathway of L-methionine biosynthesis I",
    "CYSTSYN-PWY: L-cysteine biosynthesis I",
    "HOMOSER-METSYN-PWY: L-methionine biosynthesis III",
    "TRPSYN-PWY: L-tryptophan biosynthesis I",
    "PWY-6163: superpathway of L-lysine biosynthesis",
    "DAPLYSINESYN-PWY: L-lysine biosynthesis III",
    "ILEUSYN-PWY: L-isoleucine biosynthesis I",
    "VALSYN-PWY: L-valine biosynthesis",
    "LEUSYN-PWY: L-leucine biosynthesis",
    "PHEPROSYN-PWY: superpathway of L-phenylalanine and L-tyrosine biosynthesis",
    "HISTSYN-PWY: L-histidine biosynthesis I",
    "SERSYN-PWY: L-serine biosynthesis I",
    "GLNSYN-PWY: glutamine biosynthesis I",
    "GLUTORN-PWY: ornithine biosynthesis II",
    "PROSYN-PWY: L-proline biosynthesis I",
    "ALANASYN-PWY: L-alanine biosynthesis I",
    "ASPARAGSYN-PWY: L-asparagine biosynthesis I",
    "ASPARTATESYN-PWY: L-aspartate biosynthesis",
    "GLUTSYN-PWY: glutamate biosynthesis I",
    "PWY-5652: superpathway of aromatic amino acid biosynthesis",
    "CHLORSYN-PWY: superpathway of chlorophyll biosynthesis",
    "COA-PWY: coenzyme A biosynthesis I",
    "FASYN-INITIAL-PWY: fatty acid biosynthesis initiation",
    "FASYN-ELONG-PWY: fatty acid elongation -- saturated",
    "BIOTIN-BIOSYNTHESIS-PWY: biotin biosynthesis I",
    "RIBOSYN2-PWY: riboflavin biosynthesis I",
    "FOLSYN-PWY: superpathway of tetrahydrofolate biosynthesis",
    "THIOSULFATE-RDP-PWY: thiosulfate oxidation II",
    "SULFATE-CYS-PWY: sulfate activation for cysteine biosynthesis",
    "PWY-7210: pyruvate fermentation to isobutanol",
    "PWY-6583: pyruvate fermentation to propanoate I",
    "PWY-7225: L-lysine fermentation to acetate and butanoate",
    "CENTFERM-PWY: pyruvate fermentation to (S)-lactate",
    "LACTOSESYN-PWY: lactose biosynthesis",
    "COLANSYN-PWY: colanic acid building blocks biosynthesis",
    "PWY-7332: superpathway of L-threonine metabolism",
    "GALLDEG-PWY: gallate degradation II",
    "PWY-5430: superpathway of UDP-glucose-derived O-antigen building blocks biosynthesis",
    "PWY-7388: superpathway of C10 isoprenoid biosynthesis",
    "MEVALONATE-PWY: mevalonate pathway I",
    "NONMEVALIPP-PWY: non-mevalonate pathway I",
    "PEPTIDOGLYCANSYN-PWY: peptidoglycan biosynthesis I",
    "PWY-6386: UDP-N-acetylmuramoyl-tripeptide biosynthesis II",
    "LPSBIOSYN-PWY: lipid A biosynthesis",
    "NAD-BIOSYNTHESIS-II: NAD biosynthesis II",
    "PWY-6892: superpathway of pyrimidine ribonucleosides biosynthesis",
    "DENOVOPURINE2-PWY: purine nucleotides de novo biosynthesis II",
]
PATHWAY_TREAT_FOLD = {
    "GLYCOCAT-PWY: superpathway of glycan degradation": 2.8,
    "FERMENTATION-PWY: superpathway of fermentation": 3.4,
    "PWY-7225: L-lysine fermentation to acetate and butanoate": 3.8,
    "PWY-6583: pyruvate fermentation to propanoate I": 2.5,
    "BIOTIN-BIOSYNTHESIS-PWY: biotin biosynthesis I": 2.2,
    "FOLSYN-PWY: superpathway of tetrahydrofolate biosynthesis": 3.1,
    "MEVALONATE-PWY: mevalonate pathway I": 2.0,
    "PWY-6386: UDP-N-acetylmuramoyl-tripeptide biosynthesis II": 2.4,
    "HOMOSER-METSYN-PWY: L-methionine biosynthesis III": 3.6,
    "TRPSYN-PWY: L-tryptophan biosynthesis I": 2.7,
}

KO_FEATURES = [
    "K00001", "K00003", "K00006", "K00009", "K00013", "K00016", "K00018",
    "K00022", "K00031", "K00037", "K00134", "K00150", "K00162", "K00169",
    "K00174", "K00239", "K00244", "K00249", "K00257", "K00266", "K00286",
    "K00290", "K00305", "K00317", "K00337", "K00370", "K00382", "K00399",
    "K00400", "K00401", "K00600", "K00625", "K00631", "K00672", "K00830",
    "K00900", "K00918", "K00925", "K01006", "K01070", "K01100", "K01188",
    "K01499", "K01509", "K01623", "K01785", "K01834", "K01915", "K01938",
    "K02000", "K02014", "K02123", "K02231", "K02304", "K02352", "K02582",
    "K02631", "K02704", "K02768", "K02808",
]
COG_FEATURES = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N",
    "O", "P", "Q", "R", "S", "T", "U", "V", "EG", "GT", "KRT", "MTR", "EHP",
]

# ------------------------------------------------------------------ helpers ---
def lognorm(rng, mu, sigma):
    return math.exp(rng.gauss(mu, sigma))


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)
    return path


def fmt_row(name, values, fmt="%.6f"):
    return "\t".join([name] + [fmt % v for v in values]) + "\n"


def lineage_of(sp):
    """Full 7-rank pipe lineage for a species tuple."""
    p, c, o, f, g, s = sp
    return "k__Bacteria|p__%s|c__%s|o__%s|f__%s|g__%s|s__%s" % (
        p.replace(" ", "_"), c.replace(" ", "_"), o.replace(" ", "_"),
        f.replace(" ", "_"), g, s.replace(" ", "_"))


# --------------------------------------------------------------- generators ---
def gen_bacteria(rng):
    """Species x sample relative abundance matrix (columns sum to ~100)."""
    base = {}
    for sp in SPECIES:
        name = sp[5]
        if name in BASE_ABUNDANCE:
            base[name] = BASE_ABUNDANCE[name] * lognorm(rng, 0, 0.08)
        else:
            base[name] = lognorm(rng, math.log(0.12), 1.0)
    matrix = {}
    for s in SAMPLES:
        treat = GROUPS[s] == "treat"
        # Orthogonal diversity signals (independent of TREAT_FOLD):
        # evenness — power-flatten the base profile in treat (v^0.55 lifts
        # rares, compresses dominants -> high Shannon/Simpson) and sharpen
        # it in control (v^1.7); richness — each control sample randomly
        # loses ~a quarter of its rarest taxa (with jitter so Observed has
        # within-group variance).
        flatten = 0.55 if treat else 1.7
        even_sigma = 0.30 if treat else 0.55
        col = {}
        for sp in SPECIES:
            name = sp[5]
            fold = TREAT_FOLD.get(name, 1.0) if treat else 1.0
            v = (base[name] ** flatten) * lognorm(rng, 0, even_sigma) * fold
            col[name] = 0.0 if v < 1e-4 else v
        if not treat:
            ranked = sorted(col, key=col.get)
            n_drop = len(ranked) // 4 + rng.randint(-2, 3)
            for name in ranked[:max(1, n_drop)]:
                if col[name] < 0.5:  # never drop established base taxa
                    col[name] = 0.0
        total = sum(col.values())
        matrix[s] = {n: 100.0 * v / total for n, v in col.items()}
    return matrix


def write_taxonomy_tsv(out, matrix):
    """MetaPhlAn-style merged table with all rank prefixes + #metaphlan4 comment."""
    clades = {}  # clade -> [values per sample]
    for s in SAMPLES:
        for sp in SPECIES:
            lin = lineage_of(sp)
            v = matrix[s][sp[5]]
            parts = lin.split("|")
            for i in range(1, len(parts) + 1):
                key = "|".join(parts[:i])
                clades.setdefault(key, {s: 0.0 for s in SAMPLES})
                clades[key][s] += v
    lines = ["ID\t" + "\t".join(SAMPLES) + "\n", "#metaphlan4\n"]
    for key in sorted(clades):
        lines.append(fmt_row(key, [clades[key][s] for s in SAMPLES]))
    return write_text(os.path.join(out, "result/metaphlan4/merged/taxonomy.tsv"), "".join(lines))


def write_species_matrix(out, matrix):
    """Species x sample table (species-level subset for 96c)."""
    lines = ["feature\t" + "\t".join(SAMPLES) + "\n"]
    for sp in SPECIES:
        lines.append(fmt_row(lineage_of(sp), [matrix[s][sp[5]] for s in SAMPLES]))
    return write_text(os.path.join(out, "result/demo/bacteria_species_abundance.tsv"), "".join(lines))


def gen_virus(rng):
    """vOTU-level TPM matrix + metadata (lengths, folds).

    vOTU ids use the k127_{n} contig convention (singleton clusters), matching
    scripts/91_diversity.R: gene ``k127_42_7`` strips its gene number suffix to
    the contig, which must be both the clusters.tsv object and the geNomad
    seq_name, or every vOTU is dropped as unclassified.
    """
    n = 120
    votus = []
    tpm = {}
    for i in range(1, n + 1):
        vid = "k127_%d" % (5000 + i)
        fold = 1.0
        if i <= 15:
            fold = rng.uniform(3.0, 8.0)
        base = lognorm(rng, math.log(1.2), 1.3)
        votus.append((vid, vid, int(rng.uniform(8000, 60000)), fold))
        for s in SAMPLES:
            treat = GROUPS[s] == "treat"
            v = base * lognorm(rng, 0, 0.9) * (fold if treat else 1.0)
            tpm[(vid, s)] = 0.0 if v < 0.01 else v
    return votus, tpm


def virus_lineage(rng, taxon, short=False):
    order, family, genus = taxon
    head = "Viruses;Duplodnaviria;Heunggongvirae;Uroviricota;Caudoviricetes"
    if short:
        return head
    return "%s;%s;%s;%s" % (head, order, family, genus)


def write_virus_tables(out, rng, votus, tpm):
    # 1. simple vOTU x sample count table (93 co-occurrence / ML input)
    lines = ["vOTU\t" + "\t".join(SAMPLES) + "\n"]
    for vid, _, _, _ in votus:
        vals = []
        for s in SAMPLES:
            v = tpm[(vid, s)]
            vals.append(int(round(v * rng.uniform(60, 140))) if v > 0 else 0)
        lines.append("\t".join([vid] + [str(v) for v in vals]) + "\n")
    write_text(os.path.join(out, "result/virus/votu/votu_table.tsv"), "".join(lines))

    # 2. clusters.tsv (contig -> vOTU representative)
    lines = ["object\tcluster\n"]
    for vid, contig, _, _ in votus:
        lines.append("%s\t%s\n" % (contig, vid))
    write_text(os.path.join(out, "result/virus/votu/vclust/clusters.tsv"), "".join(lines))

    # 3. geNomad taxonomy + lengths
    tax_lines = ["seq_name\tn_genes_with_taxonomy\tagreement\ttaxid\tlineage\n"]
    len_lines = ["vOTU\tlength_bp\n"]
    for idx, (vid, contig, length, _) in enumerate(votus):
        len_lines.append("%s\t%d\n" % (vid, length))
        if idx % 12 == 11:  # ~8% absent from geNomad -> unclassified
            continue
        short = idx % 7 == 5
        taxon = VIRUS_TAXA[idx % len(VIRUS_TAXA)]
        taxid = 2731000 + (idx % 41) * 17
        tax_lines.append("%s\t%d\t%.4f\t%d\t%s\n" % (
            contig, 4 + idx % 9, 0.85 + (idx % 10) / 60.0, taxid,
            virus_lineage(rng, taxon, short=short)))
    write_text(os.path.join(out, "result/virus/votu/genomad/virus_taxonomy.tsv"), "".join(tax_lines))
    write_text(os.path.join(out, "result/virus/votu/votu_lengths.tsv"), "".join(len_lines))

    # 4. gene-level annotated table (91 diversity input)
    classified = {}
    for idx, (vid, contig, _, _) in enumerate(votus):
        short = idx % 7 == 5
        taxon = VIRUS_TAXA[idx % len(VIRUS_TAXA)]
        if idx % 12 == 11:
            classified[vid] = "Unclassified"
        else:
            lin = virus_lineage(rng, taxon, short=short).split(";")
            classified[vid] = ";".join(lin[4:])
    header = ["gene", "length"] + ["%s_tpm" % s for s in SAMPLES] + ["%s_count" % s for s in SAMPLES] + ["taxonomy"]
    lines = ["\t".join(header) + "\n"]
    for vid, contig, length, _ in votus:
        n_genes = max(2, min(60, length // 950))
        gene_len = length // n_genes
        weights = [gene_len * rng.uniform(0.5, 1.5) for _ in range(n_genes)]
        wsum = sum(weights)
        for g in range(1, n_genes + 1):
            vals_tpm, vals_cnt = [], []
            for s in SAMPLES:
                v = tpm[(vid, s)] * weights[g - 1] / wsum
                vals_tpm.append(v)
                vals_cnt.append(int(round(v * rng.uniform(60, 140))) if v > 0 else 0)
            row = ["%s_%d" % (contig, g), str(gene_len)]
            row += ["%.6f" % v for v in vals_tpm]
            row += ["%.3f" % v for v in vals_cnt]
            row.append(classified[vid])
            lines.append("\t".join(row) + "\n")
    return write_text(os.path.join(out, "result/virus/votu/table/vOTU_table_ann.txt"), "".join(lines))


def write_fungi_profiles(out, rng):
    """Per-sample fungi profiles.

    Values are INTEGER counts on a per-mille scale: microeco/vegan only compute
    the full alpha metric set (Observed/Chao1/ACE) for integer count tables,
    and 91_diversity.R's final alpha summary rbind()s all dimensions together,
    so a float-valued fungi table crashes the whole script with a column-count
    mismatch.
    """
    for s in SAMPLES:
        treat = GROUPS[s] == "treat"
        rows = {}
        for ph, cl, or_, fa, ge, sp, tid in FUNGI:
            fold = FUNGAL_TREAT_FOLD.get(sp, 1.0) if treat else 1.0
            v = lognorm(rng, math.log(3), 1.1) * fold
            rows[sp] = 0 if v < 1.5 else int(round(v))  # counts, 0 for rare hits
        total = sum(rows.values())
        body = ["UNCLASSIFIED\t-1\t%d\t\n" % max(0, 1000 - total),
                "k__Fungi\t4751\t%d\t\n" % total]
        for ph, cl, or_, fa, ge, sp, tid in FUNGI:
            if rows[sp] <= 0:
                continue
            lin = "k__Fungi|p__%s|c__%s|o__%s|f__%s|g__%s|s__%s" % (ph, cl, or_, fa, ge, sp.replace(" ", "_"))
            body.append("%s\t%d\t%d\t\n" % (lin, tid, rows[sp]))
        text = ("#mpa_vOct22_CHOCOPhlAnSGB_202212\n"
                "#synthetic demo profile (make_demo.py)\n"
                "#%d reads processed\n"
                "#SampleID\tMetaphlan_Analysis\n"
                "#clade_name\tNCBI_tax_id\trelative_abundance\tadditional_species\n" % (80000 + int(rng.uniform(0, 40000)))
                + "".join(sorted(body)))
        write_text(os.path.join(out, "result/fungi/metaphlan4/%s/%s_profile.txt" % (s, s)), text)


def write_humann3(out, rng):
    for s in SAMPLES:
        treat = GROUPS[s] == "treat"
        ab_lines = ["# Pathway\t%s_Abundance\n" % s]
        cov_lines = ["# Pathway\t%s_Coverage\n" % s]
        for pw in PATHWAYS:
            fold = PATHWAY_TREAT_FOLD.get(pw, 1.0) if treat else 1.0
            ab = lognorm(rng, math.log(150), 1.1) * fold
            ab_lines.append("%s\t%.4f\n" % (pw, ab))
            cov = min(1.0, lognorm(rng, math.log(0.55), 0.45) * (1.0 + math.log(fold) / 4.0))
            cov_lines.append("%s\t%.4f\n" % (pw, cov))
            if fold > 1.0 and rng.random() < 0.5:  # stratified contributors
                sp = SPECIES[int(rng.uniform(0, len(SPECIES)))]
                strain = "%s|%s.%s" % (pw, sp[4], sp[5].replace(" ", "_"))
                ab_lines.append("%s\t%.4f\n" % (strain, ab * 0.6))
                ab_lines.append("%s|unclassified\t%.4f\n" % (pw, ab * 0.4))
        unmapped = rng.uniform(3.8e5, 6.2e5)
        header_rows = [
            "UNMAPPED\t%.4f\n" % unmapped,
            "UNINTEGRATED\t%.4f\n" % (unmapped * rng.uniform(0.6, 0.9)),
            "UNINTEGRATED|unclassified\t%.4f\n" % (unmapped * rng.uniform(0.2, 0.4)),
        ]
        write_text(os.path.join(out, "result/humann3/%s/%s_pathabundance.tsv" % (s, s)),
                   "# Pathway\t%s_Abundance\n" % s + "".join(header_rows) + "".join(ab_lines[1:]))
        write_text(os.path.join(out, "result/humann3/%s/%s_pathcoverage.tsv" % (s, s)), "".join(cov_lines))


def write_integration(out, rng):
    for name, feature_col, features in (
            ("kegg_ko", "KEGG_KO", KO_FEATURES),
            ("cog", "COG_category", COG_FEATURES)):
        lines = ["%s\t%s\n" % (feature_col, "\t".join(SAMPLES))]
        enriched = set(rng.sample(features, max(4, len(features) // 5)))
        for f in features:
            vals = []
            for s in SAMPLES:
                fold = rng.uniform(2.0, 4.5) if (GROUPS[s] == "treat" and f in enriched) else 1.0
                vals.append(lognorm(rng, math.log(30), 1.0) * fold)
            lines.append("\t".join([f] + ["%.4f" % v for v in vals]) + "\n")
        write_text(os.path.join(out, "result/integration/bacteria/%s_abundance.tsv" % name), "".join(lines))


def write_metadata(out, rng):
    ages = {s: int(rng.uniform(20, 65)) for s in SAMPLES}
    bmis = {s: round(rng.uniform(18.5, 34.9), 1) for s in SAMPLES}
    csv = "sample_id,group,host_type,age,bmi\n"
    for s in SAMPLES:
        csv += "%s,%s,human,%d,%.1f\n" % (s, GROUPS[s], ages[s], bmis[s])
    # Comma-separated copy under an ignored path (Project/*/result/ is
    # gitignored; consumers taking -m get this file).
    write_text(os.path.join(out, "result/demo/metadata.csv"), csv)
    # 99a_core_microbiome.R comparative mode expects literal case/control values
    write_text(os.path.join(out, "result/demo/metadata_case_control.csv"),
               csv.replace(",treat,", ",case,"))
    tsv = "\tsample_id\tgroup\thost_type\tage\tbmi\n"
    for s in SAMPLES:
        tsv += "%s\t%s\t%s\thuman\t%d\t%.1f\n" % (s, s, GROUPS[s], ages[s], bmis[s])
    return write_text(os.path.join(out, "result/stat/metadata.tsv"), tsv)


def write_krona_counts(out, matrix):
    counts = {}
    for s in SAMPLES:
        for sp in SPECIES:
            lin = lineage_of(sp).split("|")
            ranks = [p[3:].replace("_", " ") for p in lin]
            key = tuple(ranks)
            counts.setdefault(key, 0)
            counts[key] += int(round(matrix[s][sp[5]] * 10))
    rows = []
    for key, v in counts.items():
        if v > 0:
            rows.append("%d\t%s\n" % (v, "\t".join(key)))
    rows.sort(key=lambda r: -int(r.split("\t")[0]))
    return write_text(os.path.join(out, "result/demo/krona_counts.tsv"), "".join(rows))


def write_fastp_json(out):
    for i, s in enumerate(SAMPLES[:3]):
        total = 7_500_000 + i * 412_345
        before = {"total_reads": total, "total_bases": total * 150,
                  "reads_too_short": 1200 + i * 37, "reads_too_long": 0,
                  "q20_rate": 0.952 + i * 0.002, "q30_rate": 0.907 + i * 0.002,
                  "read1_mean_length": 150, "gc_content": 0.44 + i * 0.004}
        after = {"total_reads": int(total * 0.94), "total_bases": int(total * 150 * 0.95),
                 "reads_too_short": 0, "reads_too_long": 0,
                 "q20_rate": 0.971 + i * 0.001, "q30_rate": 0.936 + i * 0.001,
                 "read1_mean_length": 150, "gc_content": 0.45 + i * 0.003}
        doc = {
            "summary": {
                "before_filtering": before, "after_filtering": after,
                "filtering_result": {"passed_filter_reads": after["total_reads"],
                                     "low_quality_reads": int(total * 0.04),
                                     "too_many_N_reads": 310 + i * 5,
                                     "too_short_reads": 1200 + i * 37,
                                     "too_long_reads": 0},
                "duplication": {"rate": round(0.08 + i * 0.01, 4), "size": 500},
                "adapter_cutting": {"adapter_trimmed_reads": int(total * 0.021 + i * 991),
                                    "adapter_trimmed_bases": int(total * 3.1)},
            },
            "command": "fastp -i demo_R1.fq.gz -I demo_R2.fq.gz -o clean_R1.fq.gz -O clean_R2.fq.gz",
            "detected_adapter_sequence": "CTGTCTCTTATACACATCT",
        }
        write_text(os.path.join(out, "temp/01_qc/%s.json" % s), json.dumps(doc, indent=2) + "\n")


# ------------------------------------------------------------------- main -----
def main():
    ap = argparse.ArgumentParser(description="Fabricate the synthetic VisDemo project")
    ap.add_argument("--out", default=os.path.join(REPO, "Project", "VisDemo"),
                    help="output project directory (default: Project/VisDemo)")
    ap.add_argument("--seed", type=int, default=42, help="random seed (default: 42)")
    args = ap.parse_args()
    out = os.path.abspath(args.out)
    rng = random.Random(args.seed)

    if os.path.exists(out):
        shutil.rmtree(out)  # fully deterministic: rebuild from scratch
    os.makedirs(out)

    bmatrix = gen_bacteria(rng)
    created = [
        write_taxonomy_tsv(out, bmatrix),
        write_species_matrix(out, bmatrix),
        write_metadata(out, rng),
        write_krona_counts(out, bmatrix),
    ]
    votus, tpm = gen_virus(rng)
    created.append(write_virus_tables(out, rng, votus, tpm))
    write_fungi_profiles(out, rng)
    write_humann3(out, rng)
    write_integration(out, rng)
    write_fastp_json(out)

    # Build microeco RDS files (bacteria + virus) with the companion R script.
    rds_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_demo_rds.R")
    rc = subprocess.call([RSCRIPT, rds_script, out])
    if rc != 0:
        sys.stderr.write("[ERROR] make_demo_rds.R failed with exit code %d\n" % rc)
        sys.exit(rc)
    for dim in ("bacteria", "virus"):
        created.append(os.path.join(out, "result", "stat", dim, "%s_microtable.rds" % dim))

    print("[make_demo] seed=%d  workdir=%s" % (args.seed, out))
    for p in created:
        print("  wrote %s (%d bytes)" % (os.path.relpath(p, out), os.path.getsize(p)))


if __name__ == "__main__":
    main()
