include {EMAIL_SUMMARY_RUN} from './modules/modules.nf'

params.runid = "DUMMY"
params.runfolder = "/data/runScratch.boston/demultiplexed/DUMMY"
params.qcid = "QualityControl"

workflow {
    println ("Working on Run: $params.runid") 

    def qcfolder = "${params.runfolder}/${params.qcid}/"
    def jsonfolder = "${qcfolder}/lims/*.json"
    def project_lims_json = channel.fromPath(jsonfolder, checkIfExists: true )

    EMAIL_SUMMARY_RUN(params.runfolder, qcfolder, project_lims_json.collect())
}
