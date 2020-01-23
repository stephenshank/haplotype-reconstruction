import os
import json

import pysam
from convex_qsr import covarying_sites_io
from convex_qsr import superread_json_io
from convex_qsr import superread_fasta_io
from convex_qsr import full_graph_io
from convex_qsr import reduced_graph_io
from convex_qsr import candidates_io

from py import *


with open('simulations.json') as simulation_file:
  SIMULATION_INFORMATION = json.load(simulation_file)
ACCESSION_NUMBERS = ['ERS6610%d' % i for i in range(87, 94)]
SIMULATED_DATASETS = ['sim-' + dataset for dataset in SIMULATION_INFORMATION.keys()]
RECONSTRUCTION_DATASETS = [
  "93US141_100k_14-159320-1GN-0_S16_L001_R1_001",
  "PP1L_S45_L001_R1_001",
  "sergei1",
  "FiveVirusMixIllumina_1"
]
SRA = [
  "SRX3661402"
]
FVM_RECORDS = ['89_6', 'HXB2', 'JRCSF', 'NL43', 'YU2']
ALL_DATASETS = ACCESSION_NUMBERS + SIMULATED_DATASETS + RECONSTRUCTION_DATASETS
KNOWN_TRUTH = SIMULATED_DATASETS + ["FiveVirusMixIllumina_1"]
ALL_REFERENCES = ["env", "rev", "vif", "pol", "prrt", "rt", "pr", "gag", "int", "tat"] # + ["nef", "vpr"] 
REFERENCE_SUBSET = ["env", "pol", "gag"]
HYPHY_PATH = "/Users/stephenshank/Software/lib/hyphy"
HAPLOTYPERS = ["abayesqr", "savage", "regress_haplo", "quasirecomb"]

wildcard_constraints:
  dataset="[^/]+",
  simulated_dataset="[^/]+"

rule all_haplotypers:
  input:
    expand(
      "output/{dataset}/fastp/bowtie2/{reference}/{haplotyper}/haplotypes.fasta",
      dataset=ALL_DATASETS,
      reference=REFERENCE_SUBSET,
      haplotyper=HAPLOTYPERS
    ),
    expand(
      "output/{dataset}/reads_fastqc.html",
      dataset=ALL_DATASETS
    ),
    expand(
      "output/{dataset}/qfilt/bealign/{reference}/qualimapReport.html",
      dataset=ALL_DATASETS,
      reference=REFERENCE_SUBSET
    ),
    expand(
      "output/{dataset}/fastp/bowtie2/{reference}/qualimapReport.html",
      dataset=ALL_DATASETS,
      reference=REFERENCE_SUBSET
    )

rule all_acme_running:
  input:
    "output/FiveVirusMixIllumina_1/fastp/bowtie2/gag/acme/truth_and_haplotypes.json",
    "output/FiveVirusMixIllumina_1/fastp/bowtie2/pol/acme/truth_and_haplotypes.json"
  output:
    "output/running_report.csv"
  run:
    report(input, output[0], 'running')

rule all_acme_reconstructing:
  input:
    "output/sim-diverged_pair/fastp/bowtie2/pol/acme/truth_and_haplotypes.json",
    "output/sim-diverged_pair_slightly_skewed/fastp/bowtie2/pol/acme/truth_and_haplotypes.json",
    "output/sim-diverged_triplet/fastp/bowtie2/pol/acme/truth_and_haplotypes.json",
    "output/sim-diverged_triplet_slightly_skewed/fastp/bowtie2/pol/acme/truth_and_haplotypes.json",
    "output/sim-diverged_five/fastp/bowtie2/pol/acme/truth_and_haplotypes.json"
  output:
    "output/reconstruction_report.csv"
  run:
    report(input, output[0], 'reconstructing')

rule report:
  input:
    reconstructing=rules.all_acme_reconstructing.output[0],
    running=rules.all_acme_running.output[0]
  output:
    "output/report.csv"
  shell:
    """
      cat {input.reconstructing} > {output}
      tail -n +2 {input.running} >> {output}
    """

rule haplotyper_truth_report:
  input:
    expand(
      "output/{dataset}/{{qc}}/{{read_mapper}}/{reference}/{{haplotyper}}/truth_and_haplotypes.png",
      dataset=KNOWN_TRUTH,
      reference=REFERENCE_SUBSET
    )
  output:
    "output/reports/{haplotyper}-{qc}-{read_mapper}.csv"
  run:
    haplotyper_report(input, output[0])

rule all_bams:
  input:
    expand(
      "output/{dataset}/fastp/bowtie2/{reference}/sorted.bam",
      dataset=ALL_DATASETS,
      reference=REFERENCE_SUBSET,
      haplotyper=HAPLOTYPERS
    )

rule all_known_comparisons:
  input:
    expand(
      "output/{dataset}/fastp/bowtie2/{reference}/{haplotyper}/truth_and_haplotypes.png",
      dataset=KNOWN_TRUTH,
      reference=REFERENCE_SUBSET,
      haplotyper=HAPLOTYPERS
    )

##################
# RECONSTRUCTION #
##################

# Simulation

rule extract_lanl_genome:
  input:
    "input/LANL-HIV.fasta"
  output:
    "output/lanl/{lanl_id}/genome.fasta"
  run:
    extract_lanl_genome(input[0], wildcards.lanl_id, output[0])

rule extract_gene:
  input:
    reference="input/references/{gene}.fasta",
    genome=rules.extract_lanl_genome.output[0]
  output:
    sam="output/lanl/{lanl_id}/{gene}/sequence.sam",
    fasta="output/lanl/{lanl_id}/{gene}/sequence.fasta"
  conda:
    "envs/veg.yml"
  shell:
    """
      bealign -r {input.reference} {input.genome} {output.sam}
      bam2msa {output.sam} {output.fasta}
    """

rule simulation:
  input:
    rules.extract_lanl_genome.output[0]
  output:
    fastq="output/lanl/{lanl_id}/wgs.fastq",
    sam="output/lanl/{lanl_id}/wgs.sam"
  params:
    out="output/lanl/{lanl_id}/wgs"
  conda:
    "envs/ngs.yml"
  shell:
    """
      art_illumina -rs 1 -ss HS25 --samout -i {input} -l 120 -s 50 -c 1500000 -o {params.out}
      mv {params.out}.fq {output.fastq}
    """

def simulation_truth_input(wildcards):
  dataset = SIMULATION_INFORMATION[wildcards.simulated_dataset]
  lanl_ids = [info['lanl_id'] for info in dataset]
  genomes = ["output/lanl/%s/genome.fasta" % (lanl_id) for lanl_id in lanl_ids]
  return genomes

rule simulation_truth:
  input:
    simulation_truth_input
  output:
    "output/truth/sim-{simulated_dataset}/genomes.fasta"
  run:
    simulation_truth(wildcards.simulated_dataset, output[0])

rule simulation_truth_aligned:
  input:
    rules.simulation_truth.output[0],
  output:
    "output/truth/sim-{simulated_dataset}/aligned.fasta"
  shell:
    "mafft {input} > {output}"

def wgs_simulation_inputs(wildcards):
  dataset = SIMULATION_INFORMATION[wildcards.simulated_dataset]
  lanl_ids = [info['lanl_id'] for info in dataset]
  reads = ["output/lanl/%s/wgs.fastq" % (lanl_id) for lanl_id in lanl_ids]
  genomes = ["output/lanl/%s/genome.fasta" % (lanl_id) for lanl_id in lanl_ids]
  return reads + genomes

rule simulate_wgs_dataset:
  input:
    wgs_simulation_inputs,
    fasta=rules.simulation_truth_aligned.output[0]
  output:
    fastq=temp("output/sim-{simulated_dataset}_ar-{ar}_seed-{seed}/wgs.fastq"),
    json="output/sim-{simulated_dataset}_ar-{ar}_seed-{seed}/simulation_quality.json"
  run:
    simulate_wgs_dataset(
      wildcards.simulated_dataset, wildcards.ar, input.fasta, output.fastq, output.json, wildcards.seed
    )

# Situating other data

rule sra_dataset:
  output:
    "output/sra/{sra_accession}.fastq"
  params:
    "output/sra"
  shell:
    "fastq-dump --outdir {params[0]} {wildcards.sra_accession}"

def situate_input(wildcards):
  dataset = wildcards.dataset
  is_evolution_dataset = dataset[:7] == 'ERS6610'
  is_amplicon_dataset = 'amplicon' in dataset
  is_simulated_dataset = 'sim-' in dataset
  is_sra_dataset = dataset[:2] == 'SR'

  if is_evolution_dataset:
    return "input/evolution/%s.fastq" % dataset
  if is_amplicon_dataset:
    return "output/%s/amplicon.fastq" % dataset
  if is_simulated_dataset:
    return "output/%s/wgs.fastq" % dataset
  if is_sra_dataset:
    return "output/sra/%s.fastq" % dataset
  return "input/reconstruction/%s.fastq" % dataset

rule situate_data:
  input:
    situate_input
  output:
    "output/{dataset}/reads.fastq"
  shell:
    "cp {input} {output}"

# Quality control

rule qfilt:
  input:
    rules.situate_data.output[0]
  output:
    fasta="output/{dataset}/qfilt/qc.fasta",
    json="output/{dataset}/qfilt/qc.json",
    html="output/{dataset}/reads_fastqc.html"
  params:
    dir="output/{dataset}"
  conda:
    "envs/veg.yml"
  shell:
    """
      qfilt -Q {input} -q 20 -l 50 -j >> {output.fasta} 2>> {output.json}
      fastqc {input} -o {params.dir}
    """

def fasta_454(wildcards):
  if wildcards.dataset == 'example_454':
    return "input/reconstruction/3.GAC.454Reads.fna"
  head = "input/compartmentalization/"
  tail = "/".join(wildcards.dataset.split('-'))
  return head + tail + "/reads.fasta"

def qual_454(wildcards):
  if wildcards.dataset == 'example_454':
    return "input/reconstruction/3.GAC.454Reads.qual"
  head = "input/compartmentalization/"
  tail = "/".join(wildcards.dataset.split('-'))
  return head + tail + "/scores.qual"

rule qfilt_454:
  input:
    fasta=fasta_454,
    qual=qual_454
  output:
    fasta="output/{dataset}/qfilt/qc.fasta",
    json="output/{dataset}/qfilt/qc.json"
  conda:
    "envs/veg.yml"
  shell:
    "qfilt -F {input.fasta} {input.qual} -q 20 -l 50 -j >> {output.fasta} 2>> {output.json}"

rule fastp:
  input:
    rules.situate_data.output[0]
  output:
    fastq="output/{dataset}/fastp/qc.fastq",
    fasta="output/{dataset}/fastp/qc.fasta",
    json="output/{dataset}/fastp/qc.json",
    html="output/{dataset}/fastp/qc.html"
  conda:
    "envs/ngs.yml"
  shell:
    """
      fastp -A -q 30 -i {input} -o {output.fastq} -j {output.json} -h {output.html} -n 50
      cat {output.fastq} | paste - - - - | sed 's/^@/>/g'| cut -f1-2 | tr '\t' '\n' > {output.fasta}
    """

rule trimmomatic:
  input:
    rules.situate_data.output[0]
  output:
    "output/{dataset}/trimmomatic/qc.fastq"
  conda:
    "envs/ngs.yml"
  shell:
    "trimmomatic SE {input} {output} ILLUMINACLIP:TruSeq3-SE:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"

# Read mapping

rule bealign:
  input:
    qc="output/{dataset}/{qc}/qc.fasta",
    reference="input/references/{reference}.fasta"
  output:
    bam="output/{dataset}/{qc}/bealign/{reference}/mapped.bam",
    discards="output/{dataset}/{qc}/bealign/{reference}/discards.fasta"
  conda:
    "envs/veg.yml"
  shell:
    "bealign -r {input.reference} -e 0.5 -m HIV_BETWEEN_F -D {output.discards} -R {input.qc} {output.bam}"

def situate_reference_input(wildcards):
  if wildcards.reference in FVM_RECORDS:
    return "output/FiveVirusMixIllumina_1/%s.fasta" % wildcards.reference
  return "input/references/%s.fasta" % wildcards.reference

rule situate_references:
  input:
    situate_reference_input
  output:
    "output/references/{reference}.fasta"
  shell:
    "cp {input} {output}"

rule bwa:
  input:
    fastq="output/{dataset}/{qc}/qc.fastq",
    reference="output/references/{reference}.fasta"
  output:
    "output/{dataset}/{qc}/bwa/{reference}/mapped.bam"
  conda:
    "envs/ngs.yml"
  shell:
    """
      bwa index {input.reference}
      bwa mem {input.reference} {input.fastq} > {output}
    """

rule bowtie2:
  input:
    fastq="output/{dataset}/{qc}/qc.fastq",
    reference="output/references/{reference}.fasta"
  output:
    sam="output/{dataset}/{qc}/bowtie2/{reference}/mapped.sam",
    bam="output/{dataset}/{qc}/bowtie2/{reference}/mapped.bam"
  params:
    lambda wildcards: "output/references/%s" % wildcards.reference
  conda:
    "envs/ngs.yml"
  shell:
    """
      bowtie2-build {input.reference} {params}
      bowtie2 -x {params} -U {input.fastq} -S {output.sam}
      samtools view -Sb {output.sam} > {output.bam}
    """

rule sort_and_index:
  input:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/mapped.bam"
  output:
    bam="output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.bam",
    sam="output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.sam",
    index="output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.bam.bai"
  conda:
    "envs/ngs.yml"
  shell:
    """
      samtools sort {input} > {output.bam}
      samtools view -h {output.bam} > {output.sam}
      samtools index {output.bam}
    """

rule sorted_fasta:
  input:
    rules.sort_and_index.output.bam
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.fasta"
  conda:
    "envs/veg.yml"
  shell:
    "bam2msa {input} {output}"

rule qualimap:
  input:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.bam"
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/qualimapReport.html"
  params:
    dir="output/{dataset}/{qc}/{read_mapper}/{reference}"
  conda:
    "envs/ngs.yml"
  shell:
    "qualimap bamqc -bam {input} -outdir {params.dir}"

rule insertion_plot:
  input:
    rules.sort_and_index.output.bam
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/insertion_plot.png"
  script:
    "R/insertion_plot.R"

# Haplotype reconstruction (full pipelines)

rule regress_haplo_full:
  input:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.bam",
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.bam.bai",
  output:
    temp("output/{dataset}/{qc}/{read_mapper}/{reference}/regress_haplo/final_haplo.fasta")
  script:
    "R/regress_haplo/full_pipeline.R"

rule regress_haplo_rightname:
  input:
    rules.regress_haplo_full.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/regress_haplo/haplotypes.fasta"
  shell:
    "mv {input} {output}"

rule haploclique:
  input:
    bam="output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.bam",
    index="output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.bam.bai"
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/haplo_clique/result.fasta"
  params:
    move="output/{dataset}/{qc}/{read_mapper}/{reference}/haplo_clique/result.fasta.fasta"
  shell:
    """
      haploclique {input.bam} {output}
      mv {params.move} {output}
    """

rule quasirecomb_jar:
  output:
    "QuasiRecomb.jar"
  shell:
    "wget https://github.com/cbg-ethz/QuasiRecomb/releases/download/v1.2/QuasiRecomb.jar"

rule quasirecomb:
  input:
    rules.quasirecomb_jar.output[0],
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.bam"
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/quasirecomb/haplotypes.fasta"
  params:
    basedir="output/{dataset}/{qc}/{read_mapper}/{reference}/quasirecomb"
  shell:
    """
      java -jar QuasiRecomb.jar -conservative -o {params.basedir} -i {input}
      mv {params.basedir}/quasispecies.fasta {params.basedir}/haplotypes.fasta
    """

rule savage:
  input:
    bam="output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.bam",
    reference="input/references/{reference}.fasta"
  output:
    fastq="output/{dataset}/{qc}/{read_mapper}/{reference}/savage/reads.fastq",
    fasta="output/{dataset}/{qc}/{read_mapper}/{reference}/savage/haplotypes.fasta"
  params:
    outdir="output/{dataset}/{qc}/{read_mapper}/{reference}/savage",
    intermediate="output/{dataset}/{qc}/{read_mapper}/{reference}/savage/contigs_stage_c.fasta"
  shell:
    """
      bamToFastq -i {input.bam} -fq {output.fastq}
      savage -s {output.fastq} --ref `pwd`/{input.reference} --split 3 --num_threads 12 --outdir {params.outdir}
      mv {params.intermediate} {output.fasta}
    """

rule abayesqr_config:
  input:
    sam="output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.sam",
    reference="input/references/{reference}.fasta"
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/abayesqr/config",
  run:
    write_abayesqr_config(input.sam, input.reference, output[0])

rule abayesqr:
  input:
    rules.abayesqr_config.output[0]
  output:
    freq="output/{dataset}/{qc}/{read_mapper}/{reference}/abayesqr/test_Freq.txt",
    seq="output/{dataset}/{qc}/{read_mapper}/{reference}/abayesqr/test_Seq.txt",
    viralseq="output/{dataset}/{qc}/{read_mapper}/{reference}/abayesqr/test_ViralSeq.txt",
    fasta="output/{dataset}/{qc}/{read_mapper}/{reference}/abayesqr/haplotypes.fasta"
  run:
    shell("aBayesQR {input}")
    shell("mv test_Freq.txt {output.freq}")
    shell("mv test_Seq.txt {output.seq}")
    shell("mv test_ViralSeq.txt {output.viralseq}")
    parse_abayesqr_output(output.viralseq, output.fasta)

rule shorah:
  input:
    bam=rules.sort_and_index.output.bam,
    reference=rules.situate_references.output[0]
  output:
    fasta="output/{dataset}/{qc}/{read_mapper}/{reference}/shorah/haplotypes.fasta"
  params:
    workdir="output/{dataset}/{qc}/{read_mapper}/{reference}/shorah",
    bam="../sorted.bam",
    reference="../../../../../references/{reference}.fasta"
  conda:
    "envs/shorah.yml"
  shell:
    """
      cd {params.workdir}
      shorah.py -b {params.bam} -f {params.reference} -w 51
      mv sorted_global_haps.fasta haplotypes.fasta
    """

# VEG haplotype reconstruction

rule mmvc:
  input:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sorted.fasta"
  output:
    json="output/{dataset}/{qc}/{read_mapper}/{reference}/mmvc.json",
    fasta="output/{dataset}/{qc}/{read_mapper}/{reference}/mmvc.fasta"
  conda:
    "envs/veg.yml"
  shell:
    "mmvc -j {output.json} -f {output.fasta} {input}"

rule readreduce:
  input:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/mmvc.fasta"
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/veg/haplosuperreads.fasta"
  conda:
    "envs/veg.yml"
  shell:
    "readreduce -a resolve -l 30 -s 16 -o {output} {input}"

# ACME haplotype reconstruction

def true_sequences_input(wildcards):
  if wildcards.dataset == 'FiveVirusMixIllumina_1':
    return "input/5VM.fasta"
  dataset = wildcards.dataset.split('_')[0]
  return "output/truth/%s/genomes.fasta" % dataset

rule true_sequences:
  input:
    wgs=true_sequences_input,
    reference=rules.situate_references.output[0]
  output:
    fasta="output/truth/{dataset}/{reference}_gene.fasta",
    json="output/truth/{dataset}/{reference}_gene.json"
  run:
    extract_truth(input.wgs, input.reference, wildcards.dataset, wildcards.reference, output.fasta, output.json)

rule covarying_sites:
  input:
    rules.sort_and_index.output.bam
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/covarying_sites.json"
  run:
    covarying_sites_io(input[0], output[0])

rule superreads:
  input:
    alignment=rules.sort_and_index.output.bam,
    covarying_sites=rules.covarying_sites.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/superreads.json",
  run:
    superread_json_io(input.alignment, input.covarying_sites, output[0])

rule superread_fasta:
  input:
    cvs=rules.covarying_sites.output[0],
    sr=rules.superreads.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/superreads.fasta"
  run:
    superread_fasta_io(input.cvs, input.sr, output[0])

rule truth_at_cvs:
  input:
    cvs=rules.covarying_sites.output[0],
    fasta=rules.true_sequences.output.fasta
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/truth-cvs.fasta"
  run:
    restrict_fasta_to_cvs(input.fasta, input.cvs, output[0])

rule truth_and_superreads_cvs:
  input:
    truth=rules.truth_at_cvs.output[0],
    superreads=rules.superread_fasta.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/truth-sr-cvs.fasta"
  shell:
    "cat {input.truth} {input.superreads} > {output}"

rule superread_graph:
  input:
    rules.superreads.output[0],
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/graph.json"
  run:
    full_graph_io(input[0], output[0])

rule reduced_superread_graph:
  input:
    rules.superreads.output[0],
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/graph-reduced.json"
  run:
    reduced_graph_io(input[0], output[0])

rule candidates:
  input:
    graph=rules.reduced_superread_graph.output[0],
    superreads=rules.superreads.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/describing.json"
  run:
    candidates_io(input.graph, input.superreads, output[0])

# Simulation studies

def n_paths_boxplot_input(wildcards):
  template_string = "output/sim-%s_ar-%d_seed-%d/fastp/bowtie2/%s/acme/graph.json"
  input_files = []
  for seed in range(1, 11):
    for ar in [0, 5, 10, 15, 20]:
      parameters = (wildcards.simulated_dataset, ar, seed, wildcards.gene)
      input_files.append(template_string % parameters)
  return input_files

rule n_paths_boxplot:
  input:
    n_paths_boxplot_input
  output:
    "output/simulation/{simulated_dataset}/n_paths_boxplot_{gene}.png"
  run:
    n_paths_boxplot(wildcards.simulated_dataset, wildcards.gene, output[0])

'''
rule covarying_truth:
  input:
    computed=rules.error_correction.output.json,
    actual="output/{dataset}/{reference}_truth.json",
    reference=rules.situate_references.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/covarying_truth.json"
  run:
    covarying_truth(input.computed, input.actual, input.reference, output[0])

rule error_correction_fasta:
  input:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/corrected.bam"
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/corrected.fasta"
  shell:
    "bam2msa {input} {output}"

rule superread:
  input:
    bam=rules.error_correction.output.bam,
    json=rules.error_correction.output.json,
    consensus=rules.error_correction.output.consensus,
  output:
    full="output/{dataset}/{qc}/{read_mapper}/{reference}/acme/superreads-full.fasta",
    cvs="output/{dataset}/{qc}/{read_mapper}/{reference}/acme/superreads-cvs.fasta",
    describing="output/{dataset}/{qc}/{read_mapper}/{reference}/acme/describing.json",
    graph="output/{dataset}/{qc}/{read_mapper}/{reference}/acme/graph.json",
    candidates="output/{dataset}/{qc}/{read_mapper}/{reference}/acme/candidates.fasta"
  run:
    read_graph_io(
      input.bam, input.json, input.consensus,
      output.full, output.cvs, output.describing, output.graph, output.candidates,
      minimum_weight=3
    )

def reference_input(wildcards):
  format_string = "output/%s/%s_truth.fasta"
  parameters = (wildcards.dataset, wildcards.reference)
  return format_string % parameters

rule truth_and_candidates:
  input:
    candidates=rules.superread.output.candidates,
    truth=reference_input
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/truth_and_candidates.fasta"
  shell:
    "cat {input.truth} {input.candidates} > {output}"

rule truth_and_candidates_diagnostics:
  input:
    candidates=rules.superread.output.candidates,
    truth=reference_input
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/truth_and_candidates.json"
  run:
    evaluate(input.candidates, input.truth, output[0])

rule regression:
  input:
    superreads=rules.superread.output.graph,
    describing=rules.superread.output.describing,
    candidates_fasta=rules.superread.output.candidates
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/haplotypes.fasta",
  run:
    regression_io(input.superreads, input.describing, input.candidates_fasta, output[0])

rule sc_covarying_sites:
  input:
    rules.sort_and_index.output.bam
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sc/covarying_sites.json",
  run:
    sc_covarying_sites_io(input[0], output[0])

rule sc_superreads:
  input:
    alignment=rules.sort_and_index.output.bam,
    covarying_sites=rules.sc_covarying_sites.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sc/superreads.json",
  run:
    sc_superread_io(input.alignment, input.covarying_sites, output[0])

rule sc_superread_fasta:
  input:
    cvs=rules.sc_covarying_sites.output[0],
    sr=rules.sc_superreads.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sc/superreads-cvs.fasta"
  run:
    sc_srfasta_io(input.cvs, input.sr, output[0])

rule sc_embedding:
  input:
    rules.sc_superreads.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/sc/embedding_{start}_{stop}.csv"
  run:
    sc_embedding_io(input[0], output[0], wildcards.start, wildcards.stop)

# Five Virus Mixture

rule FVM_references:
  input:
    "input/5VM.fasta"
  output:
    "output/FiveVirusMixIllumina_1/reference_genomes/{strain}.fasta"
  run:
    pluck_record(input[0], output[0], wildcards.strain)

rule all_fvm_mapping_data:
  input:
    expand(
      "output/FiveVirusMixIllumina_1/{{qc}}/{{read_mapper}}/{dataset}/mapping_data.csv",
      dataset=FVM_RECORDS
    )
  output:
    "output/FiveVirusMixIllumina_1/{qc}/{read_mapper}/mapping_data.csv"
  run:
    full_fvm_mapping_dataset(input, output[0])

# Results

rule single_mapping_data:
  input:
    bam=rules.sort_and_index.output.bam,
    reference=rules.situate_references.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/mapping_data.csv"
  run:
    single_mapping_dataset(input.bam, input.reference, output[0])

rule true_covarying_sites:
  input:
    rules.true_sequences.output.fasta
  output:
    "output/truth/{dataset}/{reference}_covarying_sites.json"
  run:
    covarying_sites(input[0], output[0])

rule sorted_and_truth:
  input:
    reads=rules.sorted_fasta.output[0],
    truth=rules.true_sequences.output.fasta
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/truth_and_sorted.fasta"
  shell:
    "cat {input.truth} {input.reads} > {output}"

rule true_covarying_fasta:
  input:
    json=rules.true_covarying_sites.output[0],
    fasta=rules.true_sequences.output.fasta
  output:
    "output/{dataset}/{reference}_cvs_truth.fasta"
  run:
    covarying_fasta(input.json, input.fasta, output[0])

rule truth_and_superreads:
  input:
    truth=rules.true_covarying_fasta.output[0],
    full_superreads=rules.superread.output.full,
    cvs_superreads=rules.superread.output.cvs
  output:
    full="output/{dataset}/{qc}/{read_mapper}/{reference}/acme/truth_and_full_superreads.fasta",
    cvs="output/{dataset}/{qc}/{read_mapper}/{reference}/acme/truth_and_cvs_superreads.fasta"
  shell:
    """
      cat {input.truth} {input.full_superreads} > {output.full}
      cat {input.truth} {input.cvs_superreads} > {output.cvs}
    """

rule covarying_kmers:
  input:
    fasta=rules.true_sequences.output.fasta,
    json=rules.true_covarying_sites.output[0]
  output:
    "output/{dataset}/covarying_{reference}_{k}mers.csv"
  run:
    true_covarying_kmers(input.fasta, input.json, output[0], wildcards.k)

rule read_kmer_support:
  input:
    bam=rules.sort_and_index.output.bam,
    csv=rules.covarying_kmers.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/{k}mer_support.csv"
  run:
    kmers_in_reads(input.bam, input.csv, output[0], wildcards.k)

rule superread_agreement:
  input:
    superreads=rules.superread.output.full,
    fasta=rules.true_covarying_fasta.output[0],
    json=rules.true_covarying_sites.output[0]
  output:
    "output/{dataset}/{qc}/{read_mapper}/{reference}/acme/superread_agreement.csv"
  run:
    superread_agreement(input.superreads, input.fasta, input.json, output[0])

rule haplotypes_and_truth:
  input:
    haplotypes="output/{dataset}/{qc}/{read_mapper}/{reference}/{haplotyper}/haplotypes.fasta",
    truth=reference_input
  output:
    unaligned="output/{dataset}/{qc}/{read_mapper}/{reference}/{haplotyper}/truth_and_haplotypes_unaligned.fasta",
    aligned="output/{dataset}/{qc}/{read_mapper}/{reference}/{haplotyper}/truth_and_haplotypes.fasta",
    csv="output/{dataset}/{qc}/{read_mapper}/{reference}/{haplotyper}/truth_and_haplotypes.csv",
    json="output/{dataset}/{qc}/{read_mapper}/{reference}/{haplotyper}/truth_and_haplotypes.json"
  run:
    shell("cat {input.haplotypes} {input.truth} > {output.unaligned}")
    shell("mafft {output.unaligned} > {output.aligned}")
    pairwise_distance_csv(output.aligned, output.csv)
    result_json(output.csv, output.json)

rule haplotypes_and_truth_heatmap:
  input:
    rules.haplotypes_and_truth.output.csv
  output:
    png="output/{dataset}/{qc}/{read_mapper}/{reference}/{haplotyper}/truth_and_haplotypes.png"
  conda:
    "envs/R.yml"
  script:
    "R/truth_heatmap.R"
'''
# Regress Haplo

rule regress_haplo_bam_to_variant_calls:
  input:
    "output/{dataset}/{reference}/sorted.bam",
    "output/{dataset}/{reference}/sorted.bam.bai"
  output:
    "output/{dataset}/{reference}/variant_calls.csv"
  script:
    "R/regress_haplo/bam_to_variant_calls.R"
   
rule regress_haplo_variant_calls_to_read_table:
  input:
    "output/{dataset}/{reference}/sorted.bam",
    "output/{dataset}/{reference}/variant_calls.csv",
  output:
    "output/{dataset}/{reference}/read_table.csv"
  script:
    "R/regress_haplo/variant_calls_to_read_table.R"

rule regress_haplo_read_table_to_loci:
  input:
    rules.regress_haplo_variant_calls_to_read_table.output[0]
  output:
    "output/{dataset}/{reference}/loci.csv"
  script:
    "R/regress_haplo/read_table_to_loci.R"

rule regress_haplo_loci_to_haplotypes:
  input:
    rules.regress_haplo_read_table_to_loci.output[0]
  output:
    "output/{dataset}/{reference}/h.csv"
  script:
    "R/regress_haplo/loci_to_haplotypes.R"

rule regress_haplo_haplotypes_to_parameters:
  input:
    rules.regress_haplo_loci_to_haplotypes.output[0]
  output:
    "output/{dataset}/{reference}/P.csv"
  script:
    "R/regress_haplo/haplotypes_to_parameters.R"

rule regress_haplo_parameters_to_solutions:
  input:
    rules.regress_haplo_haplotypes_to_parameters.output[0]
  output:
    "output/{dataset}/{reference}/solutions.csv"
  script:
    "R/regress_haplo/parameters_to_solutions.R"

rule regress_haplo_solutions_to_haplotypes:
  input:
    rules.regress_haplo_parameters_to_solutions.output[0]
  output:
    "output/{dataset}/{reference}/final_haplo.csv"
  script:
    "R/regress_haplo/solutions_to_haplotypes.R"

rule regress_haplo_haplotypes_to_fasta:
  input:
    rules.regress_haplo_bam_to_variant_calls.input[0],
    rules.regress_haplo_solutions_to_haplotypes.output[0]
  output:
    "output/{dataset}/{reference}/final_haplo.fasta"
  script:
    "R/regress_haplo/haplotypes_to_fasta.R"

#############
# EVOLUTION #
#############

rule concatenate:
  input:
    expand("output/{dataset}/qfilt/bealign/{{reference}}/{{haplotyper}}/haplotypes.fasta", dataset=ACCESSION_NUMBERS)
  output:
    "output/evolution/{qc}/{read_mapper}/{reference}/{haplotyper}/unaligned.fasta"
  params:
    lambda wildcards: ' '.join([
      "output/%s/qfilt/bealign/%s/%s/haplotypes.fasta" % 
      (accession, wildcards.reference, wildcards.haplotyper) for accession in ACCESSION_NUMBERS
    ])
  shell:
    "cat {params} > {output}"

rule alignment:
  input:
    rules.concatenate.output[0]
  output:
    "output/evolution/{qc}/{read_mapper}/{reference}/{haplotyper}/aligned.fasta"
  shell:
    "mafft {input} > {output}"

rule tree:
  input:
    rules.alignment.output[0]
  output:
    "output/evolution/{qc}/{read_mapper}/{reference}/{haplotyper}/tree.new"
  shell:
    "FastTree -nt {input} > {output}"

