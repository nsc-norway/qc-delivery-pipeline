
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

echo '#!/bin/bash'
echo "#SBATCH --job-name=NSC${run_id}"
echo '#SBATCH --output='"$ANALYSIS_DIR"'/NSC/pipeline_output.log'
echo '#SBATCH --time=3-0'
echo '#SBATCH --cpus-per-task=2'
echo '#SBATCH --mem=8G'
echo '#SBATCH --qos=high'

echo 'cd "'"$ANALYSIS_DIR"'/NSC"'

echo $NEXTFLOW run "$PIPELINE_PATH" \
  -profile "$NEXTFLOW_PROFILE" \
  --runFolder "$RUN_FOLDER" \
  --analysisDir "$ANALYSIS_DIR" \
  --outdir "$NSC_DEMULTIPLEXED_DIR" \
  --deliveryDir "$NSC_DELIVERY_DIR" \
  --passwordTool "$PASSWORD_TOOL" \
  -resume
