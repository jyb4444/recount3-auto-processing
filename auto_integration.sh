#!/bin/bash

# Set to exit immediately if any command exits with a non-zero status
set -e

# Check if exactly three arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <project_id> <sample_id> <working_directory>"
    exit 1
fi

# Assign input arguments to descriptive variables
# The original working directory will be stored in this variable
project_id="$1"
sample_id="$2"
working_directory="$3" # This is the original working directory

# Check if the working_directory path ends with '/' using regex matching
if [[ "${working_directory}" =~ .*/$ ]]; then
    echo "Warning: The working_directory path ends with '/'. It's recommended to omit the trailing slash."
    # Optional: Automatically remove the trailing slash for consistency
    working_directory="${working_directory%/}"
fi

# Define the expected final result directory path
expected_final_output_dir="${working_directory}/final_output"
# Define the expected final result filename pattern (decompressed file without .gz suffix)
expected_output_file_pattern="*gene_sums.${project_id}.M023*"

# >>> Check for existing results (Prevent redundant runs) <<<
# Check for existing results matching the pattern in the expected final output directory.
# This logic handles cases where the directory doesn't exist or is empty by default.
echo "Checking for existing results matching pattern '${expected_output_file_pattern}' in ${expected_final_output_dir}..."

# 首先，检查预期的最终输出目录是否存在
if [ -d "${expected_final_output_dir}" ]; then
    # 目录存在，现在检查其中的文件
    echo "Final output directory '${expected_final_output_dir}' exists. Checking for result files inside..."

    # 使用 ls 在预期的最终输出目录中查找匹配模式的文件
    # 2>/dev/null 避免在找不到文件时 ls 报错
    found_existing_results=$(ls "${expected_final_output_dir}/${expected_output_file_pattern}" 2>/dev/null)

    # 统计找到的文件的数量
    # 如果 ls 没有找到文件，found_existing_results 变量是空的
    if [ -z "$found_existing_results" ]; then
        existing_file_count=0
    else
        # 统计 ls 输出的行数，即找到的文件数量
        existing_file_count=$(echo "${found_existing_results}" | wc -l)
    fi

    # 如果找到了任何匹配的文件，则认为结果已存在，直接退出
    if [ "$existing_file_count" -gt 0 ]; then
        echo "------------------------------------------------------------"
        echo "Results already found for Project ID: ${project_id}, Sample ID: ${sample_id}"
        echo "Matching file(s):"
        echo "${found_existing_results}"
        echo "Skipping pipeline execution."
        echo "Script finished (results already available)."
        echo "------------------------------------------------------------"
        exit 0 # 找到结果，成功退出
    else
        # 目录存在，但没有找到匹配的文件
        echo "Directory ${expected_final_output_dir} exists, but no existing results found matching pattern '${expected_output_file_pattern}'."
        # 继续执行后续流程
    fi
else
    # 目录不存在
    echo "Expected final output directory '${expected_final_output_dir}' not found."
    # 继续执行后续流程 (这个目录会在后面 Unifier 输出处理部分被创建)
fi


# Ensure the working directory exists, create if necessary
# Ensure the working directory exists, create if necessary (This was also done earlier, but good to ensure here again before putting stuff into it)
mkdir -p "${working_directory}"

# --- Download Section (using SRA Toolkit) ---
# Using fastq-dump from SRA Toolkit to get genuine FASTQ data from SRA
# Note: The previous curl method with the SRA URL may not reliably provide FASTQ,
# and often provides FASTA or fails. fastq-dump is the recommended tool.

# fastq-dump outputs single-end data as ${sample_id}.fastq.gz
# fastq-dump outputs paired-end data as ${sample_id}_1.fastq.gz and ${sample_id}_2.fastq.gz

# Define the expected filename for single-end data
output_file_single="${working_directory}/${sample_id}.fastq.gz"
# Define the expected filename for the first file of paired-end data
output_file_paired_1="${working_directory}/${sample_id}_1.fastq.gz"


echo "Checking for existing FASTQ file(s): ${output_file_single} or ${output_file_paired_1}"

# Check if the target file(s) already exist in the working directory
# Check for the single-end name OR the first paired-end name
if [ -f "${output_file_single}" ] || [ -f "${output_file_paired_1}" ]; then
    echo "Found existing FASTQ file(s). Skipping download."
    # Determine which file(s) to use for pump based on existence
    if [ -f "${output_file_paired_1}" ]; then
        # Paired-end file found, use paired-end names for pump
        pump_fastq_file="${output_file_paired_1}"
        # Assuming _2 exists if _1 does. Add a check if needed for robustness.
        pump_fastq_file2="${working_directory}/${sample_id}_2.fastq.gz"
    else
        # Single-end file found, use single-end name for pump
        pump_fastq_file="${output_file_single}"
        pump_fastq_file2="" # No second file for single-end
    fi
else
    # Files not found, execute fastq-dump
    echo "Existing FASTQ file(s) not found. Using fastq-dump to get FASTQ for Sample ID: ${sample_id}"
    echo "Output files will be created in: ${working_directory}"

    # Use fastq-dump to download and convert to fastq.gz format
    # --gzip: compress output to .gz
    # -O "${working_directory}": specify output directory
    # --skip-technical, --readids, --read_filter pass: common recommended parameters
    # set -e ensures the script exits if fastq-dump fails
    echo "Running fastq-dump for ${sample_id}..."
    # Ensure fastq-dump is in PATH or use full path here (e.g., /path/to/sratoolkit/bin/fastq-dump)
    fastq-dump --gzip "${sample_id}"

    # Check if fastq-dump successfully produced the file(s)
    # Check for single-end name OR the first paired-end name after running fastq-dump
    if [ -f "${output_file_single}" ]; then
        echo "fastq-dump produced single-end file: ${output_file_single}"
        pump_fastq_file="${output_file_single}"
        pump_fastq_file2="" # No second file for single-end
    elif [ -f "${output_file_paired_1}" ]; then
         echo "fastq-dump produced paired-end files starting with ${output_file_paired_1}"
         pump_fastq_file="${output_file_paired_1}"
         pump_fastq_file2="${working_directory}/${sample_id}_2.fastq.gz" # Assume _2 exists if _1 does
         # Add a check for the second paired-end file just to be sure
         if [ ! -f "${pump_fastq_file2}" ]; then
             echo "Error: fastq-dump produced ${output_file_paired_1} but not the expected second paired-end file ${pump_fastq_file2}"
             echo "Check fastq-dump output above for errors."
             exit 1
         fi
    else
        # Neither expected single-end nor paired-end file was found
        echo "Error: fastq-dump did not produce the expected output file(s) for ${sample_id} in ${working_directory}"
        echo "Check fastq-dump output above for errors."
        exit 1
    fi

    echo "FASTQ download/conversion successful."
fi
# --- Get FASTQ Section End ---


# --- Setup: Download References and Singularity Images ---
echo "Starting setup: Downloading/Preparing References and Singularity Images..."

# Define the directory for reference files (in a subdirectory within the working directory)
reference_directory="${working_directory}/monorail_references"
echo "Creating reference directory: ${reference_directory}"
mkdir -p "${reference_directory}"

# Define the directory for Singularity images (working directory itself)
singularity_image_dir="${working_directory}"
echo "Singularity images will be pulled into: ${singularity_image_dir}"


# Pull Singularity images
echo "Pulling recount-pump Singularity image (recount-rs5:1.0.6)..."
singularity pull --dir "${singularity_image_dir}" docker://quay.io/benlangmead/recount-rs5:1.0.6

echo "Pulling recount-unify Singularity image (recount-unify:1.0.4)..."
singularity pull --dir "${singularity_image_dir}" docker://quay.io/broadsword/recount-unify:1.0.4


# Run reference getter scripts
# Needs to first change to the reference file directory
echo "Changing directory to ${reference_directory} to get references..."
# pushd changes to directory and pushes current to stack, > /dev/null hides output
pushd "${reference_directory}" > /dev/null

echo "Running get_mouse_ref_indexes.sh..."
# Use the working_directory variable and script filename to construct the full path and execute
# Ensure get_mouse_ref_indexes.sh is in the provided working_directory and is executable
"${working_directory}/get_mouse_ref_indexes.sh"

echo "Running get_unify_refs.sh grcm38..."
# Use the working_directory variable and script filename to construct the full path and execute
# Ensure get_unify_refs.sh is in the provided working_directory and is executable
"${working_directory}/get_unify_refs.sh" grcm38

# Change back to the previous directory (where the script was before pushd)
echo "Changing back to previous directory..."
# popd returns from directory stack, > /dev/null hides output
popd > /dev/null

echo "Setup complete."
# --- Setup End ---


# --- Execute run_recount_pump.sh Script ---
echo "Calling run_recount_pump.sh with derived parameters..."

# Construct parameters to pass to run_recount_pump.sh
# Parameter 1: Singularity image file path
pump_sif_image="${singularity_image_dir}/recount-rs5_1.0.6.sif" # Assuming .sif file is in the original working directory

# Parameter 2: sample_id
pump_sample_id="${sample_id}"

# Parameter 3: local (fixed value)
# Indicates local input file
pump_param3="local"

# Parameter 4: grcm38 (fixed value)
# Genome version
pump_param4="grcm38"

# Parameter 5: 20 (fixed value)
# Number of CPUs
pump_param5="20"

# Parameter 6: Reference genome index directory path
# Needs to pass the reference index path obtained in the setup step
pump_ref_path="${reference_directory}" # This is the directory created and used in the setup step for references

# Parameter 7: Path to the first FASTQ file
# This variable is set in the "Get FASTQ Section" based on whether single or paired-end was found/downloaded
# pump_fastq_file is already defined correctly above

# Parameter 8: Path to the second FASTQ file (for paired-end)
# This variable is set in the "Get FASTQ Section" based on whether single or paired-end was found/downloaded.
# It will be "" for single-end data.
# pump_fastq_file2 is already defined correctly above

# Parameter 9: project_id
pump_project_id="${project_id}"

# Check if the FASTQ files required by run_recount_pump.sh exist (sanity check before calling)
# This check is mostly covered in the download section, but a quick final check is harmless.
if [ "${pump_param3}" == "local" ]; then
    if [ ! -f "${pump_fastq_file}" ]; then
        echo "Error: Required first local input file not found before calling pump: ${pump_fastq_file}"
        exit 1
    fi
    # If pump_fastq_file2 is set (i.e., it's paired-end), check if it exists
    if [ -n "${pump_fastq_file2}" ]; then
        if [ ! -f "${pump_fastq_file2}" ]; then
             echo "Error: Required second local input file not found before calling pump: ${pump_fastq_file2}"
             exit 1
        fi
    fi
fi


echo "Constructing command for run_recount_pump.sh..."
# Construct the complete command string, including parameters and quotes
pump_command_to_print="/bin/bash run_recount_pump.sh"
pump_command_to_print+=" \"${pump_sif_image}\""
pump_command_to_print+=" \"${pump_sample_id}\""
pump_command_to_print+=" \"${pump_param3}\""
pump_command_to_print+=" \"${pump_param4}\""
pump_command_to_print+=" \"${pump_param5}\""
pump_command_to_print+=" \"${pump_ref_path}\"" # Use the reference path variable
pump_command_to_print+=" \"${pump_fastq_file}\""
# Only add pump_fastq_file2 to the command string if it's defined (i.e., for paired-end)
if [ -n "${pump_fastq_file2}" ]; then
    pump_command_to_print+=" \"${pump_fastq_file2}\""
fi
pump_command_to_print+=" \"${pump_project_id}\""

echo "The exact command being executed is:"
echo "${pump_command_to_print}"
echo "------------------------------------------------------------"


# Execute run_recount_pump.sh script
# set -e ensures the script exits if run_recount_pump.sh fails
# Ensure run_recount_pump.sh has execute permissions and is in PATH or use full path.
# Or you need to provide its full path.
/bin/bash run_recount_pump.sh \
    "${pump_sif_image}" \
    "${pump_sample_id}" \
    "${pump_param3}" \
    "${pump_param4}" \
    "${pump_param5}" \
    "${pump_ref_path}" \ # Use the reference path variable
    "${pump_fastq_file}" \
    "${pump_fastq_file2}" \ # This parameter is passed only if pump_fastq_file2 is set
    "${pump_project_id}"

echo "run_recount_pump.sh executed successfully."


# --- Unifier Section ---
echo "Starting Unifier steps..."

# 1. Create Unifier's working directory
unify_working_dir="${working_directory}/unify_working"
echo "Creating Unifier working directory: ${unify_working_dir}"
# -p flag creates parent directories if they don't exist
mkdir -p "${unify_working_dir}"
echo "Unifier working directory created: ${unify_working_dir}"

# 2. Create sample_metadata.tsv file
sample_metadata_file="${unify_working_dir}/sample_metadata.tsv"
echo "Creating sample metadata file: ${sample_metadata_file}"
# Write the header line
# echo -e interprets escape characters, \t represents a Tab character
echo -e "study_id\tsample_id" > "${sample_metadata_file}"
# Write the data line(s)
# Write the current project_id and sample_id to the file
# >> appends content, does not overwrite the header
echo -e "${project_id}\t${sample_id}" >> "${sample_metadata_file}"

echo "Sample metadata file created successfully."


# 3. Execute /bin/bash run_recount_unify.sh
echo "Calling run_recount_unify.sh with derived parameters..."

# Construct parameters to pass to run_recount_unify.sh
# Parameter 1: Singularity image file path
unify_sif_image="${singularity_image_dir}/recount-unify_1.0.4.sif"

# Parameter 2: grcm38 (fixed value)
unify_param2="grcm38"

# Parameter 3: working_directory (original, based on user's initial list)
unify_param3="${working_directory}"

# Parameter 4: unify_working_directory (newly created unify working directory)
unify_param4="${unify_working_dir}"

# Parameter 5: output/{sample_id}_att0/ (output directory, relative to original working directory)
# Construct output path
unify_param5="${working_directory}/output/${sample_id}_att0/"

# Parameter 6: unify_working_directory/sample_metadata.tsv (metadata file path)
# Construct metadata file path
unify_param6="${unify_working_dir}/sample_metadata.tsv"

# Parameter 7: 20 (fixed value)
unify_param7="20"

# Parameter 8: sra:101 (fixed value)
unify_param8="sra:101"

unify_command_to_print="/bin/bash run_recount_unify.sh"
unify_command_to_print+=" \"${unify_sif_image}\""
unify_command_to_print+=" \"${unify_param2}\""
unify_command_to_print+=" \"${unify_param3}\""
unify_command_to_print+=" \"${unify_param4}\""
unify_command_to_print+=" \"${unify_param5}\""
unify_command_to_print+=" \"${unify_param6}\""
unify_command_to_print+=" \"${unify_param7}\""
unify_command_to_print+=" \"${unify_param8}\""

echo "The exact command being executed is:"
echo "${unify_command_to_print}"
echo "------------------------------------------------------------"


# Execute run_recount_unify.sh script
# set -e ensures the script exits if run_recount_unify.sh fails
# Ensure run_recount_unify.sh has execute permissions and is in PATH or use full path.
# Or you need to provide its full path.
/bin/bash run_recount_unify.sh \
    "${unify_sif_image}" \
    "${unify_param2}" \
    "${unify_param3}" \
    "${unify_param4}" \
    "${unify_param5}" \
    "${unify_param6}" \
    "${unify_param7}" \
    "${unify_param8}"

echo "run_recount_unify.sh executed successfully."

# --- Process Unifier Output gene_sums file ---
echo "Processing Unifier output gene_sums file..."

# Construct the **search** starting directory for the expected gene counts file (start recursive search from here)
# This directory is usually the top-level directory for gene_sums output from Unifier
gene_sums_search_start_dir="${unify_working_dir}/gene_sums_per_study/"

# Construct the final destination directory for the decompressed file (newly created subdirectory within the original working directory)
decompressed_gene_sums_dir="${working_directory}/final_output/"
echo "Ensuring final output directory exists: ${decompressed_gene_sums_dir}"
# Create the target directory, does not error if it already exists
mkdir -p "${decompressed_gene_sums_dir}"

# Construct the filename pattern to search for
# * is a wildcard representing zero or more characters
gene_sums_filename_pattern="*gene_sums.${project_id}.M023.gz*"

# Use the find command to search for files matching the pattern recursively
echo "Looking for gzipped gene sums file recursively matching pattern: '${gene_sums_filename_pattern}' starting from directory: ${gene_sums_search_start_dir}"

# find command outputs the full path of matching files, one path per line.
# 2>/dev/null redirects find errors (e.g., permission denied in subdirectories) to null
# set -e ensures script exits if find fails due to other errors...
# Ensure the starting directory exists, otherwise find will error and trigger set -e
if [ ! -d "${gene_sums_search_start_dir}" ]; then
    echo "Error: Search start directory not found: ${gene_sums_search_start_dir}"
    echo "This indicates the Unifier step did not produce the expected output structure."
    exit 1
fi

found_gene_sums_files=$(find "${gene_sums_search_start_dir}" -name "${gene_sums_filename_pattern}" 2>/dev/null)

# Count the number of found files.
# If find did not find any files, the found_gene_sums_files variable is empty.
if [ -z "$found_gene_sums_files" ]; then
    file_count=0
else
    # Count the number of lines in the find output, which is the number of found files.
    file_count=$(echo "${found_gene_sums_files}" | wc -l)
fi


# Process based on the number of found files
if [ "$file_count" -eq 1 ]; then
    # Exactly one matching file was found
    # found_gene_sums_files variable now contains the full path of the found file (e.g., /path/to/.../file.gz)
    gzipped_gene_sums_file="$found_gene_sums_files" # Use the full path found by find

    echo "Found exactly one gzipped gene sums file: ${gzipped_gene_sums_file}. Decompressing..."

    # Construct the full path for the decompressed file in the final destination directory
    # Use basename "$gzipped_gene_sums_file" .gz to remove the path and .gz suffix from the actual found filename
    decompressed_gene_sums_file="${decompressed_gene_sums_dir}/$(basename "${gzipped_gene_sums_file}" .gz)"

    echo "Decompressing '${gzipped_gene_sums_file}' to '${decompressed_gene_sums_file}'"

    # Use gunzip -c to decompress the file and redirect output to the destination (the new directory)
    # set -e ensures script exits if gunzip fails
    gunzip -c "${gzipped_gene_sums_file}" > "${decompressed_gene_sums_file}"

    echo "Decompression successful. File saved."

    # (Optional) If you no longer need the original .gz file, you can delete it
    # echo "Removing original gzipped file: ${gzipped_gene_sums_file}"
    # rm "${gzipped_gene_sums_file}"

elif [ "$file_count" -eq 0 ]; then
    # No matching file was found
    echo "Error: No file matching pattern '${gene_sums_filename_pattern}' found recursively in ${gene_sums_search_start_dir}"
    # If the file does not exist, this is an error condition, exit the script
    exit 1
else
    # Multiple matching files were found
    echo "Error: Multiple files matching pattern '${gene_sums_filename_pattern}' found recursively in ${gene_sums_search_start_dir}:"
    # Print all found filenames (one per line)
    echo "${found_gene_sums_files}"
    echo "Please check the Unifier output or refine the pattern."
    # Finding multiple files is also an error condition, exit the script
    exit 1
fi

# --- Script End ---
echo "Script finished successfully."

exit 0