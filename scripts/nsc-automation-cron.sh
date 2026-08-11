#!/bin/bash

# Cron job for automatisk pipeline execution.

# The called script sapio-run-extractor.py requires environment variables to be set for the Sapio API. See script source for details.

if [ "$1" == "" ]; then
    echo "Usage: $0 RUN_FOLDER_ROOT"
    exit 1
fi

# List analysis folders
shopt -s nullglob
for analysis in "$1"/*/Analysis/*/
do
    run_folder=$(cd "$analysis/../.." && pwd)
    log_file="$analysis/nsc_automation_log.txt"
    if [ -f "$log_file" ]; then
        # Skip analysies that are already processed
        continue
    fi
    # Determine if demultiplexing is complete
    complete=false
    if [ -f "$analysis/CopyComplete.txt" ]; then
        complete=true
    elif [ -f "$analysis/Fastq/Logs/FastqComplete.txt" ]; then
        complete=true
    fi

    # Process completed run
    if [ "$complete" = true ]; then
        echo "Processing analysis" > "$log_file"
        if [ ! -f "$run_folder/NscSapioInfo.yaml" ]; then
            echo "Extracting run information from Sapio into NscSapioInfo.yaml..." >> "$log_file"
            python3 sapio-run-extractor.py \
                "$run_folder/RunInfo.xml" \
                --output-yaml-file "$run_folder/NscSapioInfo.yaml" >> "$log_file" 2>&1
            echo "" >> "$log_file"
        fi
        grep -q '^  department: MIK' "$run_folder/NscSapioInfo.yaml"
        IS_MIK=$?
        grep -q '^  department: IMM' "$run_folder/NscSapioInfo.yaml"
        IS_IMM=$?

        if [ $IS_MIK -eq 0 ]; then
            echo "Analysis is from MIK department" >> "$log_file"
            shared-resource-user-delivery.sh MIK "$analysis" >> "$log_file" 2>&1
        elif [ $IS_IMM -eq 0 ]; then
            echo "Analysis is from IMM department" >> "$log_file"
            shared-resource-user-delivery.sh IMM "$analysis" >> "$log_file" 2>&1
        else
            echo "Running the nextflow pipeline..." >> "$log_file"
            pipeline-runner.sh "$analysis" >> "$log_file" 2>&1
        fi
    fi
done
