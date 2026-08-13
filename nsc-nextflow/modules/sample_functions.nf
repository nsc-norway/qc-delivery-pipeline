/**
 * Parse an Illumina SampleSheet v2 and extract only the [BCLConvert_Data] rows,
 * emitting tuples of ( Lane, Sample_Name, Sample_Project ). Sheets without a
 * Lane column (NoLaneSplitting) are assigned lane 1.
 *
 * @param sheetFile       Path to SampleSheet.csv
 * @return                A Channel emitting tuple( lane, sampleName, projectName )
 */
def parseBclConvertData( sheetFile ) {
    def rows         = []
    def inData   = false
    def hdr = null
    def idxLane = -1
    def idxId = -1
    def idxProj = -1
    def useProjectColumn = false // to be determined

    sheetFile.toFile().eachLine { line ->
        def t = line.trim()

        // 1) enter the data block
        if( t ==~ /\[BCLConvert_Data\],*/ ) {
            inData = true
            hdr     = null
            return
        }

        if( inData ) {
            // 2) leave on next section header
            if( t.startsWith('[') ) {
                inData = false
                return
            }

            // 3) parse the header row
            if( !hdr && ! t.replaceAll(',', '').isEmpty() ) {
                hdr      = t.split(',').toList()
                idxLane  = hdr.indexOf('Lane')
                idxId    = hdr.indexOf('Sample_ID')
                idxProj = hdr.indexOf('Sample_Project')
                if( idxId < 0 ) {
                    throw new IllegalArgumentException(
                        "Missing 'Sample_ID' in header: $t"
                    )
                }
                if( idxProj >= 0 ) {
                    useProjectColumn = true
                }
            }
            // 4) data rows
            else if( ! t.replaceAll(',', '').isEmpty() ) {
                def vals = t.split(',')
                def lane = idxLane >= 0 ? vals[idxLane].toInteger() : 1
                def sampleId = vals[idxId]
                def projectName = null
                if( useProjectColumn ) {
                    projectName  = vals[idxProj]
                }
                else {
                    projectName  = null
                }
                rows << tuple( lane, projectName, sampleId )
            }
        }
    }
    return rows
}

def unpackSampleIds( projectName, sampleId ) {
    // If no Project_Name is given in the SampleSheet, the project name should be included in the Sample_ID column.
    // GUID may be included at the end of the Sample_ID value (sampleId).
    // This function returns: (projectName, sampleName, guid)

    // First strip and extract the GUID if it appears to be in GUID format.
    def parts = sampleId.split('_')
    def sampleName = sampleId
    def guid = null
    if( parts.size() > 2 && parts[-1] ==~ /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/ ) {
        guid = parts[-1]
        sampleName = parts[0..-2].join('_')
    }

    // If project name was not extracted from the SampleSheet, i.e. projectName == null, then use the first part of the sampleName as the project name.
    if( ! projectName ) {
        def sampleParts = sampleName.split('_')
        if( sampleParts.size() > 1 ) {
            projectName = sampleParts[0..-2].join('_')
            sampleName = sampleParts[-1]
        }
    }
    return tuple( projectName, sampleName, guid )
}

def getProjectDirName( projectName, runId ) {
    // Example runId: 20250502_LH00534_0135_B22LCYYLT4 
    // Example Long projectName: 250502_LH00534.B.Project_Christophersen-DNA2-2025-04-10
    def runIdParts = runId.split('_')
    if( runIdParts.size() < 3 ) {
        throw new IllegalArgumentException(
            "Invalid runId format: $runId"
        )
    }
    return runIdParts[0][-6..-1] + '_' + runIdParts[1] + '.' + runIdParts[-1][0] + '.Project_' + projectName
}

/**
 * Find the FASTQ files for one sample / lane by globbing for any _S<digits>_ tag.
 *
 * @param lane             (Integer)  the lane number (e.g. 1, 2, …)
 * @param fastqDir         (Path)     Fastq directory
 * @param sampleId         (String)   Sample ID
 * @param sampleProject    (String)   Value of Sample_Project column in SampleSheet (may be null)
 * @param isOraCompressed  (Boolean)  True if ora compressed, otherwise gz
 * @return                 Tuples of (readLabel, fastq_path) for each FASTQ file found for the sample.
 */
def getFastqReadLabelsAndPaths( lane, fastqDir, sampleId, sampleProject, isOraCompressed ) {
    // decide which reads to look for
    def extensionPattern = "\\.fastq\\.gz"
    if (isOraCompressed) {
        extensionPattern = "\\.fastq\\.ora"
    }

    // For each read (1 or 2), pick the one file matching
    //   <sampleId>_S<digits>_L00<lane>_<read>_001.fastq.gz
    ["R1", "I1", "I2", "R2"].collect { readLabel ->
        // build a Groovy regex to match the unpredictable S<digits> part
        def pattern = "^${sampleId}_S\\d+_L00${lane}_${readLabel}_001${extensionPattern}\$"
        def fastqLocalDir = fastqDir
        if (sampleProject) {
            fastqLocalDir = fastqDir.resolve(sampleProject)
        }
        def match = fastqLocalDir.listDirectory().find { fastqFile -> fastqFile.name ==~ pattern }
        if( ! match ) {
            if (readLabel == "R1") {
                throw new FileNotFoundException("No FASTQ file matching $pattern in $fastqLocalDir")
            }
            else {
                match = ""
            }
        }
        return [ readLabel, match.toString() ]
    }.findAll { _readLabel, fastqPath -> fastqPath } // remove any empty matches
}

/**
 * Group the channel elements by project name.
 */
def groupByProject( files_ch ) {
    return files_ch.map { meta, fastqPath -> [meta.project_name, meta, fastqPath] }
                   .groupTuple()
                   .map { projectName, metas, fastqs -> [[
                            run_id: metas[0].run_id,
                            project_name: projectName,
                            project_dir_name: metas[0].project_dir_name,
                        ], fastqs] }
}


