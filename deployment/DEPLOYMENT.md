# Production deployment

The following procedure is used to set up the system in production.


Download the container images using this command:

```
scripts/download-singularity-images.sh
```

This git repo should be made available on the target system, including the singularity
images (ignored by git).

The pipeline is configured using a config file which defines environment variables.
(Some settings are not controllable in this way, and require manual overrides - e.g.
enable FastQC)

The example is given in `example.env`.

Then the pipeline should simply be added as a cron job, specifying the environment
file as an argument.

Here is a line for `/etc/crontab`:

```
 * * * * * EXAMPLE_USER /EXAMPLE_PATH_1/qc-delivery-pipeline/scripts/nsc-automation-cron.sh /EXAMPLE_PATH_2/mysite.env
```
