#!/usr/bin/env python3
"""
脚本名: 43c_fba_simulate.py
功  能: COBRApy FBA (Flux Balance Analysis) 代谢能力预测
        基于 SBML 格式的基因组尺度代谢模型进行：
          1. 生长速率预测（FBA 优化）
          2. 反应通量分布分析
          3. 基因敲除模拟（必需基因鉴定）
          4. 底物利用能力测试

依  赖: 43_bac_gem_gapseq.sh 的 SBML 模型输出
输  入: ${WORKDIR}/result/gem/gapseq/{mag_name}/{mag_name}.xml
输  出: ${WORKDIR}/result/gem/fba/{mag_name}/
          {mag_name}_growth_rate.txt        — 预测生长速率
          {mag_name}_flux_distribution.tsv  — 反应通量分布
          {mag_name}_essential_genes.tsv    — 必需基因列表
          {mag_name}_substrate_utilization.tsv — 底物利用预测

参  考: Orth et al. 2010 Nature Biotechnology (FBA)
        Ebrahim et al. 2013 BMC Systems Biology (COBRApy)
用  法: python3 43c_fba_simulate.py --model MODEL.xml --output-dir OUTPUT/
"""

import argparse
import sys
from pathlib import Path
import pandas as pd
import cobra
from cobra.flux_analysis import single_gene_deletion

def setup_argparse():
    parser = argparse.ArgumentParser(
        description='COBRApy FBA metabolic capability prediction'
    )
    parser.add_argument('--model', required=True,
                        help='Path to SBML model file (.xml)')
    parser.add_argument('--output-dir', required=True,
                        help='Output directory')
    parser.add_argument('--threads', type=int, default=1,
                        help='Number of threads for parallel gene deletion')
    parser.add_argument('--substrates', default='',
                        help='Comma-separated substrate list to test (default: auto-detect from model)')
    return parser.parse_args()

def load_model(model_path):
    """Load SBML model with error handling"""
    try:
        model = cobra.io.read_sbml_model(str(model_path))
        print(f"[FBA] Model loaded: {model.id}")
        print(f"[FBA] Reactions: {len(model.reactions)}, Metabolites: {len(model.metabolites)}, Genes: {len(model.genes)}")

        # Check if objective function is set
        if not model.objective or len(model.objective.variables) == 0:
            print("[WARNING] Model has no objective function set")
            # Try to find biomass reaction
            biomass_rxns = [rxn for rxn in model.reactions if 'biomass' in rxn.id.lower()]
            if biomass_rxns:
                model.objective = biomass_rxns[0]
                print(f"[FBA] Set objective to: {biomass_rxns[0].id}")
            else:
                print("[WARNING] No biomass reaction found, FBA may fail")

        return model
    except Exception as e:
        print(f"[ERROR] Failed to load model: {e}", file=sys.stderr)
        sys.exit(1)

def run_fba(model):
    """Run basic FBA optimization"""
    print("[FBA] Running FBA optimization...")
    try:
        solution = model.optimize()
        if solution.status == 'optimal':
            growth_rate = solution.objective_value
            print(f"[FBA] Growth rate: {growth_rate:.6f}")
            return solution
        else:
            print(f"[WARNING] FBA optimization status: {solution.status}")
            return None
    except Exception as e:
        print(f"[ERROR] FBA optimization failed: {e}", file=sys.stderr)
        return None

def export_flux_distribution(model, solution, output_file):
    """Export reaction flux distribution"""
    if solution is None or solution.status != 'optimal':
        print("[WARNING] Skipping flux distribution export (no optimal solution)")
        return

    print(f"[FBA] Exporting flux distribution to {output_file}")
    flux_data = []
    for rxn in model.reactions:
        flux_data.append({
            'reaction_id': rxn.id,
            'reaction_name': rxn.name,
            'flux': solution.fluxes[rxn.id],
            'lower_bound': rxn.lower_bound,
            'upper_bound': rxn.upper_bound,
            'subsystem': rxn.subsystem
        })

    df = pd.DataFrame(flux_data)
    df.to_csv(output_file, sep='\t', index=False)
    print(f"[FBA] Exported {len(df)} reactions")

def identify_essential_genes(model, output_file, threads=1):
    """Identify essential genes via single gene deletion"""
    if len(model.genes) == 0:
        print("[WARNING] No genes in model, skipping gene deletion analysis")
        return

    print(f"[FBA] Running single gene deletion on {len(model.genes)} genes...")
    try:
        deletion_results = single_gene_deletion(
            model,
            model.genes,
            processes=threads
        )

        # Essential genes: knockout causes growth < 1% of wildtype
        wildtype_growth = model.optimize().objective_value
        threshold = wildtype_growth * 0.01

        essential_data = []
        # DataFrame columns: ['ids', 'growth', 'status']
        # 'ids' is a set object like {gene_id} or {spontaneous}
        for row in deletion_results.itertuples(index=False):
            gene_ids = row.ids  # set object
            growth = row.growth
            status = row.status

            # Skip spontaneous reactions (no gene)
            if 'spontaneous' in gene_ids:
                continue

            # Extract gene ID from set
            gene_id = list(gene_ids)[0] if len(gene_ids) > 0 else 'unknown'

            if growth < threshold and status == 'optimal':
                essential_data.append({
                    'gene_id': gene_id,
                    'wildtype_growth': wildtype_growth,
                    'knockout_growth': growth,
                    'growth_reduction_pct': (1 - growth/wildtype_growth) * 100 if wildtype_growth > 0 else 100,
                    'status': status
                })

        df = pd.DataFrame(essential_data)
        df.to_csv(output_file, sep='\t', index=False)
        print(f"[FBA] Identified {len(df)} essential genes (out of {len(model.genes)})")

    except Exception as e:
        print(f"[ERROR] Gene deletion analysis failed: {e}", file=sys.stderr)

def test_substrate_utilization(model, substrates, output_file):
    """Test growth on different substrates

    Note: This function tests substrates that exist in the model.
    CarveMe models only include exchange reactions for compounds
    that the organism can actually produce/consume based on its genome.
    If a substrate is not found, it means the organism lacks the
    metabolic pathways for that compound.
    """
    print(f"[FBA] Testing substrate utilization")

    # Get all exchange reactions in the model
    all_exchanges = [rxn.id for rxn in model.exchanges]
    print(f"[FBA] Model has {len(all_exchanges)} exchange reactions")

    # Common substrate-to-exchange reaction mapping
    substrate_map = {
        'glucose': ['EX_glc__D_e', 'EX_glc_e', 'EX_glucose_e'],
        'acetate': ['EX_ac_e', 'EX_acetate_e'],
        'propionate': ['EX_ppa_e', 'EX_propionate_e'],
        'butyrate': ['EX_but_e', 'EX_butyrate_e'],
        'lactate': ['EX_lac__D_e', 'EX_lac__L_e', 'EX_lactate_e'],
        'succinate': ['EX_succ_e', 'EX_succinate_e']
    }

    results = []

    # If substrates list provided, test those
    if substrates and len(substrates) > 0:
        test_substrates = substrates
    else:
        # Otherwise, auto-detect testable carbon sources from model
        print("[FBA] No substrates specified, auto-detecting from model...")
        test_substrates = []
        # Look for common carbon sources in model exchanges
        carbon_keywords = ['glc', 'glucose', 'fru', 'fructose', 'xyl', 'xylose',
                          'ac', 'acetate', 'ppa', 'propionate', 'but', 'butyrate',
                          'lac', 'lactate', 'succ', 'succinate']
        for rxn in model.exchanges:
            rxn_lower = rxn.id.lower()
            for keyword in carbon_keywords:
                if keyword in rxn_lower and rxn.id not in test_substrates:
                    test_substrates.append(rxn.id)
                    break
        print(f"[FBA] Auto-detected {len(test_substrates)} potential substrates")

    for substrate in test_substrates:
        substrate = substrate.strip()

        # Check if this is already an exchange reaction ID
        if substrate.startswith('EX_'):
            ex_rxn_id = substrate
            substrate_name = substrate.replace('EX_', '').replace('_e', '')
        else:
            # Map common name to exchange reaction
            if substrate not in substrate_map:
                print(f"[WARNING] Unknown substrate: {substrate}, skipping")
                continue

            # Find the exchange reaction
            ex_rxn_id = None
            for rxn_id in substrate_map[substrate]:
                if rxn_id in model.reactions:
                    ex_rxn_id = rxn_id
                    break

            if ex_rxn_id is None:
                print(f"[WARNING] Exchange reaction not found for {substrate}")
                results.append({
                    'substrate': substrate,
                    'can_utilize': False,
                    'growth_rate': 0.0,
                    'exchange_reaction': 'not_found'
                })
                continue
            substrate_name = substrate

        ex_rxn = model.reactions.get_by_id(ex_rxn_id)

        # Test growth with this substrate
        with model:  # context manager to revert changes
            # Close only carbon source exchange reactions, keep O2/H2O/ions open
            # Common carbon sources to close
            carbon_sources = ['glc', 'glucose', 'fru', 'fructose', 'xyl', 'xylose',
                            'ac', 'acetate', 'ppa', 'propionate', 'but', 'butyrate',
                            'lac', 'lactate', 'succ', 'succinate', 'pyr', 'pyruvate',
                            'mal', 'malate', 'fum', 'fumarate', 'cit', 'citrate']

            for rxn in model.exchanges:
                # Close if it's a carbon source exchange
                if any(cs in rxn.id.lower() for cs in carbon_sources):
                    rxn.lower_bound = 0.0
                # Keep other exchanges (O2, H2O, ions, etc.) at their original bounds

            # Allow uptake of this substrate
            ex_rxn.lower_bound = -10.0

            try:
                solution = model.optimize()
                can_grow = solution.status == 'optimal' and solution.objective_value > 0.01
                growth_rate = solution.objective_value if solution.status == 'optimal' else 0.0

                results.append({
                    'substrate': substrate_name,
                    'can_utilize': can_grow,
                    'growth_rate': growth_rate,
                    'exchange_reaction': ex_rxn_id
                })

                print(f"[FBA]   {substrate_name}: {'YES' if can_grow else 'NO'} (growth={growth_rate:.4f})")

            except Exception as e:
                print(f"[WARNING] Failed to test {substrate_name}: {e}")
                results.append({
                    'substrate': substrate_name,
                    'can_utilize': False,
                    'growth_rate': 0.0,
                    'exchange_reaction': ex_rxn_id
                })

    df = pd.DataFrame(results)
    df.to_csv(output_file, sep='\t', index=False)
    print(f"[FBA] Substrate utilization results exported")

def main():
    args = setup_argparse()

    # Validate inputs
    model_path = Path(args.model)
    if not model_path.exists():
        print(f"[ERROR] Model file not found: {model_path}", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    mag_name = model_path.stem  # filename without extension

    # Load model
    model = load_model(model_path)

    # 1. Run FBA
    solution = run_fba(model)
    if solution:
        growth_file = output_dir / f"{mag_name}_growth_rate.txt"
        with open(growth_file, 'w') as f:
            f.write(f"{solution.objective_value:.6f}\n")
        print(f"[FBA] Growth rate saved to {growth_file}")

    # 2. Export flux distribution
    flux_file = output_dir / f"{mag_name}_flux_distribution.tsv"
    export_flux_distribution(model, solution, flux_file)

    # 3. Identify essential genes
    essential_file = output_dir / f"{mag_name}_essential_genes.tsv"
    identify_essential_genes(model, essential_file, threads=args.threads)

    # 4. Test substrate utilization
    if args.substrates:
        substrates = args.substrates.split(',')
    else:
        substrates = []  # Empty list triggers auto-detection in test_substrate_utilization
    substrate_file = output_dir / f"{mag_name}_substrate_utilization.tsv"
    test_substrate_utilization(model, substrates, substrate_file)

    print("[FBA] All analyses complete")

if __name__ == '__main__':
    main()
