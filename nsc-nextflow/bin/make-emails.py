#!/usr/bin/env python

import sys
import os
import io
import re
import stat
import logging
from math import ceil
from pathlib import Path
import argparse
from xml.etree.ElementTree import ElementTree
import yaml
from jinja2 import Environment, FileSystemLoader, select_autoescape
import pandas as pd
from interop import py_interop_run_metrics, py_interop_run, py_interop_summary


def main(): 

    # Generate summary email based on demultiplexing stats
    parser = argparse.ArgumentParser(description="Make summary email")
    parser.add_argument('--run-dir', default=".",
                        help="Path to run folder with SAV files (RunParameters.xml, RunInfo.xml, InterOp).")

    parser.add_argument('--demultiplex-stats', type=open, help="Demultiplex stats (used for read counts).")

    parser.add_argument('--suprdupr-dir',
                        help="Directory containing duplicate count files for each (Lane, Sample) as [Sample_ID]_L00[Lane]_suprDUPr.txt.")

    parser.add_argument('--bclconvert-version', default="4.1.23", help="Specify BCL Convert version (TODO automate).")

    parser.add_argument('--pipeline-version', default="dev", help="Provide the NSC QC pipeline version as a string.")

    parser.add_argument('--output-email-dir', default=".", help="Output directory for email automation file and email "
                                        "content files (in subdir email_content, which will be created).")

    parser.add_argument('--create-summary', action='store_true', help="Enable HTML summary email creation.")

    parser.add_argument('--create-project-email', type=str, help="Create project email for the specified project.")

    parser.add_argument('--nird-username', type=str, help="NIRD username for the project.")

    parser.add_argument('--nird-password-file', type=open, help="File containing NIRD password for the project.")

    parser.add_argument('sapio_file', type=open, nargs='?', help="Input YAML file with project Sapio LIMS information.")
    

    # Prepare input data
    args = parser.parse_args()

    # Init template system with the script's directory as the template dir
    jinja_env = Environment(loader=FileSystemLoader(os.path.dirname(__file__)),
            autoescape=select_autoescape(['html','xml']))
    # Export the zip function so it can be used in templates
    jinja_env.globals.update(zip=zip)

    # Get sample-level information
    demultiplex_stats, undetermined_stats = get_demux_stats_and_sample_info(
        args.demultiplex_stats
        )

    run_dir = Path(args.run_dir)
    assert run_dir.is_dir(), "Run dir must exist"

    # Construct run parameters objects, parsing RunParameters file
    run_parameters = RunParameters(run_dir / "RunParameters.xml")

    # Add duplicate count column if duplicate metrics are available. The downstream processes will
    # check for the existence of the column.
    if args.suprdupr_dir:
        non_undetermined = demultiplex_stats[demultiplex_stats['SampleID'] != "Undetermined"]
        # Pushing data back to the original DataFrame should work, because the merging is done on the
        # index.
        demultiplex_stats['suprDUPr_duplicate_count'] = get_suprDUPr_duplicates(non_undetermined, Path(args.suprdupr_dir))

    if args.sapio_file:
        sapio_data = yaml.safe_load(args.sapio_file)
    else:
        sapio_data = {'projects': []}


    # List of tuples of (SoftwareName, SoftwareVersion)
    software_versions = [
        (run_parameters.system_suite_name, run_parameters.system_suite_version),
        ("BCL Convert", args.bclconvert_version),
        ("NSC scripts", args.pipeline_version)
    ]

    output_email_dir = Path(args.output_email_dir)
    output_email_dir.mkdir(parents=True, exist_ok=True)

    email_list = []
    # Email list automation text files: pipe-separated values. Contains the following fields.
    # - format (html/text)
    # - to
    # - cc
    # - bcc
    # - subject
    # - content file path
    # - attachment file path
    automation_email_files = []
    if args.create_summary:
        # Summary file for email content

        # Get list of unique projects
        projects = demultiplex_stats['Sample_Project'].unique()

        # Get project information
        project_datas = [
            get_project_data(project, sapio_data['projects'], demultiplex_stats, run_parameters.run_id)
            for project in projects
        ]

        # Lane-specific information from InterOp and from sample metrics
        lane_table_headers, lane_table_classes, lane_table_data = get_lane_summary_data(run_dir, demultiplex_stats, undetermined_stats)
        
        summary_file_name = ("Summary_for_" + run_parameters.run_id + ".html")
        summary_content_path = output_email_dir / summary_file_name
        with open(summary_content_path, 'w') as out:
            doc_content = jinja_env.get_template('run_summary.html.j2').render(
                                    lane_header=lane_table_headers, lane_classes=lane_table_classes,
                                    lane_data=lane_table_data, run_parameters=run_parameters,
                                    software_versions=software_versions, project_datas=project_datas
                                    )
            out.write(doc_content)
        automation_txt_filename = f"automatic_email_list-run.txt"
        with open(output_email_dir / automation_txt_filename, 'w') as of:
            of.write("|".join([
                "html", '"nsc-ous-data-delivery@sequencing.uio.no" <nsc-ous-data-delivery@sequencing.uio.no>', "", "", 
                f"Summary for run {run_parameters.run_id}",
                f"email_content/{summary_file_name}", ""
            ]) + "\n")
        automation_email_files.append(automation_txt_filename)
    
    # Make project emails
    if args.create_project_email:
        project_data = get_project_data(args.create_project_email, sapio_data['projects'], demultiplex_stats, run_parameters.run_id)
        if args.nird_username:
            project_data['nird_username'] = args.nird_username
        if args.nird_password_file:
            project_data['nird_password'] = args.nird_password_file.read().strip()
        if project_data.get('Classification') != "Diagnostics":
            project_email_filename = (project_data['dir_name'] + ".txt")
            with open(output_email_dir / project_email_filename, 'w') as out:
                size = None
                doc_content = jinja_env.get_template('project_email.txt.j2').render(
                    project_data=project_data,
                    size=size,
                    run_parameters=run_parameters,
                    software_versions=software_versions
                    )
                out.write(doc_content)

            email_list.append("|".join([
                    "text", project_data.get('ContactEmail', "CONTACT_EMAIL"), "",
                    '"nsc-ous-data-delivery@sequencing.uio.no" <nsc-ous-data-delivery@sequencing.uio.no>',
                    f"Sequence ready for download - sequencing run {run_parameters.run_id} - {project_data['ProjectName']} ({project_data['number_of_samples']} samples)",
                    f"{project_email_filename}",
                    "" # No MultiQC attachment, because they are too big
                ]))
            automation_txt_filename = f"automatic_email_list-{project_data['dir_name']}.txt"
            with open(output_email_dir / automation_txt_filename, 'w') as of:
                of.write("|".join([
                        "text", project_data.get('ContactEmail', "CONTACT_EMAIL"), "",
                        '"nsc-ous-data-delivery@sequencing.uio.no" <nsc-ous-data-delivery@sequencing.uio.no>',
                        f"Sequence ready for download - sequencing run {run_parameters.run_id} - {project_data['ProjectName']} ({project_data['number_of_samples']} samples)",
                        f"{project_email_filename}",
                        "" # No MultiQC attachment, because they are too big
                    ])+ "\n")
            automation_email_files.append(automation_txt_filename)

    command_file_path = output_email_dir / "Open_emails.command"
    with open(command_file_path, 'w') as of:
        of.write("""#!/bin/bash

# This shell script is written to the Delivery folder in
# all runs processed by the demultiplexing scripts. It calls the AppleScript file
# "Open Emails.scpt", which is located in /data/runScratch.boston/scripts.

SCRIPT_DIR=$( dirname "$0" )
cd "$SCRIPT_DIR"
for list_file in automatic_email_list-*.txt
do
    osascript /Volumes/runScratch/scripts/Open\ Emails.scpt "$SCRIPT_DIR" "$list_file"
done
""")

    # Make it executable
    command_file_path.chmod(command_file_path.stat().st_mode | stat.S_IEXEC)
    

def get_demux_stats_and_sample_info(demultiplex_stats_file):
    """Get the Demultiplex_Stats.csv information and ensure that the ProjectName is available

    Undetermined will be removed

    Also returns a dataframe with just undetermined.
    """

    # Enforce string data type for Sample ID. It may not be necessary, but keeps things tidy.
    demultiplex_stats = pd.read_csv(demultiplex_stats_file, dtype={'SampleID': str})

    demultiplex_stats['OriginalSampleID'] = demultiplex_stats['SampleID']
    if 'Sample_Project' not in demultiplex_stats.columns:
        # Decompose the sample ID into ProjectName and sample ID
        demultiplex_stats['Sample_Project'] = demultiplex_stats.OriginalSampleID.str.split("_", expand=True)[0]
        demultiplex_stats['SampleID'] = demultiplex_stats.OriginalSampleID.str.split("_", expand=True, n=1)[1]
        # Determine if all remaining sample IDs contain a UUID as the last _-separated part, and if so, strip it.
        uuid_pattern = re.compile(r'_[0-9a-fA-F-]{36}$')
        sample_ids = demultiplex_stats.loc[
            demultiplex_stats['OriginalSampleID'] != "Undetermined", 'SampleID'
        ]
        all_have_uuid = sample_ids.apply(
            lambda sample_id: isinstance(sample_id, str) and bool(uuid_pattern.search(sample_id))
        ).all()
        if all_have_uuid:
            demultiplex_stats['SampleID'] = demultiplex_stats['SampleID'].str.replace(uuid_pattern, '', regex=True)

    # Ensure integer type - required for correct format in the project email
    demultiplex_stats['# Reads'] = demultiplex_stats['# Reads'].astype(int)

    undetermined = demultiplex_stats[demultiplex_stats.OriginalSampleID == "Undetermined"]
    demultiplex_stats = demultiplex_stats[demultiplex_stats.OriginalSampleID != "Undetermined"]

    return demultiplex_stats, undetermined


def get_sample_suprDUPr(suprdupr_dir, lane, sample_id):
    suprdupr_path = suprdupr_dir / f"{sample_id}_L{str(lane).zfill(3)}.suprDUPr.txt"
    if not suprdupr_path.exists():
        return pd.NA
    with open(suprdupr_path) as f:
        data = [l.strip().split() for l in f.readlines()]
        assert data[0][0] == "NUM_READS" and data[0][1] == "READS_WITH_DUP", f"suprDUPr file headers {suprdupr_path}"
        if float(data[1][0]) == 0: return float('NaN')
        return float(data[1][1])


def get_suprDUPr_duplicates(demultiplex_stats, suprdupr_dir):
    """
    Return a Series of duplicate counts for the samples given in demultiplex_stats.
    """
    if 'suprDUPr_duplicates' in demultiplex_stats.columns:
        raise ValueError("The specified DataFrame already contains suprDUPr_duplicates.")
    return demultiplex_stats.apply(
        lambda row: get_sample_suprDUPr(suprdupr_dir, row.Lane, row.OriginalSampleID),
        axis=1
    )


def get_lane_summary_data(run_dir, demultiplex_stats, undetermined_stats):
    """Get the summary table with lane metrics.

    run_dir             should be a directory containing the necessary files to use the
                        interop library (InterOp/).
    demultiplex_stats   pandas DataFrame of Demultiplex_Stats.csv file, optionally 
                        containing duplicate counts (suprDUPr_duplicates).
    
    Returns a tuple representing the lane metrics table:
        (HEADERS, CLASSES, [LANE_1_DATA, LANE_2_DATA, ...])
    
    HEADERS is a list of string used as the column headers in the table.
    CLASSES is the CSS classes used for displaying each of the columns (same length as HEADERS)
    The data in the table is represented as a list of rows. Each row, such as LANE_x_DATA, is 
    a list of data values.
    LANE_1_DATA = [
        LANE,
        PROJECT_NAME,
        ...
    ]
    """
    # Load InterOp data
    valid_to_load = py_interop_run.uchar_vector(py_interop_run.MetricCount, 0)
    py_interop_run_metrics.list_summary_metrics_to_load(valid_to_load)
    valid_to_load[py_interop_run.ExtendedTile] = 1
    run_metrics = py_interop_run_metrics.run_metrics()
    run_metrics.read(str(run_dir), valid_to_load)
    summary = py_interop_summary.run_summary()
    py_interop_summary.summarize_run_metrics(run_metrics, summary)

    # Determine how many read phases and lanes
    read_count = summary.size()
    nonindex_reads = [read for read in range(read_count) if not summary.at(read).read().is_index()]
    nonindex_read_count = len(nonindex_reads)
    lane_count = summary.lane_count()

    # Return values for the table structure
    headers, classes = zip(*(
            [("Lane", "center"),
            ("Project", "text"),
            ("PF cluster no", "number"),
            ("PF ratio", "number"),
    #        ("Yield (Gb)", "number"),
            ("SeqDuplicates", "number"),
            ("Undetermined", "number")] + \
             [(f"AlignPhixR{i+1}", "number") for i in range(nonindex_read_count)] + \
             [
            (">=Q30", "number"),
            ("Occupied", "number"),
            ("Informative", "number"),
            ("MaxReadsSam", "number"),
            ("MinReadsSam", "number"),
            ("Quality", "text")
    ]))
    data = []
    for lane_number in demultiplex_stats['Lane'].unique():
        if lane_number > lane_count:
            logging.error(f"Error: Lane {lane_number} is not present in InterOp data.")
            continue

        # Filter demultiplexing stats for this lane. The data frame already excludes undetermined,
        # by the inner join when merging with sample sheet.
        lane_demultiplex_stats = demultiplex_stats[demultiplex_stats.Lane==lane_number]

        # Compute the total number of reads in the lane, used for several data below.
        total_sample_reads = lane_demultiplex_stats['# Reads'].sum()

        # Get InterOp metrics for this lane (per read1, read2, ...)
        lane_index = int(lane_number - 1)
        read_1_interop = summary.at(0).at(lane_index)

        # Lane
        row_data = [str(lane_number)]

        # Project
        lane_proejcts = lane_demultiplex_stats.Sample_Project.unique()
        row_data.append(",".join(lane_proejcts))

        # PF cluster no
        # (PF related metrics are always the same for read1, read2, ...)
        pf_reads = read_1_interop.reads_pf()
        # Verify read count is equal in demultiplexing and InterOp.
        total_reads = total_sample_reads + undetermined_stats.loc[undetermined_stats.Lane==lane_number, '# Reads'].sum()
        if pf_reads != total_reads:
            raise RuntimeError("Demultiplex_Stats reads is different from the PF clusters in InterOp for lane "
                               f"{lane_number}: {total_reads} != {pf_reads}.")
        row_data.append(f"{pf_reads:,}")

        # PF ratio
        row_data.append(f"{read_1_interop.percent_pf().mean():.1f} %")

        # PF yield
        #yield_sum = sum(summary.at(read).at(lane_index).yield_g() for read in range(read_count))
        #row_data.append(f"{yield_sum:.0f}")

        # SeqDuplicates

        # Informative
        if 'suprDUPr_duplicate_count' in lane_demultiplex_stats.columns:
            dup_ratio = lane_demultiplex_stats['suprDUPr_duplicate_count'].sum() / max(total_sample_reads,1)
            row_data.append(f"{100 * dup_ratio:.2f} %")
        else:
            row_data.append("-")

        # Undetermined
        undetermined_sample = undetermined_stats.loc[undetermined_stats.Lane==lane_number, '% Reads']
        if undetermined_sample.empty:
            undetermined_ratio = 0 # Used below for informative clusters
            row_data.append("-")
        elif len(undetermined_sample) == 1:
            undetermined_ratio = undetermined_sample.iloc[0] # Used below for informative clusters
            row_data.append(f"{100 * undetermined_ratio:.2f} %")
        else:
            raise RuntimeError(f"Multiple undetermined samples found in lane {lane_number}.")

        # AlignedPhiX
        for read in nonindex_reads:
            aligned_phix = summary.at(read).at(lane_index).percent_aligned().mean()
            row_data.append(f"{aligned_phix:.2f} %")

        # Q30% needs to be computed as a total for all the data reads. There doesn't seem to be an easy way
        # to get the Q30 yield for a specific lane, which would be the natural way to do this.
        # Instead we get the Q30 % for each read. The Q30 reported by the interop library does not include the last
        # cycle, which is okay. We compute the average Q30% weighted by the number of cycles in each read,
        # to get the overall Q30% for all data in the lane.
        cycle_weighted_q30ratio_sum = 0
        cycle_count = 0
        for read in nonindex_reads:
            read_cycles = summary.at(read).read().useable_cycles()
            cycle_count += read_cycles
            cycle_weighted_q30ratio_sum += (read_cycles * summary.at(read).at(lane_index).percent_gt_q30() / 100)
        q30pct = 100 * cycle_weighted_q30ratio_sum / max(cycle_count, 1)
        row_data.append(f"{q30pct:.2f} %")

        # Occupied
        # Same for all read passes, so we use read 1
        row_data.append(f"{read_1_interop.percent_occupied().median():.2f} %")

        # Informative
        if 'suprDUPr_duplicate_count' in lane_demultiplex_stats.columns:
            informative_clusters_pct = (1 - undetermined_ratio) * (1 - dup_ratio) * read_1_interop.percent_pf().mean()
            row_data.append(f"{informative_clusters_pct:.2f} %")
        else:
            row_data.append("-")

        # For relative read count stats, we first compute the mean reads per sample in the lane
        mean_reads = lane_demultiplex_stats['# Reads'].mean()
        # Take max of 1, to avoid divide by zero in case of pretty bad lanes / high undetermined
        divisor_mean_reads = max(1, mean_reads)

        # MaxReadsSam
        max_reads = lane_demultiplex_stats['# Reads'].max()
        row_data.append("%+3.1f%%" % ((max_reads - mean_reads) * 100.0 / divisor_mean_reads))

        # MinReadsSam
        min_reads = lane_demultiplex_stats['# Reads'].min()
        row_data.append("%+3.1f%%" % ((min_reads - mean_reads) * 100.0 / divisor_mean_reads))

        # Quality
        row_data.append("ok")


        data.append(row_data)

    return headers, classes, data


class RunParameters:
    """Get run parameters from xml file and store them in instance variables of this
    class. (This is a class because it was like that in the old email script.)
    
    instrument_type, instrument_id, instrument_name: Example:
        NovaSeq X, LH00534, Nox

    run_mode_field, run_mode_value: Contains the flow cell type for NovaSeqX
        Flow Cell Type,B25
    
    cycles: Contains a list of tuples. Each tuple represent a read phase.
        [("R1", 151), ("R2", 151)]
    """

    def __init__(self, run_parameters_path):

        rp_tree = ElementTree()
        rp_tree.parse(run_parameters_path)

        # Simple parameters
        self.run_id =               rp_tree.findtext("RunId")
        if not self.run_id:
            raise ValueError("Required tag RunId is not available or blank in RunParameters.xml.")
        self.instrument_type =      rp_tree.findtext("InstrumentType")
        self.instrument_id =        rp_tree.findtext("InstrumentSerialNumber")
        self.system_suite_version=  rp_tree.findtext("SystemSuiteVersion")
        if self.instrument_type:
            self.system_suite_name = f"{self.instrument_type.split()[0]} System Suite"
        else:
            self.system_suite_name = "System Suite"

        # The flow cell type is recorded in some simple variables, but the name
        # is unusual. We use the ConsumableInfo value, because it's exactly the normal
        # user-facing name 25B etc.
        for consumable_info in rp_tree.findall("ConsumableInfo/ConsumableInfo"):
            if consumable_info.find("Type").text == "FlowCell":
                self.run_mode_field = "Flow Cell Type"
                self.run_mode_value = consumable_info.find("Name").text

        # Cycles
        self.cycles = []
        for read in rp_tree.findall("PlannedReads/Read"):
            read_name = read.attrib['ReadName']
            # ReadName is "Read1", ... - change it to "R1"
            self.cycles.append((read_name[0] + read_name[-1], read.attrib['Cycles']))


def get_project_data(project_name, sapio_projects, demultiplex_stats, run_id):
    """Load information about a project into a dict object.
    
    Project details from LIMS are added if available in the sapio_projects dict. The ProjectName is used to
    look up the project. All fields from the project, evaluation form and submission form are added to the dict.

    It gathers the number of fragments in each of the samples from demultiplex_stats.
    Samples run on multiple lanes are reported once for each lane.
    For each sample, it writes a tuple of the sample name, the number of fragments, and the
    relative difference from the mean number of reads (see below).

    sample_fragments_table = [("Sample1_L001", 100000, -0.09), ("Sample1_L002", 120000, 0.09), ...]

    The relative difference is: (frags - mean_frags) / mean_frags

    ADDED KEYS:

    dir_name                NSC project directory name
    sample_fragments_table  See above
    number_of_samples

    """

    result = {}
    sapio_project = next((p for p in sapio_projects if p['fields']['ProjectName'] == project_name), None)
    if sapio_project:
        result.update(sapio_project['fields'])
        if 'evaluation_form' in sapio_project and sapio_project['evaluation_form']:
            result.update(sapio_project['evaluation_form'])
        if 'submission_form' in sapio_project and sapio_project['submission_form']:
            result.update(sapio_project['submission_form'])
    else:
        result['ProjectName'] = project_name
        result['ContactEmail'] = ""

    result['dir_name'] = get_nsc_project_name(run_id, result['ProjectName'])
    assert all(c.isalnum() or c in '-_.' for c in result['dir_name']), "Project directory should only contain safe characters."
    
    sample_list = demultiplex_stats[demultiplex_stats.Sample_Project==result['ProjectName']].copy()
    mean_frags = sample_list['# Reads'].mean()
    sample_list['RelativeDifference'] = (sample_list['# Reads'] - mean_frags) / mean_frags
    
    # Add Sample_Lane display name
    sample_list['SampleDisplayName'] = (sample_list['SampleID'] + "_L") + sample_list['Lane'].astype(str).str.zfill(3)

    result['sample_fragments_table'] = [
        (row.SampleDisplayName, row['# Reads'], row.RelativeDifference)
        for _, row in sample_list.iterrows()
    ]

    result['number_of_samples'] = sample_list.SampleID.nunique()

    return result


def get_nsc_project_name(run_id, project_name):
    run_id_parts = run_id.split("_")
    if len(run_id_parts) < 3 or not run_id_parts[-1]:
        raise ValueError(f"Invalid run ID {run_id}.")
    return run_id_parts[0][-6:] + "_" + run_id_parts[1] + "." + run_id_parts[-1][0] + ".Project_" + project_name


def get_data_size(bc_dir, project):
    """She's got better data size?"""

    size = 0
    for sample in project.samples:
        for file in sample.files:
            if not file.empty:
                size += os.path.getsize(os.path.join(bc_dir, file.path))
    return size

if __name__ == "__main__":
    main()

