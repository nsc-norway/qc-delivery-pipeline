#!/bin/bash

set -eu

RUN="$1"

if [ -z "$RUN" ]
then
    echo "usage: script.sh RUN_FOLDER"
    exit 1
fi

# Reformat sample sheet
# Split Sample_ID into Sample_Project column, core Sample_ID and strip the UUID.
# Create expected file name for demux-runner
RUN_PATH=$( readlink -f $RUN )
RUN_ID=$( basename $RUN_PATH )

awk -F, '
BEGIN { OFS="," }

# Enter BCLConvert_Data section
/^\[BCLConvert_Data\]$/ {
    in_data=1
    print
    next
}

# Stop at the next section
in_data && /^\[/ { exit }

# Preserve everything before BCLConvert_Data
!in_data { print; next }

# Skip empty lines
/^[[:space:]]*$/ { next }

# Update column header
$2 == "Sample_ID" {
    $2 = "Sample_ID" OFS "Sample_Project"
    print
    next
}

# Split Sample_ID into exactly three parts
{
    split($2, parts, "_")
    $2 = parts[2] OFS parts[1]
    print
}
' "$RUN/SampleSheet.csv" > "$RUN/${RUN_ID:0:4}-${RUN_ID:4:2}-${RUN_ID:6:2}_SampleSheet_NSC_AllLanes.csv"



SIF=/boston-common/tools/sapio-sequencingfiles/sapio-sequencingfiles-1.0.0.sif

# Create job file. Interactive demux-runner wizard.
JOB_FILE=$( singularity exec -B /boston/nsc $SIF \
        demux-runner \
            init-job \
            --defaults-json /boston/nsc/scripts/qc-delivery-pipeline/redemultiplexing/demux-runner-defaults-ullevaal.json \
            "$RUN" | jq -r '.job_file' )

# Run the submit command. At the moment, the submission is not actually working.
# We just want to generate the analysis directory, script and sample sheet. Then the
# submission is done manually after the sample sheet has been edited by the user.
if [ ! -z "$JOB_FILE" ]
then
    echo "Creating analysis directory..."
    echo ""
    echo "1. Edit sample sheet in directory of SLURM script if necessary."
    echo "2. Submit from RUN FOLDER:"
    
    SCRIPT_PATH=$( singularity exec -B /boston/nsc $SIF \
        demux-runner \
            submit \
            $JOB_FILE | awk '/Wrote SLURM script/ {print $NF;}')
    echo "   cd $RUN_PATH && sbatch $( realpath -s --relative-to=$RUN_PATH $SCRIPT_PATH )"
fi
