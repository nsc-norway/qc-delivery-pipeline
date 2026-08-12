#!/usr/bin/env bats

setup() {
    repo_root=$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)
    cron_script="${repo_root}/scripts/nsc-automation-cron.sh"
    run_root="${BATS_TEST_TMPDIR}/runs"
    mock_bin="${BATS_TEST_TMPDIR}/bin"
    call_log="${BATS_TEST_TMPDIR}/calls.log"
    mik_delivery_root="${BATS_TEST_TMPDIR}/mik-delivery"
    imm_delivery_root="${BATS_TEST_TMPDIR}/imm-delivery"

    mkdir -p "$run_root" "$mock_bin" "$mik_delivery_root" "$imm_delivery_root"
    : > "$call_log"
    export CALL_LOG="$call_log"
    export MIK_DELIVERY_ROOT="$mik_delivery_root"
    export IMM_DELIVERY_ROOT="$imm_delivery_root"
    export PATH="${mock_bin}:${PATH}"

    create_command_mock pipeline-runner.sh
    create_command_mock shared-resource-user-delivery.sh
    create_sapio_mock
}

create_command_mock() {
    local command_name="$1"

    cat > "${mock_bin}/${command_name}" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${0##*/}" >> "$CALL_LOG"
for argument in "$@"; do
    printf '\t%s' "$argument" >> "$CALL_LOG"
done
printf '\n' >> "$CALL_LOG"
EOF
    chmod +x "${mock_bin}/${command_name}"
}

create_sapio_mock() {
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

@test "runs the pipeline runner for completed analyses and skips incomplete analyses" {
    copy_analysis=$(create_analysis "copy-run" "3" "copy")
    fastq_analysis=$(create_analysis "fastq-run" "c2" "fastq")
    incomplete_analysis=$(create_analysis "incomplete-run" "4" "none")

    run bash "$cron_script" "$run_root"

    [ "$status" -eq 0 ]
    expected_calls=$(printf 'pipeline-runner.sh\t%s\npipeline-runner.sh\t%s' "$copy_analysis" "$fastq_analysis")
    assert_calls_match "$expected_calls"
    [ ! -e "${incomplete_analysis}nsc_automation_log.txt" ]
}

@test "routes MIK and IMM analyses to the shared-resource delivery script" {
    mik_analysis=$(create_analysis "mik-run" "3" "copy" "MIK")
    imm_analysis=$(create_analysis "imm-run" "c1" "fastq" "IMM")

    run bash "$cron_script" "$run_root"

    [ "$status" -eq 0 ]
    expected_calls=$(printf 'shared-resource-user-delivery.sh\t%s\t%s\t%s\nshared-resource-user-delivery.sh\t%s\t%s\t%s' \
        "${run_root}/imm-run" "$imm_analysis" "$imm_delivery_root" \
        "${run_root}/mik-run" "$mik_analysis" "$mik_delivery_root")
    assert_calls_match "$expected_calls"
}

@test "mocks Sapio extraction when NscSapioInfo.yaml is missing" {
    analysis=$(create_analysis "missing-sapio-run" "3" "copy" "missing")
    run_dir="${run_root}/missing-sapio-run"

    run bash "$cron_script" "$run_root"

    [ "$status" -eq 0 ]
    [ -f "${run_dir}/NscSapioInfo.yaml" ]
    expected_calls=$(printf 'python3\tsapio-run-extractor.py\t%s\t--output-yaml-file\t%s\npipeline-runner.sh\t%s' "${run_dir}/RunInfo.xml" "${run_dir}/NscSapioInfo.yaml" "$analysis")
    assert_calls_match "$expected_calls"
}