import argparse
import base64
import json
import os
import sys
import xml.etree.ElementTree as ET
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

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


def sapio_request(url, headers, auth, params=None, json_body=None):
    if params:
        url = f"{url}?{urlencode(params)}"

    request_headers = dict(headers)
    data = None
    if auth:
        username, password = auth
        credentials = f"{username}:{password}".encode("utf-8")
        request_headers["Authorization"] = (
            f"Basic {base64.b64encode(credentials).decode('ascii')}"
        )
    if json_body is not None:
        data = json.dumps(json_body).encode("utf-8")
        request_headers["Content-Type"] = "application/json"

    request = Request(url, data=data, headers=request_headers)
    try:
        with urlopen(request) as response:
            return json.load(response)
    except HTTPError as error:
        message = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Sapio API request failed ({error.code}): {message}") from error


def get_department_name_of_project(sapio_url_base, sapio_headers, sapio_auth, record_id):
    response = sapio_request(
        f"{sapio_url_base}/webservice/api/datarecord/parents",
        sapio_headers,
        sapio_auth,
        {"recordId": record_id, "parentTypeName": "VeloxDepartment"},
    )
    parent_records = response.get("resultList", [])
    if not parent_records:
        return "Unknown"
    return parent_records[0].get("fields", {}).get("DepartmentName", "Unknown")


def get_sapio_child_record_fields(sapio_url_base, sapio_headers, sapio_auth, record_id, child_type_name):
    response = sapio_request(
        f"{sapio_url_base}/webservice/api/datarecord/children",
        sapio_headers,
        sapio_auth,
        {"recordId": record_id, "childTypeName": child_type_name},
    )
    child_records = response.get("resultList", [])
    if not child_records:
        return {}
    return child_records[0].get("fields", {})


def get_sapio_project_forms(sapio_url_base, sapio_headers, sapio_auth, record_id):
    return {
        form_name: get_sapio_child_record_fields(
            sapio_url_base,
            sapio_headers,
            sapio_auth,
            record_id,
            child_type_name,
        )
        for form_name, child_type_name in {
            "evaluation_form": "ProjectEvaluationForm",
            "submission_form": "ProjectSubmissionForm",
        }.items()
    }


def get_sapio_lane_projects(sapio_url_base, sapio_headers, sapio_auth, lane_record_id):
    # Get all Project ancestors of this lane and add them to the results
    response = sapio_request(
        f"{sapio_url_base}/webservice/api/datarecord/ancestors",
        sapio_headers,
        sapio_auth,
        {"recordId": lane_record_id, "ancestorTypeName": "Project"},
    )
    result_project_list = []
    for ancestor in response.get("resultList", []):
        record_id = ancestor["recordId"]
        result_project_list.append(
            {
                "record_id": record_id,
                "department": get_department_name_of_project(sapio_url_base, sapio_headers, sapio_auth, record_id),
                "fields": ancestor["fields"],
                **get_sapio_project_forms(sapio_url_base, sapio_headers, sapio_auth, record_id),
            }
        )
    return result_project_list


def get_sapio_flowcell_projects(sapio_url_base, sapio_headers, sapio_auth, fcid):
    response = sapio_request(
        f"{sapio_url_base}/webservice/api/datarecordmanager/querydatarecords",
        sapio_headers,
        sapio_auth,
        {"dataTypeName": "FlowCellLane", "dataFieldName": "FlowcellId"},
        [fcid],
    )
    lane_list = response.get("resultList", [])
    projects = {}
    for lane in lane_list:
        lane_id = lane["recordId"]
        for project in get_sapio_lane_projects(sapio_url_base, sapio_headers, sapio_auth, lane_id):
            project_name = project["fields"].get("ProjectName")
            if project_name:
                projects[project_name] = project

    return list(projects.values())


def get_sapio_api_headers(app_key, api_token):
    headers = {}
    if app_key:
        headers["X-APP-KEY"] = app_key
    if api_token:
        headers["X-API-TOKEN"] = api_token
    return headers


def get_sapio_details_for_run(
    sapio_url_base,
    sapio_app_key,
    sapio_api_token,
    sapio_username,
    sapio_password,
    runinfo_path,
):
    fcid = get_flowcell_id(runinfo_path)

    sapio_headers = get_sapio_api_headers(sapio_app_key, sapio_api_token)
    sapio_auth = None if sapio_api_token else (sapio_username, sapio_password)
    projects = get_sapio_flowcell_projects(sapio_url_base, sapio_headers, sapio_auth, fcid)

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
    sapio_username=None,
    sapio_password=None,
):
    sapio_details = get_sapio_details_for_run(
        sapio_url_base,
        sapio_app_key,
        sapio_api_token,
        sapio_username,
        sapio_password,
        runinfo_path,
    )
    json.dump(sapio_details, output_yaml_file, indent=2, ensure_ascii=False)
    output_yaml_file.write("\n")


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
    parser.add_argument(
        "--sapio-username",
        default=os.environ.get("SAPIO_USERNAME"),
        help="Sapio username (defaults to SAPIO_USERNAME env).",
    )
    parser.add_argument(
        "--sapio-password",
        default=os.environ.get("SAPIO_PASSWORD"),
        help="Sapio password (defaults to SAPIO_PASSWORD env).",
    )
    args = parser.parse_args(argv)

    missing = []
    if not args.sapio_url_base:
        missing.append("--sapio-url-base or SAPIO_URL_BASE")
    if not (args.sapio_api_token or (args.sapio_username and args.sapio_password)):
        missing.append(
            "--sapio-api-token or SAPIO_API_TOKEN, or both --sapio-username and "
            "--sapio-password (SAPIO_USERNAME and SAPIO_PASSWORD)"
        )
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
        sapio_username=args.sapio_username,
        sapio_password=args.sapio_password,
    )
