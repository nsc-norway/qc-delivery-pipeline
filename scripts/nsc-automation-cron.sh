#!/bin/bash

# Cron job for automatisk pipeline execution.

# The script takes an environment file as its argument.

# Required environment variables for running this cron job:
# Sapio credentials
# MIK_DELIVERY_DIR
# IMM_DELIVERY_DIR
# NSC_DELIVERY_DIR
# NSC_DEMULTIPLEXED_DIR
# RUN_FOLDER_ROOT
# PASSWORD_TOOL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 ENV_FILE"
    exit 1
fi

# Export all environment variables so they can be used by subprocesses
set -a
source "$1"
set +a


if [ ! -d "$MIK_DELIVERY_DIR" ] || [ ! -d "$IMM_DELIVERY_DIR" ] || \
   [ ! -d "$NSC_DELIVERY_DIR" ] || [ ! -d "$NSC_DEMULTIPLEXED_DIR" ] || \
   [ ! -d "$RUN_FOLDER_ROOT" ]; then
    echo "Error: Delivery destinations and run folder root must be specified and exist:"
    echo "MIK_DELIVERY_DIR, IMM_DELIVERY_DIR, NSC_DELIVERY_DIR,"
    echo "NSC_DEMULTIPLEXED_DIR, RUN_FOLDER_ROOT"
    exit 1
fi

if [ ! -f "$PASSWORD_TOOL" ]; then
    echo "Error: PASSWORD_TOOL must be specified and exist."
    exit 1
fi

# List analysis folders
shopt -s nullglob
for analysis in "$RUN_FOLDER_ROOT"/*/Analysis/*/
do
    run_folder=$(cd "$analysis/../.." && pwd)
    log_file="$analysis/NSC/automation_log.txt"
    if [ -e "$analysis/NSC" ]; then
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
        mkdir "$analysis/NSC"
        echo "Processing analysis" > "$log_file"
        if [ ! -f "$run_folder/NscSapioInfo.yaml" ]; then
            echo "Extracting run information from Sapio into NscSapioInfo.yaml..." >> "$log_file"
            python3 "$SCRIPT_DIR/sapio-run-extractor.py" \
                "$run_folder/RunInfo.xml" \
                --output-yaml-file "$run_folder/NscSapioInfo.yaml" >> "$log_file" 2>&1
            echo "" >> "$log_file"
        fi
        grep -q '^  department: MIK' "$run_folder/NscSapioInfo.yaml"
        IS_MIK=$?
        grep -q '^  department: IMM' "$run_folder/NscSapioInfo.yaml"
        IS_IMM=$?
        grep -q '^  department: NSC' "$run_folder/NscSapioInfo.yaml"
        IS_NSC=$?

        if [ $IS_NSC -eq 0 ]; then
            echo "Running the nextflow pipeline..." >> "$log_file"
            "$SCRIPT_DIR/get-pipeline-command.sh" "$run_folder" "$analysis" > "$analysis/NSC/pipeline_command.sh" 2> "$log_file"
            sbatch "$analysis/NSC/pipeline_command.sh" >> "$log_file" 2>&1
        elif [ $IS_MIK -eq 0 ]; then
            echo "Analysis is from MIK department" >> "$log_file"
            "$SCRIPT_DIR/shared-resource-user-delivery.sh" "$run_folder" "$analysis" "$MIK_DELIVERY_DIR" >> "$log_file" 2>&1
        elif [ $IS_IMM -eq 0 ]; then
            echo "Analysis is from IMM department" >> "$log_file"
            "$SCRIPT_DIR/shared-resource-user-delivery.sh" "$run_folder" "$analysis" "$IMM_DELIVERY_DIR" >> "$log_file" 2>&1
        fi
    fi
done
