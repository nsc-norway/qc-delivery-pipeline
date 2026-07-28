nextflow.enable.dsl=2

nf_mod_path = "$baseDir/modules/"

containerdir = "$baseDir/../container-images"


include {EMAIL_SUMMARY_RUN} from "$nf_mod_path/modules.nf"

params.runid = "DUMMY"
params.runfolder = "/data/runScratch.boston/demultiplexed/DUMMY"
params.qcid = "QualityControl"

workflow {
    println ("Working on Run: $params.runid") 

    qcfolder = "${params.runfolder}/${params.qcid}/"
    jsonfolder = "${qcfolder}/lims/*.json"
    project_lims_json = Channel.fromPath(jsonfolder, checkIfExists: true )

    EMAIL_SUMMARY_RUN(params.runfolder, qcfolder, project_lims_json.collect())
}
