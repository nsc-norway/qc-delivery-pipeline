#!/usr/bin/env python

# Get project info script

from genologics.lims import *
import sys
import json

if len(sys.argv) < 2:
    print("usage: get-project-info.py PROJECT_NAME")
    sys.exit(1)

pw_file = "/etc/apiuser-pw.txt"
lims = Lims(    "https://ous-lims.sequencing.uio.no",
                "apiuser",
                open(pw_file).read().strip()
                )

projects = lims.get_projects(name=sys.argv[1].split('_')[-1])
if len(projects) != 1:
    print(f"Looking for projects named {sys.argv[1]}, expected one, but found {len(projects)} projects.")
    sys.exit(1)
project = projects[0]
project_info = {
    'project_info_version': 1,
    'Project ID': project.id,
    'Project name': project.name,
}
for udf in [
        'Delivery method',
        'Project type',
        'Contact person',
        'Contact email',
        ]:
    project_info[udf] = project.udf[udf]

for optional_udf in [
        'REK approval number',
        'TSD project ID'
        ]:
    project_info[optional_udf] = project.udf.get(optional_udf, '')

json.dump(
        project_info,
        sys.stdout
        )

