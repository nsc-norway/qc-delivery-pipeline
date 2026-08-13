# NSC QC & Delivery pipeline

NSC data handling - new pipeline based on Sapio LIMS.

See the repo linked below for the initial data handling tools shared between NSC and GDx (diagnostics) - for demultiplexing and Sapio LIMS integration:

https://gitlab.com/genomedx/labautomation/sapio-sequencingfiles


## Entry points and usage


### Direct pipeline invocation (TODO - update with current parameter specs)

```
nextflow run nsc-nextflow/main.nf \
  --runFolder tests/fixtures/20260715_SH01006_0020_ASC2245414-SC3 \
  --bclConvertFastqDir tests/fixtures/20260715_SH01006_0020_ASC2245414-SC3/Analysis/3/Data/BCLConvert/fastq \
  --outdir output/outdir \
  --deliveryDir output/delivery \
  -resume

  TODO -- update
```

### Input / output parameter spec

Input:

* runFolder example: 
* analysisBclConvertFolers 


Output:

* outdir: base root.

Example:

...

Creates:

...


### Scheduled automation worker

Scans a run folder location for unprocessed runs, looks up LIMS information and starts an appropriate
pipeline based on the project type.

Automation worker requires exported environment variables for configuration:


```
set -a            # Automatically export all subsequent variables
source .env       # Read and execute the file in the current shell
set +a            # Turn off the automatic export feature
scripts/nsc-automation-cron.sh
```




```
set -a            # Automatically export all subsequent variables
source .env       # Read and execute the file in the current shell
set +a            # Turn off the automatic export feature
scripts/nsc-automation-cron.sh
```

The scripts are configured using environment variables. An example is given in .env.example. The 
nextflow pipeline should not read environment variables, and is instead configured explicitly using
parameters (see above).


TODO - describe running this or refer to deployment docs




## Requirements

### Pipeline

The Nextflow-based pipeline requires a local **Java and Nextflow** on the path.

* Java >= 17
* Nextflow 26.04.6

For local development and manual tests, create the project environment from the
repository root:

```
conda env create -f environment.yml
conda activate qc-delivery-pipeline
```

The pipeline's environment is not containerized due to the complexity of job submission from a container.
Docker must be installed and its daemon running for pipeline runs and the
Nextflow test suite.


### Scripts

The shell scripts require Bash on an Unix-like OS.

The Python scripts require Python >= 3.9 locally installed, and only rely on the standard library.


## Testing

Tests are run manually during development and are not currently run in GitHub
CI. Use the project Conda environment before running them.

### Nextflow pipeline

Run the end-to-end Nextflow test from `nsc-nextflow/`:

```
cd nsc-nextflow
nf-test test
```

Run an individual test by its name tag:

```
nf-test test --tag MiSeq.20260715.3
```

When development intentionally changes expected output, update that test's
snapshots:

```
nf-test test --tag MiSeq.20260715.3 --update-snapshot
```

### Cron worker

Run the cron worker tests from the repository root:

```
bats tests/cron/nsc-automation-cron.bats
```

They use temporary run folders and mocked pipeline, delivery, and Sapio
commands. The suite checks completion-marker handling, department routing, and
the missing `NscSapioInfo.yaml` path without starting Nextflow or contacting
Sapio.


## Repo layout

### Cron job, script and Sapio extractor: scripts/

#### Main pipeline running scripts

##### nsc-automation-cron.sh

Primary entry point for automatic job execution. 


#### Helper scripts

* scripts/anonymize-fastq.py


### miseq-delivery-simple.sh

Stand-alone script for legacy MiSeq data transfers - not integrated with the rest of the repo.


### Setup and installation: deployment/

Contains code for deploying the pipeline and orchestration in a production environment.

TODO



### QC / Delivery pipeline: nsc-nextflow/

Nextflow pipeline for data QC, file copying, report generation and data delivery preparation.


### Containers: dockerfiles/

Dockerfiles for tools that are contained in this repo. The docker images are built through Github Actions.

For external tools there are instead references to public Docker images.


