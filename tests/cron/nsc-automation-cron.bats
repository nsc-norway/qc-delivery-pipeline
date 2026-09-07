#!/usr/bin/env bats

setup() {
    repo_root=$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)
    script_dir="${BATS_TEST_TMPDIR}/scripts"
    cron_script="${script_dir}/nsc-automation-cron.sh"
    run_root="${BATS_TEST_TMPDIR}/runs"
    mock_bin="${BATS_TEST_TMPDIR}/bin"
    call_log="${BATS_TEST_TMPDIR}/calls.log"
    mik_delivery_root="${BATS_TEST_TMPDIR}/mik-delivery"
    imm_delivery_root="${BATS_TEST_TMPDIR}/imm-delivery"
    nsc_delivery_root="${BATS_TEST_TMPDIR}/nsc-delivery"
    nsc_demultiplexed_root="${BATS_TEST_TMPDIR}/nsc-demultiplexed"
    environment_file="${BATS_TEST_TMPDIR}/environment"

    mkdir -p "$script_dir" "$run_root" "$mock_bin" "$mik_delivery_root" "$imm_delivery_root" \
        "$nsc_delivery_root" "$nsc_demultiplexed_root"
    cp "${repo_root}/scripts/nsc-automation-cron.sh" "$cron_script"
    chmod +x "$cron_script"
    cat > "$environment_file" <<EOF
MIK_DELIVERY_DIR=${mik_delivery_root}
IMM_DELIVERY_DIR=${imm_delivery_root}
NSC_DELIVERY_DIR=${nsc_delivery_root}
NSC_DEMULTIPLEXED_DIR=${nsc_demultiplexed_root}
RUN_FOLDER_ROOT=${run_root}
EOF
    : > "$call_log"
    export CALL_LOG="$call_log"
    export MIK_DELIVERY_ROOT="$mik_delivery_root"
    export IMM_DELIVERY_ROOT="$imm_delivery_root"
    export PATH="${mock_bin}:${script_dir}:${PATH}"

    create_command_mock "${script_dir}/get-pipeline-command.sh"
    create_command_mock "${script_dir}/shared-resource-user-delivery.sh"
    create_sapio_mock
}

create_command_mock() {
    local command_path="$1"

    cat > "$command_path" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${0##*/}" >> "$CALL_LOG"
for argument in "$@"; do
    printf '\t%s' "$argument" >> "$CALL_LOG"
done
printf '\n' >> "$CALL_LOG"
EOF
    chmod +x "$command_path"
}

create_sapio_mock() {
    touch "${script_dir}/sapio-run-extractor.py"
    cat > "${mock_bin}/python3" <<'EOF'
#!/usr/bin/env bash
arguments=("$@")
output_file=""

while (($#)); do
    case "$1" in
        --output-yaml-file)
            output_file="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

printf '%s' "${0##*/}" >> "$CALL_LOG"
for argument in "${arguments[@]}"; do
    printf '\t%s' "$argument" >> "$CALL_LOG"
done
printf '\n' >> "$CALL_LOG"

cat > "$output_file" <<'YAML'
projects:
- record_id: 1
  department: NSC
YAML
EOF
    chmod +x "${mock_bin}/python3"
}

create_analysis() {
    local run_name="$1"
    local analysis_name="$2"
    local completion_marker="$3"
    local department="${4:-NSC}"
    local run_dir="${run_root}/${run_name}"
    local analysis_dir="${run_dir}/Analysis/${analysis_name}"

    mkdir -p "$analysis_dir"
    case "$completion_marker" in
        copy)
            touch "${analysis_dir}/CopyComplete.txt"
            ;;
        fastq)
            mkdir -p "${analysis_dir}/Fastq/Logs"
            touch "${analysis_dir}/Fastq/Logs/FastqComplete.txt"
            ;;
    esac

    if [[ "$department" != "missing" ]]; then
        cat > "${run_dir}/NscSapioInfo.yaml" <<EOF
projects:
- record_id: 1
  department: ${department}
EOF
    else
        touch "${run_dir}/RunInfo.xml"
    fi

    printf '%s/\n' "$analysis_dir"
}

assert_calls_match() {
    local expected_calls="$1"
    local actual_calls
    actual_calls=$(cat "$call_log")

    if [[ "$actual_calls" != "$expected_calls" ]]; then
        printf 'Expected calls:\n%s\nActual calls:\n%s\n' "$expected_calls" "$actual_calls" >&2
        return 1
    fi
}

@test "generates and runs the pipeline command for completed analyses and skips incomplete analyses" {
    copy_analysis=$(create_analysis "copy-run" "3" "copy")
    fastq_analysis=$(create_analysis "fastq-run" "c2" "fastq")
    incomplete_analysis=$(create_analysis "incomplete-run" "4" "none")

    run nsc-automation-cron.sh "$environment_file"

    [ "$status" -eq 0 ]
    expected_calls=$(printf 'get-pipeline-command.sh\t%s\t%s\nget-pipeline-command.sh\t%s\t%s' \
        "${run_root}/copy-run" "$copy_analysis" \
        "${run_root}/fastq-run" "$fastq_analysis")
    assert_calls_match "$expected_calls"
    [ ! -e "${incomplete_analysis}nsc_automation_log.txt" ]
}

@test "routes MIK and IMM analyses to the shared-resource delivery script" {
    mik_analysis=$(create_analysis "mik-run" "3" "copy" "MIK")
    imm_analysis=$(create_analysis "imm-run" "c1" "fastq" "IMM")

    run nsc-automation-cron.sh "$environment_file"

    [ "$status" -eq 0 ]
    expected_calls=$(printf 'shared-resource-user-delivery.sh\t%s\t%s\t%s\nshared-resource-user-delivery.sh\t%s\t%s\t%s' \
        "${run_root}/imm-run" "$imm_analysis" "$imm_delivery_root" \
        "${run_root}/mik-run" "$mik_analysis" "$mik_delivery_root")
    assert_calls_match "$expected_calls"
}

@test "mocks Sapio extraction when NscSapioInfo.yaml is missing" {
    analysis=$(create_analysis "missing-sapio-run" "3" "copy" "missing")
    run_dir="${run_root}/missing-sapio-run"

    run nsc-automation-cron.sh "$environment_file"

    [ "$status" -eq 0 ]
    [ -f "${run_dir}/NscSapioInfo.yaml" ]
    expected_calls=$(printf 'python3\t%s\t%s\t--output-yaml-file\t%s\nget-pipeline-command.sh\t%s\t%s' \
        "${script_dir}/sapio-run-extractor.py" "${run_dir}/RunInfo.xml" \
        "${run_dir}/NscSapioInfo.yaml" "$run_dir" "$analysis")
    assert_calls_match "$expected_calls"
}

@test "generates a pipeline command with an absolute pipeline path" {
    analysis=$(create_analysis "pipeline-path-run" "3" "copy")

    cd "$BATS_TEST_TMPDIR"
    run "${repo_root}/scripts/get-pipeline-command.sh" "${run_root}/pipeline-path-run" "$analysis"

    [ "$status" -eq 0 ]
    [[ "$output" == "nextflow run ${repo_root}/nsc-nextflow/main.nf "* ]]
}

@test "delivers IMM or MIK FASTQs without Sample_ID UUID suffixes" {
    delivery_script="${repo_root}/scripts/shared-resource-user-delivery.sh"
    delivery_run_dir="${BATS_TEST_TMPDIR}/delivery-run"
    delivery_analysis_dir="${delivery_run_dir}/Analysis/42"
    source_fastq_dir="${delivery_analysis_dir}/Data/BCLConvert/fastq"
    delivery_root="${BATS_TEST_TMPDIR}/delivered"

    mkdir -p "${source_fastq_dir}/Reports" "${delivery_analysis_dir}/Data/Demux" "${delivery_run_dir}/InterOp"
    touch "${source_fastq_dir}/Reports/SampleSheet.csv" "${delivery_analysis_dir}/Data/Demux/metrics.csv"
    touch "${delivery_run_dir}/RunInfo.xml" "${delivery_run_dir}/RunParameters.xml" "${delivery_run_dir}/InterOp/metrics.bin"
    printf 'R1 data\n' > "${source_fastq_dir}/26-1094-1D_fa8781b0-ff92-4c21-afa9-20d7ae946df8_S3_L001_R1_001.fastq.gz"
    printf 'R2 data\n' > "${source_fastq_dir}/26-1094-1D_fa8781b0-ff92-4c21-afa9-20d7ae946df8_S3_L002_R2_001.fastq.gz"
    printf 'plain data\n' > "${source_fastq_dir}/sample-without-uuid_S4_L001_R1_001.fastq.gz"

    run bash "$delivery_script" "$delivery_run_dir" "$delivery_analysis_dir" "$delivery_root"

    [ "$status" -eq 0 ]
    delivered_fastq_dir="${delivery_root}/delivery-run/Analysis_42/fastq"
    [ -f "${delivered_fastq_dir}/26-1094-1D_S3_L001_R1_001.fastq.gz" ]
    [ -f "${delivered_fastq_dir}/26-1094-1D_S3_L002_R2_001.fastq.gz" ]
    [ -f "${delivered_fastq_dir}/sample-without-uuid_S4_L001_R1_001.fastq.gz" ]
    [ ! -e "${delivered_fastq_dir}/26-1094-1D_fa8781b0-ff92-4c21-afa9-20d7ae946df8_S3_L001_R1_001.fastq.gz" ]
    run grep -q 'fa8781b0-ff92-4c21-afa9-20d7ae946df8' "${delivered_fastq_dir}/md5sum.txt"
    [ "$status" -eq 1 ]
    run md5sum --check "${delivered_fastq_dir}/md5sum.txt"
    [ "$status" -eq 0 ]
}
