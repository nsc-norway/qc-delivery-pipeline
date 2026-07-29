# NSC QC & Delivery pipeline

NSC data handling - new pipeline based on Sapio LIMS.

See the repo linked below for the initial data handling tools shared between NSC and GDx (diagnostics) - for demultiplexing and Sapio LIMS integration:

https://gitlab.com/genomedx/labautomation/sapio-sequencingfiles



## Repo overview

### miseq-delivery-simple.sh

Stand-alone script for legacy MiSeq data transfers - not integrated with the rest of the repo.


### QC / Delivery pipeline: nsc-nextflow

TODO

#### Containers

TODO - container information


### Cron job, script and Sapio extractor: scripts

TODO

#### Run information payload



```yaml

run:
    flowcell_id: 23AAAACIX

samples:
    Bjoernstad-DNA22-2026-05-06_1-TestSample_30dd879c-ee2f-11db-8314-0800200c9a66:
        project: Bjoernstad-DNA22-2026-05-06
        sample_prep: Illumina DNA
        sample_name: 1-TestSample
        sequencingfile_record_id: 330

    TI-IMM1-2026-05-06_1-H2O_64f3cb6a-e70e-45e5-8b90-d86cddbab7bb:
        project: TI-IMM1-2026-05-06
        sample_name: 1-H2O
        sequencingfile_record_id: 331

projects:
    Bjoernstad-DNA22-2026-05-06:
        DepartmentName: NSC
        DeliveryMethod: NeLS project
        NeLSProjectId: OUS_PipelineSeq_2026
        TSDProjectId: ''
        ContactPerson: Test Contact
        ContactEmail: test@example.com
    TI-IMM1-2026-05-06:
        DepartmentName: IMM

```
