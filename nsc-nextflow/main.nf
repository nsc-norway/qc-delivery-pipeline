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
    JSON_GENERATOR;
    LINK_FOLDER;
    MAKE_SENSITIVE_DATA_LOG_FILE;
    MD5SUM_FASTQ;
    MULTIQC;
    PROJECT_CREDENTIALS;
    SUPRDUPR;
    TAR_FOLDER;
    DECOMPRESS_ORA
} from './modules/modules.nf'

include {parseBclConvertData; getProjectDirName; getFastqPaths} from './modules/parse_samplesheet.nf'

params.runid = "DUMMY_RUN"
params.runfolder = "/data/runScratch.boston/demultiplexed/DUMMY_RUN"
params.qcid = "QualityControl"
params.project = "DUMMY"

params.enableSuprdupr = true
params.enableFastQC = true
params.deliverymethod = 'Norstore' // Norstore, NeLS_project, User_HDD, New_HDD, TSD_project

workflow {
    println ("Working on Run: $params.runid, Project: $params.project") 

    def sampleSheet = "${params.runfolder}/${params.qcid}/SampleSheet.csv"
    def qcfolder = "${params.runfolder}/${params.qcid}"

    // Get project directory name e.g. 250611_LH00534.A.Project_Foo-1999-12-31
    def project_dir_name = getProjectDirName(params.project, params.runid)
    def fastq_path_ora = "${params.runfolder}/${project_dir_name}_ora"
    def is_ora = file(fastq_path_ora).exists()
    def fastq_path = file(fastq_path_ora)
    def data_project_folder = "${params.runfolder}/${project_dir_name}"
    if ( ! is_ora) {
        fastq_path = file(data_project_folder)
    }

    // Create samples channel from SampleSheet
    // One entry per fastq file (up to two entries per sample)
    // Format:
    // [(project_dir_name, sampleName, fqPath), ...]
    def original_samples_ch = channel.fromPath( sampleSheet, checkIfExists: true )
        .flatMap { samplesheet_file -> parseBclConvertData(samplesheet_file) }
        // tuples of (lane, project, sampleName)
        .unique()
        .filter { sample -> sample[1] == params.project }
        .flatMap { lane, project, sampleName ->
            // glob out FASTQs (handles both R1+R2 if paired)
            def fq_paths = getFastqPaths(lane, fastq_path, sampleName, is_ora)
            // emit a 3-tuple: (project dir name, sample_id, fastqs) for each file
            fq_paths.collect { fq_path -> [ project_dir_name, sampleName, fq_path ] }
        }

    def samples_ch
    if (is_ora) {
        // ORA Compressed samples
        samples_ch = DECOMPRESS_ORA(original_samples_ch, data_project_folder)
    }
    else {
        samples_ch = original_samples_ch
    }

    def analysis_project_folder = "${params.runfolder}/${params.analysisid}/${project_dir_name}"

    MD5SUM_FASTQ(samples_ch, data_project_folder) /*max 10 jobs*/
    CAT_MD5SUM(data_project_folder, MD5SUM_FASTQ.out.MD5SUM_FASTQ_out.collect())

    superdupr_ch = channel.empty()
    if (params.enableSuprdupr.toString().toBoolean()) {
        def suprdupr_samples_ch = samples_ch.filter { sample -> sample[2].toString().contains('R1_001') }
        SUPRDUPR(suprdupr_samples_ch, qcfolder)
        suprdupr_ch = SUPRDUPR.out.SUPRDUPR_out.collect()
    }

    if (params.enableFastQC.toString().toBoolean()) {
        FASTQC(samples_ch, analysis_project_folder)
        MULTIQC(FASTQC.out.FASTQC_ZIP_out.collect(), data_project_folder, "fastqc")
    }
    else {
        MULTIQC(analysis_project_folder, data_project_folder, "dragen_fastqc")
    }

    JSON_GENERATOR(params.project, qcfolder)
    PROJECT_CREDENTIALS(params.project, data_project_folder, params.passwordTool)
    
    def samples_fastqs = samples_ch.collect { sample -> sample[2] }
    if (params.deliverymethod == 'Norstore') {
        TAR_FOLDER(
            project_dir_name,
            params.runfolder,
            params.deliverydir,
            PROJECT_CREDENTIALS.out.username_txt,
            PROJECT_CREDENTIALS.out.htpasswd,
            MULTIQC.out.MULTIQC_out,
            CAT_MD5SUM.out
        )
    }
    if (params.deliverymethod in ['NeLS_project', 'User_HDD', 'New_HDD', 'TSD_project']) {
        LINK_FOLDER(project_dir_name, samples_fastqs, MULTIQC.out.MULTIQC_out, CAT_MD5SUM.out)
    }

    EMAIL_PROJECT(
        params.project,
        params.runfolder,
        qcfolder,
        JSON_GENERATOR.out.JSON_GENERATOR_out,
        PROJECT_CREDENTIALS.out.credentials_json
    )
    MAKE_SENSITIVE_DATA_LOG_FILE(project_dir_name, JSON_GENERATOR.out.JSON_GENERATOR_out, params.runfolder)

    // Run-level process
    EMAIL_SUMMARY_RUN(params.runfolder, qcfolder, project_lims_json.collect())
}
