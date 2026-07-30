/* If you prefer to change the reports directory, change the following in nextflow.config file
reportdir = "$baseDir/90_reports/"

If you prefer to change the container directory, change the following in nextflow.config file
containerdir = "/data/runScratch.boston/analysis/pipelines/container-images/"
*/

include {
    //CAT_MD5SUM;
    //EMAIL_PROJECT;
    //EMAIL_SUMMARY_RUN;
    //FASTQC;
    //JSON_GENERATOR;
    //LINK_FOLDER;
    //MAKE_SENSITIVE_DATA_LOG_FILE;
    //MD5SUM_FASTQ;
    //MULTIQC;
    //PROJECT_CREDENTIALS;
    //SUPRDUPR;
    //TAR_FOLDER;
    DECOMPRESS_ORA
} from './modules/modules.nf'

include {parseBclConvertData; getProjectDirName; getFastqReadLabelsAndPaths; unpackSampleIds} from './modules/parse_samplesheet.nf'

params.runFolder = "/data/runScratch.boston/demultiplexed/DUMMY_RUN"
params.bclConvertFastqDir = "/data/runScratch.boston/demultiplexed/DUMMY_RUN/Analysis/1/BCLConvert/fastq"

workflow {
    // Get the Run ID as the name of the run folder
    def runid = file(params.runFolder).getName()

    // Input files
    def sapioFile = file("${params.runFolder}/NscSapioInfo.yaml")
    def sampleSheet = file("${params.bclConvertFastqDir}/Reports/SampleSheet.csv")


    println ("Working on Run: $runid")

    def isOra = false // ORA support is not yet implemented

    // Create samples channel from SampleSheet
    // One entry per fastq file (up to two entries per sample)
    // Format:
    // [(projectDirName, sampleName, fqPath), ...]
    def sample_metadata_ch = channel.fromPath( sampleSheet, checkIfExists: true )
        .flatMap { samplesheet_file -> parseBclConvertData(samplesheet_file) }
        // tuples of (lane, projectName, sampleId)
        .unique()
        .map { lane, origProjectName, sampleId ->
            def (projectName, sampleName, guid) = unpackSampleIds(origProjectName, sampleId)
            def projectDirName = getProjectDirName(projectName, runid)
            def sampleKey = "${lane}_${projectName}_${sampleId}"
            [sampleKey, lane, projectName, projectDirName, sampleId, sampleName, guid]
        }

    /*

    original_files_ch = sample_metadata_ch.flatMap
        {
            sampleKey, lane, projectName, projectDirName, sampleId, sampleName, guid ->
            def fastqs = getFastqReadLabelsAndPaths(lane, fastqPath, sampleName, isOra)
            fastqs.collect { readLabel, fastqPath ->
                [sampleKey, readLabel, fastqPath]
            }
        }

    def files_ch
    if (isOra) {
        // ORA Compressed samples
        files_ch = DECOMPRESS_ORA(original_files_ch)
    }
    else {
        files_ch = original_files_ch
    }

    MD5SUM_FASTQ(files_ch)

    CAT_MD5SUM(dataProjectFolder, MD5SUM_FASTQ.out.MD5SUM_FASTQ_out.collect())

    superdupr_ch = channel.empty()
    if (params.enableSuprdupr.toString().toBoolean()) {
        def suprdupr_samples_ch = files_ch.filter { sample -> sample[1].toString() == 'R1' }
        SUPRDUPR(suprdupr_samples_ch, qcfolder)
        suprdupr_ch = SUPRDUPR.out.SUPRDUPR_out.collect()
    }

    if (params.enableFastQC.toString().toBoolean()) {
        FASTQC(files_ch, analysis_project_folder)
        MULTIQC(FASTQC.out.FASTQC_ZIP_out.collect(), dataProjectFolder, "fastqc")
    }
    else {
        MULTIQC(analysis_project_folder, dataProjectFolder, "dragen_fastqc")
    }

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
