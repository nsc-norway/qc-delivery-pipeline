nextflow.enable.dsl=2

nf_mod_path = "$baseDir/modules/"

/* If you prefer to change the reports directory, change the following in nextflow.config file
reportdir = "$baseDir/90_reports/"

If you prefer to change the container directory, change the following in nextflow.config file
containerdir = "/data/runScratch.boston/analysis/pipelines/container-images/"
*/

include {
    CAT_MD5SUM;
    EMAIL_PROJECT;
    FASTQC;
    JSON_GENERATOR;
    LINK_FOLDER;
    MAKE_SENSITIVE_DATA_LOG_FILE;
    MD5SUM_FASTQ;
    MULTIQC;
    SUPRDUPR;
    TAR_FOLDER;
    DECOMPRESS_ORA
} from "$nf_mod_path/modules.nf"

include {parseBclConvertData; getProjectDirName; getFastqPaths} from "$nf_mod_path/parse_samplesheet.nf"

params.runid = "DUMMY_RUN"
params.runfolder = "/data/runScratch.boston/demultiplexed/DUMMY_RUN"
params.qcid = "QualityControl"
params.project = "DUMMY"

sampleSheet = "${params.runfolder}/${params.qcid}/SampleSheet.csv"

params.enableSuprdupr = true
params.enableFastQC = true
params.deliverymethod = 'Norstore' // Norstore, NeLS_project, User_HDD, New_HDD, TSD_project

qcfolder = "${params.runfolder}/${params.qcid}"
analysisfolder = "${params.runfolder}/${params.analysisid}"

// Get project directory name e.g. 250611_LH00534.A.Project_Foo-1999-12-31
project_dir_name = getProjectDirName(params.project, params.runid)
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
original_samples_ch = Channel
    .fromPath( sampleSheet, checkIfExists: true )
    .flatMap { file -> parseBclConvertData(file) }
    // tuples of (lane, project, sampleName)
    .unique()
    .filter { it[1] == params.project }
    .flatMap { lane, project, sampleName ->
        // glob out FASTQs (handles both R1+R2 if paired)
        fq_paths = getFastqPaths(lane, fastq_path, sampleName, is_ora)
        // emit a 3‐tuple: (project dir name, sample_id, fastqs) for each file
        fq_paths.collect { [ project_dir_name, sampleName, it ] }
    }

workflow {
    println ("Working on Run: $params.runid, Project: $params.project") 

    if (is_ora) {
        // ORA Compressed samples
        samples_ch = DECOMPRESS_ORA(original_samples_ch, data_project_folder)
    }
    else {
        samples_ch = original_samples_ch
    }

    analysis_project_folder = "${params.runfolder}/${params.analysisid}/${project_dir_name}"

    MD5SUM_FASTQ(samples_ch, data_project_folder) /*max 10 jobs*/
    CAT_MD5SUM(data_project_folder, MD5SUM_FASTQ.out.MD5SUM_FASTQ_out.collect())

    if (params.enableSuprdupr) {
        SUPRDUPR(samples_ch, qcfolder) /*max 10 jobs*/
    }

    fastqc_reports = Channel.fromPath("${analysis_project_folder}/*")
    if (params.enableFastQC) {
        FASTQC(samples_ch, analysis_project_folder)
        MULTIQC(FASTQC.out.FASTQC_ZIP_out.collect(), data_project_folder, "fastqc")
    }
    else {
        MULTIQC(analysis_project_folder, data_project_folder, "dragen_fastqc")
    }

    JSON_GENERATOR(params.project, qcfolder)
    
    samples_fastqs = samples_ch.collect { it[2] }
    if (params.deliverymethod == 'Norstore') {
        TAR_FOLDER(project_dir_name, params.runfolder, MULTIQC.out.MULTIQC_out, CAT_MD5SUM.out)
    }
    if (params.deliverymethod in ['NeLS_project', 'User_HDD', 'New_HDD', 'TSD_project']) {
        LINK_FOLDER(project_dir_name, samples_fastqs, MULTIQC.out.MULTIQC_out, CAT_MD5SUM.out)
    }

    EMAIL_PROJECT(params.project, params.runfolder, qcfolder, JSON_GENERATOR.out.JSON_GENERATOR_out)
    MAKE_SENSITIVE_DATA_LOG_FILE(project_dir_name, JSON_GENERATOR.out.JSON_GENERATOR_out, params.runfolder)

}
