#!/bin/bash

# This script should be run from the repository root.

grep -h "^\s*container\b" nsc-nextflow/modules/*.nf | 
    sed 's/^[ ]*container[ ]*["]*//' | sed 's/"[ ]*$//' |
    sort -u | 
    while read -r image; do
        docker run --rm -v "$PWD"/singularity-images:/singularity-images \
                        nfcore/gitpod \
                            singularity pull --dir "/singularity-images" "docker://${image}"
    done
