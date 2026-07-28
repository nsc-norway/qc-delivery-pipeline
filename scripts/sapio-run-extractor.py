import argparse
import os
import sys
import requests
import xml.etree.ElementTree as ET
import yaml

# Sapio Run Extractor
# usage: python sapio-run-extractor.py runinfo_path [--output-yaml-path OUTPUT] [--sapio-api-token TOKEN]

# The purpose of this script is to gather information about the project and samples in this run, and potentially
# run-specific details, and store it in a YAML file. (The script is not intended to extract run details that are
# already easily available in the run's xml and InterOp files)

def get_flowcell_id(runinfo_path):
    # Parse the XML to find the Flowcell ID
    tree = ET.parse(runinfo_path)
    root = tree.getroot()
    fcid_elem = root.find(".//Flowcell")
    if fcid_elem is None or not fcid_elem.text:
        raise ValueError(f"Flowcell ID not found in RunInfo.xml at {runinfo_path}")
    return fcid_elem.text.strip()


def get_sapio_child_record_fields(sapio_url_base, sapio_headers, record_id, child_type_name):
    response = requests.get(
        f"{sapio_url_base}/webservice/api/datarecord/children",
        headers=sapio_headers,
        params={"recordId": record_id, "childTypeName": child_type_name},
    )
    response.raise_for_status()
    child_records = response.json().get("resultList", [])
    if not child_records:
        return {}
    return child_records[0].get("fields", {})


def get_sapio_project_forms(sapio_url_base, sapio_headers, record_id):
    return {
        form_name: get_sapio_child_record_fields(
            sapio_url_base,
            sapio_headers,
            record_id,
            child_type_name,
        )
        for form_name, child_type_name in {
            "evaluation_form": "ProjectEvaluationForm",
            "submission_form": "ProjectSubmissionForm",
        }.items()
    }


def get_sapio_lane_projects(sapio_url_base, sapio_headers, lane_record_id):
    # Get all Project ancestors of this lane and add them to the results
    r = requests.get(
        f"{sapio_url_base}/webservice/api/datarecord/ancestors",
        headers=sapio_headers,
        params={"recordId": lane_record_id, "ancestorTypeName": "Project"},
    )
    r.raise_for_status()
    result_project_list = []
    for ancestor in r.json().get("resultList", []):
        record_id = ancestor["recordId"]
        result_project_list.append(
            {
                "record_id": record_id,
                "fields": ancestor["fields"],
                **get_sapio_project_forms(sapio_url_base, sapio_headers, record_id),
            }
        )
    return result_project_list


def get_sapio_flowcell_projects(sapio_url_base, sapio_headers, fcid):
    r = requests.post(
        f"{sapio_url_base}/webservice/api/datarecordmanager/querydatarecords",
        headers=sapio_headers,
        params={"dataTypeName": "FlowCellLane", "dataFieldName": "FlowcellId"},
        json=[fcid],
    )
    r.raise_for_status()
    lane_list = r.json().get("resultList", [])
    projects = {}
    for lane in lane_list:
        lane_id = lane["recordId"]
        for project in get_sapio_lane_projects(sapio_url_base, sapio_headers, lane_id):
            project_name = project["fields"].get("ProjectName")
            if project_name:
                projects[project_name] = project

    return list(projects.values())


def get_sapio_api_headers(app_key, api_token):
    return {
        "X-APP-KEY": app_key,
        "X-API-TOKEN": api_token,
    }


def get_sapio_details_for_run(sapio_url_base, sapio_app_key, sapio_api_token, runinfo_path):
    fcid = get_flowcell_id(runinfo_path)

    sapio_headers = get_sapio_api_headers(sapio_app_key, sapio_api_token)
    projects = get_sapio_flowcell_projects(sapio_url_base, sapio_headers, fcid)

    return {
        'run': { # Placeholder for potetial future run information from Sapio.
            'flowcell_id': fcid,
        },
        'projects': projects,
        'samples': [], # Placeholder for potential future sample information from Sapio.
    }


def main(
    runinfo_path,
    output_yaml_file,
    sapio_url_base=None,
    sapio_app_key=None,
    sapio_api_token=None,
):
    sapio_details = get_sapio_details_for_run(sapio_url_base, sapio_app_key, sapio_api_token, runinfo_path)
    output_yaml_file.write(yaml.safe_dump(sapio_details, sort_keys=False))


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Extract details from Sapio for a run."
    )
    parser.add_argument(
        "runinfo_path",
        help="Path to the run's RunInfo.xml file, used to identify the run in Sapio.",
    )
    parser.add_argument(
        "--output-yaml-file",
        type=argparse.FileType("w"),
        default=sys.stdout,
        help="Write YAML output to this file. Defaults to stdout when omitted.",
    )
    parser.add_argument(
        "--sapio-url-base",
        default=os.environ.get("SAPIO_URL_BASE"),
        help="Sapio base URL (defaults to SAPIO_URL_BASE env).",
    )
    parser.add_argument(
        "--sapio-app-key",
        default=os.environ.get("SAPIO_APP_KEY"),
        help="Sapio application GUID (defaults to SAPIO_APP_KEY env).",
    )
    parser.add_argument(
        "--sapio-api-token",
        default=os.environ.get("SAPIO_API_TOKEN"),
        help="Sapio API token (defaults to SAPIO_API_TOKEN env).",
    )
    args = parser.parse_args(argv)

    missing = []
    if not args.sapio_url_base:
        missing.append("--sapio-url-base or SAPIO_URL_BASE")
    if not args.sapio_app_key:
        missing.append("--sapio-app-key or SAPIO_APP_KEY")
    if not args.sapio_api_token:
        missing.append("--sapio-api-token or SAPIO_API_TOKEN")
    if missing:
        parser.error(
            "Sapio connection details are required: provide " + ", ".join(missing)
        )

    return args


if __name__ == "__main__":
    args = parse_args()
    main(
        args.runinfo_path,
        output_yaml_file=args.output_yaml_file,
        sapio_url_base=args.sapio_url_base,
        sapio_app_key=args.sapio_app_key,
        sapio_api_token=args.sapio_api_token,
    )
