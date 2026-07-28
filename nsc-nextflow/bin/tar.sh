#!/usr/bin/env bash
set -euo pipefail

runfolder=$1
project_dir_name=$2
delivery_location=$3
username_file=$4
htpasswd_file=$5
delivery_project_folder="${delivery_location}/${project_dir_name}"

if [[ "$username_file" != /* ]]; then
    username_file="$PWD/$username_file"
fi
if [[ "$htpasswd_file" != /* ]]; then
    htpasswd_file="$PWD/$htpasswd_file"
fi

cd "$runfolder"
tar -cvf "${project_dir_name}.tar" "$project_dir_name"
md5sum "${project_dir_name}.tar" > "${project_dir_name}.tar.md5"
mkdir "$delivery_project_folder"
mv "${project_dir_name}.tar" "${project_dir_name}.tar.md5" "$delivery_project_folder"

username=$(head -n 1 "$username_file")

echo "$username"

# Write .htaccess file
cat <<EOL > "$delivery_project_folder/.htaccess"
AuthUserFile /data/$project_dir_name/.htpasswd
AuthGroupFile /dev/null
AuthName ByPassword
AuthType Basic

<Limit GET>
require user $username
</Limit>
EOL
#

# Copy .htpasswd file
cp "$htpasswd_file" "$delivery_project_folder/.htpasswd"
#
