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
mkdir -p "$DESTINATION_DIR"/SAV/InterOp
# Create analysis-level fastq destination. This should not be reused, but due to how the destination
# filsluse operates, it will be removed even if it's already transferred, so we just go ahead anyway.
mkdir -p "$DESTINATION_DIR"/Analysis_"$ANALYSIS_ID/fastq"

# Create md5sum in memory, to keep the copying operations fast
MD5SUM_DATA=$( md5sum "$ANALYSIS_DIR"/Data/BCLConvert/fastq/*.fastq.gz )

echo "$MD5SUM_DATA" > "$DESTINATION_DIR/Analysis_${ANALYSIS_ID}/fastq/md5sum.txt"
cp -r "$ANALYSIS_DIR/Data/BCLConvert/fastq/"*.fastq.gz "$DESTINATION_DIR/Analysis_${ANALYSIS_ID}/fastq/"
cp -r "$ANALYSIS_DIR/Data/BCLConvert/fastq/Reports" "$DESTINATION_DIR/Analysis_${ANALYSIS_ID}/"
cp -r "$ANALYSIS_DIR/Data/Demux" "$DESTINATION_DIR/Analysis_${ANALYSIS_ID}/"
cp -r "$RUN_DIR/"{RunInfo.xml,RunParameters.xml} "$DESTINATION_DIR/SAV"
cp -r "$RUN_DIR/InterOp/"*.bin "$DESTINATION_DIR/SAV/InterOp/"
