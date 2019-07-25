import subprocess
import os

import numpy as np
import pandas as pd
from Bio import SeqIO
from Bio.Seq import Seq
from Bio.SeqRecord import SeqRecord


def get_orf(input_genome, output_genome, orf):
    orf = int(orf)
    record = SeqIO.read(input_genome, 'fasta')
    record.seq = record.seq[orf:]
    SeqIO.write(record, output_genome, 'fasta')


def backtranslate(input_nucleotide, input_protein, output_codon):
    nucleotides = SeqIO.parse(input_nucleotide, 'fasta')
    proteins = SeqIO.parse(input_protein, 'fasta')
    codons = []

    for protein_record, nucleotide_record in zip(proteins, nucleotides):
        i = 0
        codon_list = []
        for character in protein_record.seq:
            if character != '-':
                codon = str(nucleotide_record.seq[3*i:3*i+3])
                codon_list.append(codon)
                i += 1
            else:
                codon_list.append('---')
        codon_record = SeqRecord(
            Seq(''.join(codon_list)),
            id=protein_record.id,
            description=protein_record.description
        )
        codons.append(codon_record)

    SeqIO.write(codons, output_codon, 'fasta')


def select_simulated_gene(dataset, gene, output):
    aligned_filename = "output/simulation/%s/aligned_%s_orf-%d_codon.fasta"
    nucleotide_genome_filename = "output/simulation/%s/genome.fasta" % dataset
    nucleotide_genome = SeqIO.read(nucleotide_genome_filename, 'fasta')
    max_percent_identity = 0
    desired_i = 0
    for i in range(3):
        non_gaps = 0
        matches = 0
        codon_list = []
        records = SeqIO.parse(aligned_filename % (dataset, gene, i), 'fasta')
        translated_genome = next(records)
        reference = next(records)
        genome_i = 0
        for j in range(len(reference)):
            if reference[j] != '-':
                non_gaps += 1
                codon = str(nucleotide_genome[3*genome_i+i:3*genome_i+i+3].seq)
                codon_list.append(codon)
                if reference[j] == translated_genome[j]:
                    matches += 1
            if translated_genome[j] != '-':
                genome_i += 1
        percent_identity = matches/non_gaps
        if percent_identity > max_percent_identity:
            max_percent_identity = percent_identity
            desired_i = i
            desired_codons = ''.join(codon_list)
    record = SeqRecord(
        Seq(desired_codons).ungap('-'),
        id=nucleotide_genome.id,
        description=gene
    )
    SeqIO.write(record, output, 'fasta')


def write_abayesqr_config(sam_filename, reference_filename, output):
  config_string = ("""filename of reference sequence (FASTA) : %s
filname of the aligned reads (sam format) : %s
paired-end (1 = true, 0 = false) : 0
SNV_thres : 0.01
reconstruction_start : 1
reconstruction_stop: 1300
min_mapping_qual : 20
min_read_length : 50
max_insert_length : 250
characteristic zone name : test
seq_err (assumed sequencing error rate(%%)) : 0.1
MEC improvement threshold : 0.0395 """ % (reference_filename, sam_filename) )
  with open(output, 'w') as config_file:
    config_file.write(config_string)


def parse_abayesqr_output(input_text, output_fasta):
    with open(input_text) as input_file:
        lines = input_file.readlines()
    records = []
    for i, line in enumerate(lines):
        if i % 2 == 0:
            freq = float(line.split()[-1])
            number = int(i/2)+1
            header = 'haplotype-%d_freq-%f' % (number, freq)
        if i % 2 == 1:
            seq = Seq(line.strip())
            record = SeqRecord(seq, id=header, description='')
            records.append(record)
    SeqIO.write(records, output_fasta, 'fasta')


def pairwise_distance_csv(fasta_filename, csv_filename):
    records = list(SeqIO.parse(fasta_filename, 'fasta'))
    np_seqs = np.array(
        [list(str(record.seq)) for record in records],
        dtype='<U1'
    )
    first_records = []
    second_records = []
    distances = []
    for i in range(len(records)):
        for j in range(len(records)):
            first_records.append(records[i].id)
            second_records.append(records[j].id)
            distance = (np_seqs[i, :] != np_seqs[j, :]).sum()
            distances.append(distance)
    pd.DataFrame({
        'first_record': first_records,
        'second_record': second_records,
        'distance': distances,
    }).to_csv(csv_filename)


def add_subtype_information(input_csv, output_csv):
    df = pd.read_csv(input_csv)
    df['Subtype1'] = df['ID1'].apply(lambda row: row.split('.')[0])
    df['Subtype2'] = df['ID2'].apply(lambda row: row.split('.')[0])
    df.to_csv(output_csv, index=False)


def extract_5vm_truth(input_fasta, reference_path, output_path):
    sequences = list(SeqIO.parse(input_fasta, "fasta"))
    aligned_sequences = []
    for sequence in sequences:
        sequence_id = sequence.id.replace('.', '_')
        output_dir = os.path.join("output", "FiveVirusMixIllumina_1")
        sequence_filename = "%s.fasta" % sequence_id
        sequence_path = os.path.join(output_dir, sequence_filename)
        alignment_path = os.path.join(output_dir, sequence_id + ".fasta")
        SeqIO.write(sequence, alignment_path, "fasta")
        command = [
            "water", "-asequence", sequence_path, "-bsequence",
            reference_path, "-gapopen", "10.0", "-gapextend", ".5", "-aformat",
            "fasta", "-outfile", alignment_path
        ]
        subprocess.run(command)
        aligned_sequence = list(SeqIO.parse(alignment_path, "fasta"))[0]
        aligned_sequence.seq = aligned_sequence.seq.ungap('-')
        aligned_sequences.append(aligned_sequence)
    SeqIO.write(aligned_sequences, output_path, "fasta")
