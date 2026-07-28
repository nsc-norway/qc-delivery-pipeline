/**
 * Parse an Illumina SampleSheet v2 and extract only the [BCLConvert_Data] rows,
 * emitting tuples of ( Lane, Sample_Name, Sample_Project ).
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
                if( idxLane < 0 || idxId < 0 ) {
                    throw new IllegalArgumentException(
                        "Missing 'Lane' or 'Sample_ID' in header: $t"
                    )
                }
                if( idxProj >= 0 ) {
                    useProjectColumn = true
                }
            }
            // 4) data rows
            else if( ! t.replaceAll(',', '').isEmpty() ) {
                def vals = t.split(',')
                def lane = vals[idxLane].toInteger()
                def sampleName = null
                def projectName = null

                if( useProjectColumn ) {
                    sampleName   = vals[idxId]
                    projectName  = vals[idxProj]
                }
                else {
                    def parts       = vals[idxId].split('_')
                    projectName     = parts[0..-2].join('_')
                    sampleName      = parts[-1]
                }

                rows << tuple( lane, projectName, sampleName )
            }
        }
    }
    return rows
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
 * @param sampleName       (String)   Sample name
 * @param isOraCompressed  (Boolean)  True if ora compressed, otherwise gz
 * @return                 List<String> of 1 (unpaired) or 2 (paired) paths
 */
def getFastqPaths( lane, fastqDir, sampleName, isOraCompressed ) {
    // decide which reads to look for
    def extensionPattern = "\\.fastq\\.gz"
    if (isOraCompressed) {
        extensionPattern = "\\.fastq\\.ora"
    }

    // For each read (1 or 2), pick the one file matching
    //   <sampleName>_S<digits>_L00<lane>_R<read>_001.fastq.gz
    [1, 2].collect { read ->
        // build a Groovy regex to match the unpredictable S<digits> part
        def pattern = "^${sampleName}_S\\d+_L00${lane}_R${read}_001${extensionPattern}\$"
        def match = fastqDir.listDirectory().find { fastq_file -> fastq_file.name ==~ pattern }
        if( ! match ) {
            if (read == 1) {
                throw new FileNotFoundException("No FASTQ file matching $pattern in $fastqDir")
            }
            else {
                match = ""
            }
        }
        return match.toString()
    }.grep( ~/^.+$/ ) // Keep non-empty strings (single end read)
}
