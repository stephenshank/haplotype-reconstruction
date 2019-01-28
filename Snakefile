import os


ACCESSION_NUMBERS = ['ERS6610%d' % i for i in range(87, 94)]
HYPHY_PATH = "/Users/stephenshank/Software/lib/hyphy"

rule reference_index:
  input:
    "input/{reference}.fasta"
  output:
    "output/references/{reference}.fasta"
  shell:
    """
      cp {input} {output}
      bwa index {output}
    """

rule map_reads:
  input:
    fastq="input/{accession}.fastq",
    reference=rules.reference_index.output
  output:
    "output/{accession}/{reference}/mapped.sam"
  shell:
    "bwa mem {input.reference} {input.fastq} > {output}"

rule sort_and_index:
  input:
    rules.map_reads.output
  output:
    "output/{accession}/{reference}/sorted.bam"
  shell:
    """
      samtools sort {input} > {output}
      samtools index {output}
    """

rule reconstruct_haplotypes:
  input:
    rules.sort_and_index.output
  output:
    "output/{accession}/{reference}/haplotypes/final_haplo.fasta"
  script:
    "invoke_regress_haplo.R"

rule concatenate:
  input:
    expand("output/{accession}/{{reference}}/haplotypes/final_haplo.fasta", accession=ACCESSION_NUMBERS)
  output:
    "output/{reference}/unaligned.fasta"
  params:
    lambda wildcards: ' '.join(["output/%s/%s/haplotypes/final_haplo.fasta" % (accession, wildcards.reference) for accession in ACCESSION_NUMBERS])
  shell:
    "cat {params} > {output}"

rule alignment:
  input:
    rules.concatenate.output[0]
  output:
    "output/{reference}/aligned.fasta"
  shell:
    "mafft {input} > {output}"

rule recombination_screening:
  input:
    rules.alignment.output[0]
  output:
    gard_json="output/{reference}/GARD.json",
    nexus="output/{reference}/seqs_and_trees.nex"
  params:
    gard_path="%s/TemplateBatchFiles/GARD.bf" % HYPHY_PATH,
    gard_output=os.getcwd() + "/output/{reference}/aligned.GARD",
    final_out=os.getcwd() + "/output/{reference}/aligned.GARD_finalout",
    translate_gard_j=os.getcwd() + "/output/{reference}/aligned.GARD.json",
    translated_json=os.getcwd() + "/output/{reference}/GARD.json",
    lib_path=HYPHY_PATH,
    alignment_path=os.getcwd() + "/output/{reference}/aligned.fasta"
  shell:
    """
      mpirun -np 2 HYPHYMPI LIBPATH={params.lib_path} {params.gard_path} {params.alignment_path} '010010' None {params.gard_output}
      translate-gard -i {params.gard_output} -j {params.translate_gard_j} -o {params.translated_json}
      mv {params.final_out} {output.nexus}
    """

rule site_selection:
  input:
    rules.recombination_screening.output.nexus
  output:
    "output/{reference}/seqs_and_trees.nex.FUBAR.json"
  params:
    full_nexus_path=os.getcwd() + "/" + rules.recombination_screening.output.nexus,
    fubar_path="%s/TemplateBatchFiles/SelectionAnalyses/FUBAR.bf" % HYPHY_PATH,
    lib_path=HYPHY_PATH
  shell:
    "(echo 1; echo {params.full_nexus_path}; echo 20; echo 1; echo 5; echo 2000000; echo 1000000; echo 100; echo .5;) | HYPHYMP LIBPATH={params.lib_path} {params.fubar_path}"

rule gene_selection:
  input:
    rules.recombination_screening.output.nexus
  output:
    "output/{reference}/seqs_and_trees.nex.BUSTED.json"
  params:
    full_nexus_path=os.getcwd() + "/" + rules.recombination_screening.output.nexus,
    busted_path="%s/TemplateBatchFiles/SelectionAnalyses/BUSTED.bf" % HYPHY_PATH,
    lib_path=HYPHY_PATH
  shell:
    "(echo 1; echo {params.full_nexus_path}; echo 2;) | HYPHYMP LIBPATH={params.lib_path} {params.busted_path}"

rule full_analysis:
  input:
    rules.site_selection.output[0],
    rules.gene_selection.output[0]
  output:
    "output/{reference}/results.tar.gz"
  shell:
    "tar cvzf {output} {input[0]} {input[1]}"
