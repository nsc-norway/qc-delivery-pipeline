process SPLIT_PROJECT {
    input:
    path(samplesheet)

    output:
    path "*_${samplesheet}", emit: SPLIT_PROJECT_out

    script:
    """
    split_samplesheet.py $samplesheet
    """
}

process MD5SUM_FASTQ {
    tag "$NewSampleID"
    publishDir "$runfolder" + "$NSC_ProjectName", mode:'link',  overwrite: false

    input:
    val runfolder
    tuple val(NSC_ProjectName), val(NewSampleID), path(fastq)

    output:
    tuple val(NSC_ProjectName), val(NewSampleID), path ("${fastq}.md5"), emit: MD5SUM_FASTQ_out


    script:
    """
    md5sum $fastq > ${fastq}.md5
    """
}


process SUPRDUPR {
    tag "$NewSampleID"
    publishDir "$qcfolder" + "suprDUPr", mode:'link',  overwrite: false

    input:
    val qcfolder
    tuple val(NSC_ProjectName), val(NewSampleID), path(fastq)
    
    when:
    fastq.name =~ /.*R1_001.*/ 

    output:
    path "${NSC_ProjectName}_${fastq}.suprDUPr.txt"

    script:
    """
    suprDUPr -r $fastq > ${NSC_ProjectName}_${fastq}.suprDUPr.txt
    """
}

process MULTIQC {
    container "/data/common/tools/multiqc/current.sif"
    tag "$NSC_ProjectName"
    publishDir "$analysisfolder" + "suprDUPr", mode:'link',  overwrite: false

    input:
    path analysisfolder
    
    //output:
    //path "${NSC_ProjectName}_${fastq}.suprDUPr.txt"

    script:
    """
    multiqc --module dragen_fastqc .
    """
}


process TAR_FOLDER {
//    tag "$NewSampleID"
//    publishDir "$runfolder" + "$NSC_ProjectName", mode:'link',  overwrite: false

    input:
    path runfolder
    tuple val(NSC_ProjectName), val(NewSampleID), path(fastq_md5)


    //output:
    //path "${runfolder}.tar.gz"

    script:
    """
    echo tar -xvf $runfolder
    """
}

process MD5SUM_FILE {
//    tag "$NewSampleID"
//    publishDir "$runfolder" + "$NSC_ProjectName", mode:'link',  overwrite: false

    input:
    path file

    output:
    path "${file}.md5"

    script:
    """
    echo md5sum $file > ${file}.md5
    """
}


