
#!/bin/bash

RUN_FOLDER="$1"
ANALYSIS_DIR="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_PATH="$(cd "$SCRIPT_DIR/../nsc-nextflow" && pwd)/main.nf"

if [ "$RUN_FOLDER" == "" ] || [ "$ANALYSIS_DIR" == "" ]; then
    echo "Usage: $0 RUN_FOLDER ANALYSIS_DIR" >&2
    exit 1
fi

run_id=$(basename "$RUN_FOLDER")

echo nextflow run "$PIPELINE_PATH" \
  --runFolder "$RUN_FOLDER" \
  --analysisDir "$ANALYSIS_DIR" \
  --outdir "$NSC_DEMULTIPLEXED_DIR/$run_id" \
  --deliveryDir "$NSC_DELIVERY_DIR" \
  -resume

