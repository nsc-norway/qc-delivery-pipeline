/* If you prefer to change the reports directory, change the following in nextflow.config file
reportdir = "$baseDir/90_reports/"

If you prefer to change the container directory, change the following in nextflow.config file
containerdir = "/data/runScratch.boston/analysis/pipelines/container-images/"
*/

include {
    CAT_MD5SUM;
    //EMAIL_PROJECT;
    //EMAIL_SUMMARY_RUN;
    FASTQC;
    //JSON_GENERATOR;
    //LINK_FOLDER;
    //MAKE_SENSITIVE_DATA_LOG_FILE;
    MD5SUM_FASTQ;
    MULTIQC;
    //PROJECT_CREDENTIALS;
    SUPRDUPR;
    //TAR_FOLDER;
    DECOMPRESS_ORA;
    RENAME_AND_SAVE_FASTQS;
} from './modules/modules.nf'

include {
    parseBclConvertData;
    getProjectDirName;
    getFastqReadLabelsAndPaths;
    unpackSampleIds;
    groupByProject;
} from './modules/parse_samplesheet.nf'


workflow {
    // Get the Run ID as the name of the run folder
    def runid = file(params.runFolder).getName()

    // Input files
    def sapioFile = file("${params.runFolder}/NscSapioInfo.yaml")
    def sampleSheet = file("${params.bclConvertFastqDir}/Reports/SampleSheet.csv")
    def fastqDir = file(params.bclConvertFastqDir)

    println ("Working on Run: $runid")

    def isOra = false // ORA support is not yet implemented

    // Create samples channel from SampleSheet
    // One entry per fastq file (up to two entries per sample)
    // The elements of the channel are map objects containing the sample information.
    def sample_metadata_ch = channel.fromPath( sampleSheet, checkIfExists: true )
        .flatMap { samplesheet_file -> parseBclConvertData(samplesheet_file) }
        // tuples of (lane, projectName, sampleId)
        .unique()
        .map { lane, origProjectName, sampleId ->
            def (projectName, sampleName, guid) = unpackSampleIds(origProjectName, sampleId)
            def projectDirName = getProjectDirName(projectName, runid)
            def sampleKey = "${lane}_${projectName}_${sampleId}"
            [
                id: sampleKey,
                lane: lane,
                project_name: projectName,
                project_dir_name: projectDirName,
                sample_id: sampleId,
                sample_name: sampleName,
                guid: guid
            ]
        }

    // One entry per FASTQ file. Format: [meta, fastqPath]
    // This file channel contains two entries per sample for paired-end runs, four entries
    // per sample in case of paired end + index reads fastqs are enabled, etc.
    def original_files_ch = sample_metadata_ch.flatMap { meta ->
            def fastqs = getFastqReadLabelsAndPaths(meta.lane, fastqDir, meta.sample_id, isOra)
            fastqs.collect { readLabel, fastqPath ->
                [meta + [read_label: readLabel], fastqPath]
        }
    }

    def files_ch
    if (isOra) {
        // ORA Compressed samples (see above; ORA was currently not supported when writing this)
        files_ch = DECOMPRESS_ORA(original_files_ch)
    }
    else {
        files_ch = RENAME_AND_SAVE_FASTQS(original_files_ch)
    }


    MD5SUM_FASTQ(files_ch)
    // Apply CAT_MD5SUM grouped by project
    CAT_MD5SUM(groupByProject(MD5SUM_FASTQ.out.MD5SUM_FASTQ_out))


    // suprDUPr QC. Used by the email scripts if available.

    // TODO - suprDUPr should be disabled (or reconfigured) in case the read length
    // is less than 51 bases. Otherwise, it will crash.
    superdupr_ch = channel.empty() // Channel to contain suprDUPr outputs
    if (params.enableSuprdupr.toBoolean()) {
        def suprdupr_files_ch = files_ch.filter { item -> item[0].read_label == 'R1' }
        SUPRDUPR(suprdupr_files_ch)
        suprdupr_ch = SUPRDUPR.out.collect()
    }

    // FastQC and MultiQC. MultiQC reports are included in the data delivery.
    // DRAGEN FastQC from the onboard analysis can be used as an alternative to FastQC.
    multiqc_ch = channel.empty() // Channel to contain multiqc outputs
    if (params.enableFastQC.toString().toBoolean()) {
        def data_read_files_ch = files_ch.filter { sample -> sample[0].read_label in ['R1', 'R2'] }
        FASTQC(data_read_files_ch)
        multiqc_ch = MULTIQC(groupByProject(FASTQC.out.FASTQC_ZIP_out), "fastqc")
    }
    else if (params.enableSuprdupr.toBoolean()) {
        //MULTIQC(analysis_project_folder, dataProjectFolder, "dragen_fastqc")
    }

    /*
    JSON_GENERATOR(params.project, qcfolder)
    PROJECT_CREDENTIALS(params.project, dataProjectFolder, params.passwordTool)

    def samples_fastqs = samples_ch.collect { sample -> sample[2] }
    if (params.deliverymethod == 'Norstore') {
        TAR_FOLDER(
            projectDirName,
            params.runFolder,
            params.deliverydir,
            PROJECT_CREDENTIALS.out.username_txt,
            PROJECT_CREDENTIALS.out.htpasswd,
            MULTIQC.out.MULTIQC_out,
            CAT_MD5SUM.out
        )
    }
    if (params.deliverymethod in ['NeLS_project', 'User_HDD', 'New_HDD', 'TSD_project']) {
        LINK_FOLDER(projectDirName, samples_fastqs, MULTIQC.out.MULTIQC_out, CAT_MD5SUM.out)
    }

    EMAIL_PROJECT(
        params.project,
        params.runFolder,
        qcfolder,
        JSON_GENERATOR.out.JSON_GENERATOR_out,
        PROJECT_CREDENTIALS.out.credentials_json
    )
    MAKE_SENSITIVE_DATA_LOG_FILE(projectDirName, JSON_GENERATOR.out.JSON_GENERATOR_out, params.runFolder)

    // Run-level process
    EMAIL_SUMMARY_RUN(params.runFolder, qcfolder, project_lims_json.collect())
    */
}
