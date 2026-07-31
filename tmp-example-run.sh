

nextflow run nsc-nextflow/main.nf \
  --runId 20260625_LH00534_0319_A22JKHGLT1 \
  --sapioRunFile tests/fixtures/20260625_LH00534_0319_A22JKHGLT1/NscSapioInfo.yaml \
  --bclConvertFastqDir tests/fixtures/20260625_LH00534_0319_A22JKHGLT1/Analysis/c2/Fastq \
  --outdir output/outdir \
  -resume


nextflow run nsc-nextflow/main.nf \
  --runId 20260715_SH01006_0020_ASC2245414-SC3 \
  --sapioRunFile tests/fixtures/20260715_SH01006_0020_ASC2245414-SC3/NscSapioInfo.yaml \
  --bclConvertFastqDir tests/fixtures/20260715_SH01006_0020_ASC2245414-SC3/Analysis/3/Data/BCLConvert/fastq \
  --outdir output/outdir \
  -resume

