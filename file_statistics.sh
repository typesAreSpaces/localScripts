#!/bin/bash

# Specify the root directory of your project
project_dir=$1

# Use find to locate all files in the project
files=$(find "$project_dir" -type f)

# Use awk to extract the file extensions and count occurrences
extensions=$(echo "$files" | awk -F'.' '{print $NF}' | sort | uniq -c)

# Display the statistics
echo "File Extension Statistics:"
echo "--------------------------"
echo "$extensions" | awk '{printf "%-10s : %s\n", $2, $1}'
