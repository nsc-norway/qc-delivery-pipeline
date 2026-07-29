#!/usr/bin/env python3
"""Randomize sequence bases and retain a small number of FASTQ reads."""

import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path
import random
import shutil
import sys
import tempfile


BASES = "ACGT"


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Randomize FASTQ sequences and retain only the first reads."
    )
    parser.add_argument(
        "inputs",
        type=Path,
        nargs="+",
        help="FASTQ files, Analysis directories, or run directories containing Analysis/.",
    )
    parser.add_argument(
        "--max-reads",
        type=int,
        default=100,
        help="Maximum complete FASTQ records to retain per file (default: 100).",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=0,
        help="Seed for reproducible random sequences (default: 0).",
    )
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument(
        "--in-place",
        action="store_true",
        help="Replace each input FASTQ after successful processing.",
    )
    destination.add_argument(
        "--output-dir",
        type=Path,
        help="Write an anonymized copy below this directory.",
    )
    args = parser.parse_args(argv)
    if args.max_reads < 0:
        parser.error("--max-reads must be zero or greater")
    return args


def find_fastqs(inputs):
    fastqs = []
    for input_path in inputs:
        if input_path.is_file():
            if input_path.name.endswith(".fastq.gz"):
                fastqs.append(input_path)
            else:
                raise ValueError(f"Not a .fastq.gz file: {input_path}")
        elif input_path.is_dir():
            analysis_dir = input_path if input_path.name == "Analysis" else input_path / "Analysis"
            if not analysis_dir.is_dir():
                raise ValueError(f"No Analysis directory found in: {input_path}")
            fastqs.extend(
                path for path in analysis_dir.rglob("*.fastq.gz") if path.is_file()
            )
        else:
            raise ValueError(f"Input does not exist: {input_path}")
    return sorted(set(fastqs))


def output_path(fastq_path, inputs, output_dir):
    containing_inputs = [path for path in inputs if path.is_dir() and fastq_path.is_relative_to(path)]
    if containing_inputs:
        source_root = min(containing_inputs, key=lambda path: len(path.parts))
        return output_dir / source_root.name / fastq_path.relative_to(source_root)
    return output_dir / fastq_path.name


def randomizer_for(fastq_path, seed):
    path_seed = hashlib.sha256(f"{seed}:{fastq_path}".encode()).digest()
    return random.Random(path_seed)


def random_sequence(length, randomizer):
    return "".join(randomizer.choices(BASES, k=length))


def validate_record(record, fastq_path, record_number):
    header, sequence, separator, quality = record
    if not header.startswith("@"):
        raise ValueError(f"{fastq_path}: record {record_number} does not start with '@'")
    if not separator.startswith("+"):
        raise ValueError(f"{fastq_path}: record {record_number} has no '+' separator")
    if len(sequence) != len(quality):
        raise ValueError(
            f"{fastq_path}: record {record_number} sequence and quality lengths differ"
        )


def anonymize_fastq(source, destination, max_reads, seed):
    randomizer = randomizer_for(source, seed)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(source, "rt", encoding="ascii", newline="") as input_file:
        with open(destination, "wb") as raw_output:
            with gzip.GzipFile(fileobj=raw_output, mode="wb", mtime=0) as gzip_output:
                with io.TextIOWrapper(gzip_output, encoding="ascii", newline="") as output_file:
                    for record_number in range(1, max_reads + 1):
                        record = [input_file.readline() for _ in range(4)]
                        if not any(record):
                            return record_number - 1
                        if not all(record):
                            raise ValueError(
                                f"{source}: incomplete record {record_number} at end of file"
                            )
                        record = [line.rstrip("\r\n") for line in record]
                        validate_record(record, source, record_number)
                        header, sequence, separator, quality = record
                        output_file.write(header + "\n")
                        output_file.write(random_sequence(len(sequence), randomizer) + "\n")
                        output_file.write(separator + "\n")
                        output_file.write(quality + "\n")
    return max_reads


def make_temporary_path(destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
    )
    os.close(file_descriptor)
    return Path(temporary_name)


def main(argv=None):
    args = parse_args(argv)
    try:
        fastqs = find_fastqs(args.inputs)
    except ValueError as error:
        raise SystemExit(f"error: {error}") from error
    if not fastqs:
        raise SystemExit("error: no .fastq.gz files found")

    for source in fastqs:
        destination = source if args.in_place else output_path(source, args.inputs, args.output_dir)
        temporary_path = make_temporary_path(destination)
        try:
            read_count = anonymize_fastq(source, temporary_path, args.max_reads, args.seed)
            temporary_path.replace(destination)
        except (OSError, UnicodeError, ValueError) as error:
            temporary_path.unlink(missing_ok=True)
            raise SystemExit(f"error: {error}") from error
        print(f"{source} -> {destination}: retained {read_count} reads")


if __name__ == "__main__":
    main()
