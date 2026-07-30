
process MD5SUM_FASTQ {
    tag "$meta.sample_id"

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
    publishDir { "${params.outdir}/${meta.project_dir_name}" }, mode:'link', overwrite: true

    input:
    tuple val(meta), path(fastq_md5)

    output:
    path "md5sum.txt"

    script:
    """
    cat *.md5 > md5sum.txt
    """
}

process SUPRDUPR {
    tag "$meta.sample_id"

    container "ghcr.io/nsc-norway/suprdupr:v1.4.1"
    publishDir { "${params.outdir}/QualityControl/${meta.project_name}/suprdupr" }, mode:'link',  overwrite: true

    input:
    tuple val(meta), path(fastq)

    output:
    path "${meta.sample_id}.suprDUPr.txt"

    script:
    """
    suprDUPr -r $fastq > ${meta.sample_id}.suprDUPr.txt
    """
}

process FASTQC {
    tag "$meta.sample_id"

    container "biocontainers/fastqc:v0.11.9_cv8"
    publishDir { "${params.outdir}/QualityControl/${meta.project_name}/fastqc" }, mode:'link',  overwrite: true

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

    publishDir { "${params.outdir}/${meta.project_dir_name}" }, mode:'link',  overwrite: true

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

/*
process PROJECT_CREDENTIALS {
    tag "$project_name"

    input:
    val project_name
    val data_project_folder
    val password_tool

    output:
    path "credentials.json", emit: credentials_json
    path "username.txt", emit: username_txt
    path "htpasswd", emit: htpasswd

    script:
    """
    username=\$(echo "$project_name" | sed -n 's/^\\(.*\\)-[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}/\\1/p' | tr '[:upper:]' '[:lower:]')
    password=\$("$password_tool" "$data_project_folder" "\$username")

    printf '%s\\n' "\$username" > username.txt
    hashed_password=\$(openssl passwd -apr1 "\$password")
    printf '%s:%s\\n' "\$username" "\$hashed_password" > htpasswd

    cat > credentials.json <<EOF
        {"NIRD password": "\$password", "NIRD username": "\$username"}
EOF
    """
}

process TAR_FOLDER {
    tag "$project_dir_name"
//    publishDir "$runfolder" + "$NSC_ProjectName", mode:'link',  overwrite: true

    input:
    val project_dir_name
    val runfolder
    val deliverydir
    path username_txt
    path htpasswd
    path MULTIQC_out
    path MD5SUM_FASTQ_out

    output:
    val "tar_complete", emit: TAR_FOLDER_out

    script:
    """
    tar.sh "$runfolder" "$project_dir_name" "$deliverydir" "$username_txt" "$htpasswd"
    """
}

process LINK_FOLDER {
    tag "$project_dir_name"
    publishDir "$params.deliverydir", mode:'move',  overwrite: true

    input:
    val project_dir_name
    path samples
    path MULTIQC_out
    path MD5SUM_FASTQ_out

    output:
    path "$project_dir_name"

    script:
    """
    mkdir $project_dir_name
    # Hard link all files to work folder (follows symbolic links)
    cp -l $samples             $project_dir_name
    cp -l  $MULTIQC_out        $project_dir_name
    cp -l $MD5SUM_FASTQ_out    $project_dir_name
    # Note: mode "move" is used in publishDir, we shouldn't leave big files in work
    """
}

process JSON_GENERATOR {
    tag "$project_name"
    publishDir "$qcfolder/lims" , mode:'link',  overwrite: true
    container "$params.containerdir/lims-environment.sif"
    containerOptions "-B /data/runScratch.boston/scripts/etc/seq-user/apiuser-password.txt:/etc/apiuser-pw.txt"

    input:
    val project_name
    val qcfolder
   
    output:
    path "${project_name}.lims.json", emit: JSON_GENERATOR_out

    script:
    """
    get-project-info.py $project_name > ${project_name}.lims.json
    """
}

process EMAIL_PROJECT {
    tag "$project_name"
    //publishDir "$qcfolder" + "lims" , mode:'link',  overwrite: true
    container "ghcr.io/nsc-norway/qc-delivery-email-scripts:1.0.0"

    input:
    val project_name
    path runfolder
    path qcfolder
    path project_lims_json
    path credentials_json

    output:
    val "email_project_complete", emit: EMAIL_PROJECT_out

    script:
    """
    jq -s add "$project_lims_json" "$credentials_json" > project.json

    make-emails.py \
            --run-dir=$runfolder \
            --demultiplex-stats=$qcfolder/Demux/Demultiplex_Stats.csv \
            --bclconvert-version=$params.bcl_convert_version \
            --pipeline-version=$params.pipeline_version \
            --output-email-dir=$qcfolder/Delivery \
            --create-project-emails \
            project.json
    """
}

process EMAIL_SUMMARY_RUN {
    tag "$runfolder"
    //publishDir "$qcfolder" + "Delivery" , mode:'link',  overwrite: true
    container "ghcr.io/nsc-norway/qc-delivery-email-scripts:1.0.0"

    input:
    path runfolder
    path qcfolder
    path project_lims_json

    output:
    val "email_summary_run_complete", emit: EMAIL_SUMMARY_RUN_out

    script:
    """
    make-emails.py \
            --run-dir=$runfolder \
            --demultiplex-stats=$qcfolder/Demux/Demultiplex_Stats.csv \
            --suprdupr-dir=$qcfolder/suprDUPr \
            --bclconvert-version=$params.bcl_convert_version \
            --pipeline-version=$params.pipeline_version \
            --output-email-dir=$qcfolder/Delivery \
            --create-summary \
            $project_lims_json
    """
}
*/
process DECOMPRESS_ORA {
    tag "$meta.sample_id"
    
    publishDir { "${params.outdir}/${meta.project_dir_name}" }, mode:'link', overwrite: true

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
    
    publishDir { "${params.outdir}/${meta.project_dir_name}" }, mode:'link', overwrite: true

    input:
    tuple val(meta), path(fastq)

    output:
    tuple val(meta), path(newName), emit: RENAME_AND_SAVE_FASTQS_out

    script:
    newName = getNewFastqName(fastq.getName(), meta.sample_id, meta.sample_name)
    """
    if [ "${fastq}" != "$newName" ]; then
        mv $fastq $newName
    fi
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