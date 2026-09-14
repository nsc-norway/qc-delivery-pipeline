#!/bin/bash

set -euo pipefail

# Script to copy files to department-specific destination.
# Copies the fastq files, Demultiplexing metrics and SAV files (InterOp, RunInfo, RunParameters).
# The current implementation assumes that the directory layout is from an onboard analysis on the MiSeq i100,
# and doesn't support other layouts.

# usage: shared-resource-user-delivery.sh RUN_DIR ANALYSIS_DIR DESTINATION_DIR

# Read arguments into variables
RUN_DIR="$1"
ANALYSIS_DIR="$2"
DESTINATION_ROOT="$3"

# Require that all arguments are specified
if [[ -z "$RUN_DIR" || -z "$ANALYSIS_DIR" || -z "$DESTINATION_ROOT" ]]; then
    echo "Usage: $0 RUN_DIR ANALYSIS_DIR DESTINATION_ROOT"
    exit 1
fi

DESTINATION_DIR="$DESTINATION_ROOT/$(basename "$RUN_DIR")"
ANALYSIS_ID=$(basename "$ANALYSIS_DIR")

# Create destination run dir and InterOp dir if they don't already exist
mkdir -p "$DESTINATION_DIR"/InterOp
# Create analysis-level fastq destination. This should not be reused, but due to how the destination
# filsluse operates, it will be removed even if it's already transferred, so we just go ahead anyway.
mkdir -p "$DESTINATION_DIR"/Analysis_"$ANALYSIS_ID/fastq"

FASTQ_DESTINATION_DIR="$DESTINATION_DIR/Analysis_${ANALYSIS_ID}/fastq"
MD5SUM_FILE="$FASTQ_DESTINATION_DIR/md5sum.txt"
: > "$MD5SUM_FILE"

for fastq_file in "$ANALYSIS_DIR"/Data/BCLConvert/fastq/*.fastq.gz; do
    fastq_filename=$(basename "$fastq_file")
    if [[ "$fastq_filename" =~ ^(.+)_[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}(_S[0-9]+_L[0-9]+_R[12]_[0-9]+\.fastq\.gz)$ ]]; then
        fastq_filename="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    fi

    destination_fastq="$FASTQ_DESTINATION_DIR/$fastq_filename"
    checksum=$(md5sum "$fastq_file")
    printf '%s  %s\n' "${checksum%% *}" "$destination_fastq" >> "$MD5SUM_FILE"
    cp "$fastq_file" "$destination_fastq"
done

cp -r "$ANALYSIS_DIR/Data/BCLConvert/fastq/Reports" "$DESTINATION_DIR/Analysis_${ANALYSIS_ID}/"
cp -r "$ANALYSIS_DIR/Data/Demux" "$DESTINATION_DIR/Analysis_${ANALYSIS_ID}/"
cp "$RUN_DIR/"{RunInfo.xml,RunParameters.xml} "$DESTINATION_DIR"
cp "$RUN_DIR/InterOp/"*.bin "$DESTINATION_DIR/InterOp/"
