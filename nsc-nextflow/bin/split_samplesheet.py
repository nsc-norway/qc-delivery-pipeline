#!/usr/bin/env python3

import sys

input = sys.argv[1]

p_list = []
for line in open(input, 'r'):
    if 'ProjectName' not in line:
        p_list.append(line.split(',')[3])

project_list = set(p_list)

for project in project_list:
    out_file = open(project + '_' + input, 'w')
    for line in open(input, 'r'):
        if 'ProjectName' in line:
            out_file.write(line)
        elif project in line:
            out_file.write(line)
    out_file.close()