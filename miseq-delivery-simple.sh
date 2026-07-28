#!/bin/bash

ROOT=/boston/runScratch
MIK_PATH=/boston-pre/runScratch/OUS-filsluse/UL-AMG-MiSeq/MIK/Til_Sentrallagring/pre
IMM_PATH=/boston-pre/runScratch/OUS-filsluse/UL-AMG-MiSeq/IMM/Til_Sentrallagring/pre

# Create a file with a timestamp for comparison, for 5 minute old files.
touch -d '-5 minutes' /tmp/miseq-run-copier.limit

for complete_xml in $ROOT/*/Alignment_1/*/CompletedJobInfo.xml
do
    if [ ! -f $complete_xml ]
    then
        break
    fi
    DEMUX_DIR=$( dirname "$complete_xml" )
    RUN_DIR=$( dirname $( dirname "$DEMUX_DIR" ))
    RUN_ID=$( basename "$RUN_DIR" )
    if [ -f "$RUN_DIR/NSC_MiSeq_Delivery_Flag.txt" ]
    then
        continue
    fi
    touch "$RUN_DIR/NSC_MiSeq_Delivery_Flag.txt"
    if [ "$complete_xml" -ot "/tmp/miseq-run-copier.limit" ]
    then
        # Find run owner - MIK or IMM
        if EXPNAME=$( grep -o '^Experiment Name,[0-9_-]*MIK-' $RUN_DIR/SampleSheet.csv )
        then
            DEST_ROOT="$MIK_PATH"
        elif EXPNAME=$( grep -o '^Experiment Name,[0-9_-]*OUSMIK-' $RUN_DIR/SampleSheet.csv )
        then
            DEST_ROOT="$MIK_PATH"
        elif EXPNAME=$( grep '^Experiment Name,[0-9_-]*TI-' $RUN_DIR/SampleSheet.csv )
        then
            DEST_ROOT="$IMM_PATH"
        else
            echo $RUN_ID is not MIK or IMM - skipping
        fi
        PROJECT=$( echo "${EXPNAME}" | grep -Eo '(TI|OUSMIK|MIK)-[_A-Za-z0-9-]+' )
        if [[ ! "$PROJECT" =~ ^[A-Za-z0-9-]+$ ]]
        then
            echo "ERROR: Run ${RUN_ID}: Skipping invalid project name ${PROJECT}."
            continue
        fi
        DATASET_NAME="${RUN_ID:0:13}.Project_${PROJECT}"
        DEST="$DEST_ROOT/$DATASET_NAME"
        mkdir -p $DEST/InterOp
        rsync -rD $RUN_DIR/InterOp/*.bin $DEST/InterOp/
        rsync -rD $RUN_DIR/{RunParameters.xml,RunInfo.xml,SampleSheet.csv} $DEST/
        rsync -rD --exclude="Undetermined_S0_L001_R*_001.fastq.gz" $DEMUX_DIR/Fastq/* $DEST/
    fi
done
