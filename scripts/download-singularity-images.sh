#!/bin/bash

# This script should be run from the repository root.
#
# Images are downloaded into singularity-images/ using Nextflow's own
# singularity cache naming convention (image ref with "/" and ":" replaced
# by "-", plus a .img extension). This lets nextflow.config point
# singularity.cacheDir at this folder and use the pre-downloaded images.

grep -h "^\s*container\b" nsc-nextflow/modules/*.nf | 
    sed 's/^[ ]*container[ ]*["]*//' | sed 's/"[ ]*$//' |
    sort -u | 
    while read -r image; do
        cache_name=$(echo "$image" | sed 's/[/:]/-/g').img
        docker run --rm -v "$PWD"/singularity-images:/singularity-images \
                        nfcore/gitpod \
                            singularity pull --dir "/singularity-images" --name "$cache_name" "docker://${image}"
    done
