/* If you prefer to change the reports directory, change the following in nextflow.config file
reportdir = "$baseDir/90_reports/"

If you prefer to change the container directory, change the following in nextflow.config file
containerdir = "/data/runScratch.boston/analysis/pipelines/container-images/"
*/

include {
    CAT_MD5SUM;
    EMAIL_PROJECT;
    EMAIL_SUMMARY_RUN;
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


workflow QC_DELIVERY_PIPELINE {
    main:
    // LOCATE INPUT FILES

    def bclConvertFastqDir = file("${params.analysisDir}/Fastq")
    if (!bclConvertFastqDir.exists()) {
        bclConvertFastqDir = file("${params.analysisDir}/Data/BCLConvert/fastq")
    }

    // Sample sheet is usually copied to Reports/ by BCL Convert, but in case of NovaSeq X onboard analysis, 
    // it can instead be found directly in the BCLConvert directory (next to fastqc outputs).
    def sampleSheet = file("${bclConvertFastqDir}/Reports/SampleSheet.csv")
    if (!sampleSheet.exists()) {
        sampleSheet = file("${params.analysisDir}/Data/BCLConvert/SampleSheet.csv")
    }
    def analysisId = file(params.analysisDir).name


    def runId = file(params.runFolder).name
    def sapioRunFile = file("${params.runFolder}/NscSapioInfo.yaml")
    def sapioRunInfo = sapioRunFile.exists() ? new groovy.yaml.YamlSlurper().parseText(sapioRunFile.text) : [projects: []]

    println ("Working on Run: ${runId}")

    def isOra = false // ORA support is not yet implemented


    // CREATE CHANNEL sample_metadata_ch FOR SAMPLES

    // Create samples channel from SampleSheet
    // The elements of the channel are map objects containing the sample information.
    def sample_metadata_ch = channel.fromPath( sampleSheet, checkIfExists: true )
        .flatMap { samplesheet_file -> parseBclConvertData(samplesheet_file) }
        // tuples of (lane, projectName, sampleId)
        .unique()
        .map { lane, sampleProjectColumnValue, sampleId ->
            def (projectName, sampleName, guid) = unpackSampleIds(sampleProjectColumnValue, sampleId)
            def projectDirName = getProjectDirName(projectName, runId)
            def sampleKey = "${lane}_${projectName}_${sampleId}"
            [
                run_id: runId,
                analysis_id: analysisId,
                id: sampleKey,
                lane: lane,
                project_name: projectName,
                sample_project_column_value: sampleProjectColumnValue,
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
            def fastqs = getFastqReadLabelsAndPaths(meta.lane, bclConvertFastqDir, meta.sample_id, meta.sample_project_column_value, isOra)
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
    def suprdupr_ch = channel.empty()
    if (params.enableSuprdupr.toBoolean()) {
        def suprdupr_files_ch = files_ch.filter { item -> item[0].read_label == 'R1' }
        SUPRDUPR(suprdupr_files_ch)
        suprdupr_ch = SUPRDUPR.out
    }

    // FastQC and MultiQC. MultiQC reports are included in the data delivery.
    // DRAGEN FastQC from the onboard analysis can be used as an alternative to FastQC.
    def fastqc_html_ch = channel.empty()
    def multiqc_ch = channel.empty()
    if (params.enableFastQC.toString().toBoolean()) {
        def data_read_files_ch = files_ch.filter { sample -> sample[0].read_label in ['R1', 'R2'] }
        FASTQC(data_read_files_ch)
        fastqc_html_ch = FASTQC.out.FASTQC_HTML_out
        multiqc_ch = MULTIQC(groupByProject(FASTQC.out.FASTQC_ZIP_out), "fastqc")
    }
    else {
        // TODO: Need to support DRAGEN FastQC inputs from onboard analysis. Copy them to outdir and use for multiqc.
        //MULTIQC(analysis_project_folder, dataProjectFolder, "dragen_fastqc")
    }

    // Create project-grouped channel of all files for delivery:
    //  * all fastqs
    //  * multiqc report
    //  * md5sum file
    // And add delivery methods from Sapio as a tuple element - Tuple structure: (delivery_method, meta, [list of files])

    // Structure: (meta, [list of files])
    delivery_files_project_grouped_ch = groupByProject(files_ch)
        .join(CAT_MD5SUM.out.CAT_MD5SUM_out)
        .join(multiqc_ch)
        .map { item -> [item[0], item[1..-1].flatten()] }
    
    def sapioProjects = sapioRunInfo.projects
    // Structure - one element per project: (delivery_method, meta, [list of files])
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

    def TAR_DELIVERY_TYPES = ['NIRD']
    def LINK_DELIVERY_TYPES = ['NeLS project', 'User HDD', 'New HDD', 'TSD project']

    // NIRD - create tar file
    TAR_FOLDER(
        // Input structure to tar process is (project-grouped): (meta, [list of files to deliver])
        delivery_files_project_grouped_ch
            .filter { delivery_method, _meta, _files -> delivery_method in TAR_DELIVERY_TYPES }
            .map { _delivery_method, meta, files -> [meta, files] }
            .join(PROJECT_CREDENTIALS.out.PROJECT_CREDENTIALS_out)
    )

    // Other delivery methods - create folder structure with hard links to files
    LINK_FOLDER(
        // Input structure to link process is (project-grouped): (meta, [list of files to deliver])
        delivery_files_project_grouped_ch
            .filter { delivery_method, _meta, _files -> delivery_method in LINK_DELIVERY_TYPES }
            .map { _delivery_method, meta, files -> [meta, files] }
    )

    // Throw an error if there are any projects with unsupported delivery methods
    delivery_files_project_grouped_ch
        .filter { delivery_method, _meta, _files -> !(delivery_method in TAR_DELIVERY_TYPES + LINK_DELIVERY_TYPES) }
        .map { delivery_method, _meta, _files ->
            error("Unsupported delivery method '${delivery_method}' for project '${_meta.project_name}'")
        }

    // Get demultiplexing stats, publish them in the outdir
    reports_files = channel.fromPath("${bclConvertFastqDir}/Reports/*", checkIfExists: true)
    demux_files = channel.fromPath("${params.analysisDir}/Data/Demux/*")
    //DEMUX_STATS(demux_stats_files)

    // Pick the first file named Demultiplex_Stats.csv from the reports or demux files channels
    // (the file may exist in either one or both)
    demultiplex_stats = reports_files.mix(demux_files)
        .filter { file -> file.name == 'Demultiplex_Stats.csv' }
        .first()

    EMAIL_PROJECT(
        PROJECT_CREDENTIALS.out.PROJECT_CREDENTIALS_out,
        file(params.runFolder),
        analysisId,
        demultiplex_stats,
        sapioRunFile
    )
    // MAKE_SENSITIVE_DATA_LOG_FILE(projectDirName, JSON_GENERATOR.out.JSON_GENERATOR_out, params.runFolder)

    // Run-level process
    EMAIL_SUMMARY_RUN(
        file(params.runFolder),
        analysisId,
        demultiplex_stats,
        suprdupr_ch.toList(),
        sapioRunFile
        )


    emit: // Emit channels for testing
    fastqs = files_ch
    md5sum = CAT_MD5SUM.out.CAT_MD5SUM_out
    fastqc_html = fastqc_html_ch
    suprdupr = suprdupr_ch
    multiqc = multiqc_ch
    nird_delivery = TAR_FOLDER.out.TAR_FOLDER_out
    linked_delivery = LINK_FOLDER.out

}

workflow {
    QC_DELIVERY_PIPELINE()
}
