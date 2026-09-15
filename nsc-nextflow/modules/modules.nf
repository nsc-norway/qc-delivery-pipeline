
process MD5SUM_FASTQ {
    tag "$meta.sample_id"
    container "ghcr.io/nsc-norway/qc-delivery-pipeline-tools:1.0.0"

    input:
    tuple val(meta), path(fastq)

    output:
    tuple val(meta), path("${fastq}.md5"), emit: MD5SUM_FASTQ_out

    script:
    """
    md5sum $fastq > ${fastq}.md5
    """
}

process CAT_MD5SUM {
    tag "$meta.project_name"
    container "ghcr.io/nsc-norway/qc-delivery-pipeline-tools:1.0.0"
    publishDir { "${params.outdir}/${meta.run_id}/${meta.project_dir_name}" }, mode:'link', overwrite: true

    input:
    tuple val(meta), path(fastq_md5)

    output:
    tuple val(meta), path("md5sum.txt"), emit: CAT_MD5SUM_out

    script:
    """
    cat *.md5 > md5sum.txt
    """
}

process SUPRDUPR {
    tag "$meta.sample_id"
    container "ghcr.io/nsc-norway/suprdupr:v1.4.1"
    publishDir { "${params.outdir}/${meta.run_id}/QualityControl_${meta.analysis_id}/${meta.project_name}/suprdupr" }, mode:'link',  overwrite: true

    input:
    tuple val(meta), path(fastq)

    output:
    path "${meta.sample_id}_L00${meta.lane}.suprDUPr.txt"

    script:
    """
    suprDUPr -r $fastq > ${meta.sample_id}_L00${meta.lane}.suprDUPr.txt
    """
}

process FASTQC {
    tag "$meta.sample_id"
    container "biocontainers/fastqc:v0.11.9_cv8"
    publishDir { "${params.outdir}/${meta.run_id}/QualityControl_${meta.analysis_id}/${meta.project_name}/fastqc" }, mode:'link',  overwrite: true

    input:
    tuple val(meta), path(fastq)
    
    output:
    tuple val(meta), path("${fastq.getSimpleName()}_fastqc.zip"),  emit: FASTQC_ZIP_out
    tuple val(meta), path("${fastq.getSimpleName()}_fastqc.html"), emit: FASTQC_HTML_out

    script:
    """
    fastqc ${fastq}
    """
}

process MULTIQC {
    tag "$meta.project_name"
    container "multiqc/multiqc:v1.35"
    publishDir { "${params.outdir}/${meta.run_id}/${meta.project_dir_name}" }, mode:'link',  overwrite: true

    input:
    tuple val(meta), path(multiqc_inputs)
    val multiqc_module
    
    output:
    tuple val(meta), path("multiqc_report.html"), emit: MULTIQC_out

    script:
    """
    multiqc --module $multiqc_module .
    """
}


process PROJECT_CREDENTIALS {
    tag "$meta.project_name"
    container "ghcr.io/nsc-norway/qc-delivery-pipeline-tools:1.0.0"

    input:
    val meta

    output:
    tuple val(meta), eval('cat username.txt'), path('password.txt'),  emit: PROJECT_CREDENTIALS_out

    script:
    //def username = meta.project_name.matches(/^(.*)-\d{4}-\d{2}-\d{2}.*/) ? meta.project_name.replaceFirst(/^(.*)-\d{4}-\d{2}-\d{2}.*/, '$1').toLowerCase() : ''
    """
    echo "${meta.project_name}" | sed -n 's/^\\(.*\\)-[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}/\\1/p' | tr '[:upper:]' '[:lower:]' > username.txt
    "${params.passwordTool}" "${meta.project_dir_name}" \$( cat username.txt ) > password.txt
    """
}

process PUBLISH_REPORTS {
    tag "${run_id}/${analysis_id}"
    publishDir { "${params.outdir}/${run_id}/QualityControl_${analysis_id}" }, mode: 'copy', overwrite: true, saveAs: { filename -> filename.tokenize('/').last() }

    input:
    val(run_id)
    val(analysis_id)
    path("Demux/*")
    
    output:
    path "Demux"

    script:
    """
    """
}


process PUBLISH_SAV_FILES {
    publishDir { "${params.outdir}/${run_id}" }, mode: 'link', overwrite: true

    input:
    val run_id
    path run
    
    output:
    path "{RunInfo.xml,RunParameters.xml,InterOp}"

    script:
    """
    mkdir SAV_FILES
    cp -rl $run/RunInfo.xml $run/RunParameters.xml $run/InterOp .
    """
}


process TAR_FOLDER {
    tag "${meta.project_name}"
    container "ghcr.io/nsc-norway/qc-delivery-pipeline-tools:1.0.0"
    publishDir "${params.deliveryDir}", mode:'link',  overwrite: true

    input:
    tuple val(meta), path("tar/${meta.project_dir_name}/*"), val(username), path(password_file)

    output:
    tuple val(meta), path("${meta.project_dir_name}"), emit: TAR_FOLDER_out

    script:
    def delivery_dir = meta.project_dir_name
    """
    # Create the tar file
    (cd tar && tar -hcf "${delivery_dir}.tar" "${delivery_dir}" )

    # Create delivery directory
    mkdir "${delivery_dir}"

    # Move the tar file to the delivery directory
    mv "tar/${delivery_dir}.tar" "${delivery_dir}/"

    # Compute md5sum for the tar file
    (cd "${delivery_dir}" && md5sum "${delivery_dir}.tar" > "${delivery_dir}.tar.md5" )

    # Create .htaccess
cat <<EOL > "${delivery_dir}/.htaccess"
AuthUserFile /data/${delivery_dir}/.htpasswd
AuthGroupFile /dev/null
AuthName ByPassword
AuthType Basic

<Limit GET>
require user $username
</Limit>
EOL

    # Create .htpasswd with content: username:hashed_password
    echo -n "${username}:" > "${delivery_dir}/.htpasswd"
    openssl passwd -apr1 -in "$password_file" >> "${delivery_dir}/.htpasswd"
    """
}

process LINK_FOLDER {
    tag "${meta.project_name}"
    container "ghcr.io/nsc-norway/qc-delivery-pipeline-tools:1.0.0"
    publishDir { "${params.deliveryDir}" }, mode:'link', overwrite: true

    input:
    tuple val(meta), path("${meta.project_dir_name}/*")

    output:
    path "${meta.project_dir_name}"

    script:
    """
    """
}


process EMAIL_PROJECT {
    tag "${meta.project_name}"
    container "ghcr.io/nsc-norway/qc-delivery-email-scripts:1.0.0"
    publishDir { "${params.outdir}/${runFolder.name}/QualityControl_${analysisId}" }, mode:'link',  overwrite: true

    input:
    tuple val(meta), val(username), path('password.txt')
    path runFolder
    val analysisId
    path "Demultiplex_Stats.csv"
    path sapioRunFile
    val bclConvertVersion
    val pipelineVersion

    output:
    path "Delivery/*", emit: EMAIL_PROJECT_out

    script:
    def sapioRunFileOptional = sapioRunFile.exists() ? "${sapioRunFile}" : ""
    """
    make-emails.py \
            --run-dir=$runFolder \
            --demultiplex-stats=Demultiplex_Stats.csv \
            --bclconvert-version='${bclConvertVersion}' \
            --pipeline-version='${pipelineVersion}' \
            --output-email-dir=Delivery \
            --create-project-email-for="${meta.project_name}" \
            --nird-username="$username" \
            --nird-password-file=password.txt $sapioRunFileOptional
    """
}

process EMAIL_SUMMARY_RUN {
    tag "${runFolder.name}"
    container "ghcr.io/nsc-norway/qc-delivery-email-scripts:1.0.0"
    publishDir { "${params.outdir}/${runFolder.name}/QualityControl_${analysisId}" }, mode:'link', overwrite: true

    input:
    path runFolder
    val analysisId
    path "Demultiplex_Stats.csv"
    path "suprDUPr/*"
    path sapioRunFile
    val bclConvertVersion
    val pipelineVersion

    output:
    path "Delivery/*", emit: EMAIL_SUMMARY_RUN_out

    script:
    def sapioRunFileOptional = sapioRunFile.exists() ? "${sapioRunFile}" : ""
    """
    make-emails.py \
            --run-dir=${runFolder} \
            --demultiplex-stats=Demultiplex_Stats.csv \
            --suprdupr-dir=suprDUPr \
            --bclconvert-version='${bclConvertVersion}' \
            --pipeline-version='${pipelineVersion}' \
            --output-email-dir=Delivery \
            --create-summary \
            $sapioRunFileOptional
    """
}

process DECOMPRESS_ORA {
    tag "$meta.sample_id"
    
    publishDir { "${params.outdir}/${meta.run_id}/${meta.project_dir_name}" }, mode:'link', overwrite: true

    cpus 8
    memory 32.GB

    input:
    tuple val(meta), path(fastq_ora)

    output:
    tuple val(meta), path("${fastq_ora.name[0..-5]}.gz"), emit: DECOMPRESS_ORA_out

    script:
    """
    /data/common/tools/orad/orad.2.7.0.linux/orad \
        -q -t $task.cpus \
        --ora-reference /data/common/tools/orad/orad.2.7.0.linux/oradata \
        --path . \
        $fastq_ora
    """
}

/**
 * Get a simple fastq name, replacing the the Sample_ID file name.
 * Removes project name and GUID if they were present.
 */
def getNewFastqName(originalFastq, sampleId, sampleName) {
    if (originalFastq.startsWith(sampleId + "_S")) {
        return sampleName + originalFastq.substring(sampleId.length())
    }
    return originalFastq
}

process RENAME_AND_SAVE_FASTQS {
    tag "$meta.sample_id"
    container "ghcr.io/nsc-norway/qc-delivery-pipeline-tools:1.0.0"
    publishDir { "${params.outdir}/${meta.run_id}/${meta.project_dir_name}" }, mode:'link', overwrite: true

    input:
    tuple val(meta), path(fastq)

    output:
    tuple val(meta), path(newName), emit: RENAME_AND_SAVE_FASTQS_out

    script:
    newName = getNewFastqName(fastq.getName(), meta.sample_id, meta.sample_name)
    """
    mv "$fastq" "fastq_tmp"
    cp -l "fastq_tmp" "$newName"
    """
}

/*
process MAKE_SENSITIVE_DATA_LOG_FILE {
    publishDir "$runfolder", mode: 'link'
    container "ghcr.io/nsc-norway/qc-delivery-email-scripts:1.0.0"
    
    input:
    val project_dir_name
    path json
    val runfolder

    output:
    path "${project_dir_name}.sensitive.tsv", emit: tsv, optional: true

    script:
    """
    make-sensitive-data-tsv.py $project_dir_name $json ${project_dir_name}.sensitive.tsv
    """
}
*/

process GET_BCL_CONVERT_VERSION {
    
    cpus 1
    memory 1.GB

    input:
    path("Info.log")

    output:
    eval 'cat bclconvert_version.txt', emit: GET_BCL_CONVERT_VERSION_out

    script:
    // Match: 2026-07-29T09:25:04Z thread 969464 bcl-convert Version 4.3.6
    // and if not, match: 2026-07-29T09:25:04Z thread 969464   SoftwareVersion = 4.4.12
    """
    version=\$(sed -nE 's/.*bcl-convert Version[[:space:]]+([0-9]+(\\.[0-9]+)+).*/\\1/p' Info.log | head -n 1)
    if [ -z "\$version" ]; then
        version=\$(sed -nE 's/.*SoftwareVersion[[:space:]]*=[[:space:]]*([0-9]+(\\.[0-9]+)+).*/\\1/p' Info.log | head -n 1)
    fi
    printf '%s\n' "\${version:-UNKNOWN}" > bclconvert_version.txt
    """
}
