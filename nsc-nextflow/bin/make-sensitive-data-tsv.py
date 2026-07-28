#!/usr/bin/env python

import sys
import json

project_dir_name, json_file, output_name = sys.argv[1:4]

data = json.load(open(json_file))

if data['Project type'] == "Sensitive":
    with open(output_name, "w") as output:
        # Common fields
        print(
            project_dir_name,
            data['Delivery method'],
            data['REK approval number'],
            "Research", # Purpose
            "N",        # Analysis
            sep="\t", end="\t", file=output
        )
        if data['Delivery method'].endswith("HDD"):
            # HDD pick-up date	HDD pick-up name	Hand-off by person
            print(
                data['Contact person'],
                sep="\t", end="\t", file=output
            )
            # TSD project	Transfer type (link/sleipnir)	Date transfer complete	Transfer by person
            print(
                "N/A",
                "PICKUP_DATE",
                sep="\t", end="\t", file=output
            )
        elif data['Delivery method'] == "TSD project":
            # HDD pick-up date	HDD pick-up name	Hand-off by person
            print(
                "N/A",
                sep="\t", end="\t", file=output
            )
            # TSD project	Transfer type (link/sleipnir)	Date transfer complete	Transfer by person
            print(
                data['TSD project ID'],
                "link",
                "TRANSFER_DATE",
                sep="\t", end="\t", file=output
            )
        print(
            "NSC_USER",
            sep="\t", end="\n", file=output
        )
