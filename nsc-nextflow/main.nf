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
    LINK_FOLDER;
    //MAKE_SENSITIVE_DATA_LOG_FILE;
    MD5SUM_FASTQ;
    MULTIQC;
    PROJECT_CREDENTIALS;
    SUPRDUPR;
    TAR_FOLDER;
    DECOMPRESS_ORA;
    RENAME_AND_SAVE_FASTQS;
} from './modules/modules.nf'

include {
    parseBclConvertData;
    getProjectDirName;
    getFastqReadLabelsAndPaths;
    unpackSampleIds;
    groupByProject;
} from './modules/sample_functions.nf'


workflow {
    // LOCATE INPUT FILES

    // Sample sheet is usually copied to Reports/ by BCL Convert, but in case of NovaSeq X onboard analysis, 
    // it can instead be found next to the fastq files.
    def sampleSheet = file("${params.bclConvertFastqDir}/Reports/SampleSheet.csv")
    if (!sampleSheet.exists()) {
        sampleSheet = file("${params.bclConvertFastqDir}/SampleSheet.csv")
    }
    def fastqDir = file(params.bclConvertFastqDir)
    def runId = file(params.runFolder).name
    // TODO allow missing file
    def sapioRunFile = file("${params.runFolder}/NscSapioInfo.yaml")
    def sapioRunInfo = new groovy.yaml.YamlSlurper().parseText(sapioRunFile.text)

    println ("Working on Run: ${runId}")

    def isOra = false // ORA support is not yet implemented


    // CREATE CHANNEL sample_metadata_ch FOR SAMPLES

    // Create samples channel from SampleSheet
    // The elements of the channel are map objects containing the sample information.
    def sample_metadata_ch = channel.fromPath( sampleSheet, checkIfExists: true )
        .flatMap { samplesheet_file -> parseBclConvertData(samplesheet_file) }
        // tuples of (lane, projectName, sampleId)
        .unique()
        .map { lane, origProjectName, sampleId ->
            def (projectName, sampleName, guid) = unpackSampleIds(origProjectName, sampleId)
            def projectDirName = getProjectDirName(projectName, runId)
            def sampleKey = "${lane}_${projectName}_${sampleId}"
            [
                run_id: runId,
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



    // INITIAL FASTQ DATA - FIND THE FILES AND PUBLISH THEM TO THE OUTPUT DIR WITH SIMPLE NAMES

    // files_ch will contain (meta, fastqPath) tuples for each FASTQ file.
    
    if (isOra) {
        // ORA Compressed samples (see above; ORA was currently not supported when writing this)
        files_ch = DECOMPRESS_ORA(original_files_ch)
    }
    else {
        files_ch = RENAME_AND_SAVE_FASTQS(original_files_ch)
    }




    // MD5SUM

    // Compute md5sums
    MD5SUM_FASTQ(files_ch)
    // Apply CAT_MD5SUM grouped by project to create md5sum.txt per project
    CAT_MD5SUM(groupByProject(MD5SUM_FASTQ.out.MD5SUM_FASTQ_out))




    // QC TOOLS
    
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
        // TODO: Need to support DRAGEN FastQC inputs from onboard analysis. Copy them to outdir and use for multiqc.
        //MULTIQC(analysis_project_folder, dataProjectFolder, "dragen_fastqc")
    }

    // Create project-grouped channel of all files for delivery:
    //  * all fastqs
    //  * multiqc report
    //  * md5sum file
    // And add delivery methods from Sapio as a tuple element - Tuple structure: (delivery_method, meta, [list of files])

    // Structure 1: (meta, [list of files])
    delivery_files_project_grouped_ch = groupByProject(files_ch)
        .join(CAT_MD5SUM.out.CAT_MD5SUM_out)
        .join(multiqc_ch)
        .map { item -> [item[0], item[1..-1].flatten()] }
    
    def sapioProjects = sapioRunInfo.projects
    // Structure 2 - one element per project: (delivery_method, meta, [list of files])
    delivery_files_project_grouped_ch = delivery_files_project_grouped_ch
        .map { meta, files ->
            [
                // Lookup delivery method from Sapio file
                sapioProjects.find {
                    lims_project -> 
                        lims_project.fields.ProjectName == meta.project_name 
                }?.submission_form?.DeliveryMethod ?: params.fallbackDeliveryMethod,
                meta,
                files
            ]
        }


    // DATA DELIVERY

    // Generate username and password - used by NIRD delivery and email script
    PROJECT_CREDENTIALS(groupByProject(files_ch).map { meta, _files -> meta })

    // NIRD - create tar file
    TAR_FOLDER(
        // Input structure to tar process is (project-grouped): (meta, [list of files to deliver])
        delivery_files_project_grouped_ch
            .filter { delivery_method, _meta, _files -> delivery_method == 'NIRD' }
            .map { _delivery_method, meta, files -> [meta, files] }
            .join(PROJECT_CREDENTIALS.out.PROJECT_CREDENTIALS_out)
    )

    // Other delivery methods - create folder structure with hard links to files
    LINK_FOLDER(
        // Input structure to link process is (project-grouped): (meta, [list of files to deliver])
        delivery_files_project_grouped_ch
            .filter { delivery_method, _meta, _files -> delivery_method in [null, 'NeLS project', 'User_HDD', 'New_HDD', 'TSD_project'] }
            .map { _delivery_method, meta, files -> [meta, files] }
    )

/*
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
