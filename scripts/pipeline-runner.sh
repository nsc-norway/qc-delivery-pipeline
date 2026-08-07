
#!/bin/bash

ANALYSIS_DIR="$1"

if [ "$ANALYSIS_DIR" == "" ]; then
    echo "Usage: $0 ANALYSIS_DIR"
    exit 1
fi

nextflow run ../nsc-nextflow/main.nf \
  --runFolder "$ANALYSIS_DIR/../.." \
  --bclConvertFastqDir "$ANALYSIS_DIR/" \
  -resume

