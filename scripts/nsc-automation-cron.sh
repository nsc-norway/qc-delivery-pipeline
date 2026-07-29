#!/bin/bash

# Cron job for automatisk pipeline execution.

# The called script sapio-run-extractor.py requires environment variables to be set for the Sapio API. See script source for details.

if [ "$1" == "" ]; then
    echo "Usage: $0 RUN_FOLDER_ROOT"
    exit 1
fi

# List analysis folders
for analysis in "*/Analysis/*/"
do
    log_file="$analysis/nsc_automation_log.txt"
    if [ -f "$log_file" ]; then
        # Skip analysies that are already processed
        continue
    fi
    # Determine if demultiplexing is complete
    complete=false
    if [ -f "$analysis/CopyComplete.txt" ]; then
        complete=true
    elif [ -f "$analysis/FastqComplete.txt" ]; then
        # TODO confirm off-board analysis completion file path
        complete=true
    fi

    # Process completed run
    if [ "$complete" = true ]; then
        echo "Processing analysis" > "$log_file"
        if [ ! -f "$analysis/../../NscSapioInfo.yaml" ]; then
            echo "Extracting run information from Sapio into NscSapioInfo.yaml..." >> "$log_file"
            python3 sapio-run-extractor.py \
                "$analysis/../../RunInfo.xml" \
                --output-yaml-file "$analysis/../../NscSapioInfo.yaml" >> "$log_file" 2>&1
            echo "" >> "$log_file"
        fi
        echo "Running the nextflow pipeline..." >> "$log_file"
        pipeline-runner.sh "$analysis/../../NscSapioInfo.yaml" "$analysis" >> "$log_file" 2>&1
    fi
done
