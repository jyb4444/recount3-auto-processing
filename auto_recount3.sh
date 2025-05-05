#!/bin/bash

# 设置在命令失败时立即退出脚本
set -e

# 检查是否提供了三个参数
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <project_id> <sample_id> <working_directory>"
    exit 1 
fi

# 将输入的参数分别赋值给变量，使其更易读
# 原始工作目录将被保存在这个变量中
project_id="$1"
sample_id="$2"
working_directory="$3" # 这是原始的工作目录

if [[ "${working_directory}" =~ .*/$ ]]; then
    echo "Warning: Your working_directory path ends with '/'. It's recommended to omit the trailing slash for consistency."
    # 可选：自动移除斜杠，但不修改用户输入，只是给出警告
    working_directory="${working_directory%/}" 
fi

expected_final_output_dir="${working_directory}/final_output"
# 定义预期的最终结果文件名模式 (解压后的文件没有 .gz 后缀)
expected_output_file_pattern="*gene_sums.${project_id}.M023*"

echo "Checking for existing results in ${expected_final_output_dir}..."

# >>> Revised Logic for checking existing results <<<
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

# 如果脚本执行到这里，意味着要么目录不存在，要么目录存在但里面没有找到符合模式的文件。
# 无论哪种情况，都继续执行下面的正式流程。
echo "No existing results found matching pattern '${expected_output_file_pattern}' in ${expected_final_output_dir}. Proceeding with pipeline execution."

# 确保工作目录存在，如果不存在则创建
mkdir -p "${working_directory}"

echo "Project ID: $project_id"
echo "Sample ID: $sample_id"
echo "Original Working Directory: $working_directory" # 明确打印原始工作目录

# --- 下载部分 ---
# 注意：修正了变量赋值的语法（=两边没有空格）
# 注意：修正了字符串拼接的语法（不能用+，用/或者直接连接）
# 注意：你提供的SRA URL是fasta，但你下载的文件名是fastq.gz，请确认这是你的预期。
# 通常从SRA获取FASTQ需要使用sra-toolkit的fastq-dump。
# url="https://trace.ncbi.nlm.nih.gov/Traces/sra-reads-be/fastq?acc=${sample_id}"
# 构造输出文件路径：工作目录 + 斜杠 + 样本ID + 后缀
output_file="${working_directory}/${sample_id}.fastq.gz"


# >>> 添加文件存在检查 <<<
echo "Checking for existing file: ${output_file}"
if [ -f "${output_file}" ]; then
    echo "Found existing file: ${output_file}. Skipping download."
else
    # 文件不存在，执行下载
    # echo "Existing file not found. Attempting to download data for Sample ID: ${sample_id} from ${url}"
    # echo "Output file will be: ${output_file}"

    # # 使用 curl 下载
    # # set -e 会在curl失败时自动退出，无需显式检查 $?
    # curl -L -o "${output_file}" "${url}" # 加上 -L 参数处理可能的重定向

    echo "Running fastq-dump for ${sample_id}..."
    # Ensure fastq-dump is in PATH or use full path here (e.g., /path/to/sratoolkit/bin/fastq-dump)
    fastq-dump --gzip "${sample_id}"

    echo "Download Successful: ${output_file}"
fi
# >>> 文件存在检查结束 <<<


# --- 执行 run_recount_pump.sh 脚本 ---
echo "Calling run_recount_pump.sh with derived parameters..."

# 根据你的需求构建传递给 run_recount_pump.sh 的参数
# 参数 1: working_directory + recount-rs5_1.0.6.sif
pump_sif_image="${working_directory}/recount-rs5_1.0.6.sif" # 假设.sif文件在原始工作目录下

# 参数 2: sample_id
pump_sample_id="${sample_id}"

# 参数 3: local (固定值)
pump_param3="local"

# 参数 4: grcm38 (固定值)
pump_param4="grcm38"

# 参数 5: 20 (固定值)
pump_param5="20"

# 参数 6: working_directory (原始工作目录)
pump_working_dir="${working_directory}"

# 参数 7: working_directory + sample_id.fastq.gz (下载的文件路径)
pump_fastq_file="${output_file}" # 直接使用上面定义的 output_file 变量

# 参数 8: working_directory + sample_id.fastq.gz (再次使用下载的文件路径)
pump_fastq_file2="${output_file}" # 假设这是单端数据的处理方式，或需要重复提供

# 参数 9: project_id
pump_project_id="${project_id}"

# 执行 run_recount_pump.sh 脚本
# set -e 会在run_recount_pump.sh失败时自动退出，无需显式检查 $?
# 确保 run_recount_pump.sh 文件有执行权限，并且在当前环境的 PATH 中，
# 或者你需要提供它的完整路径，例如 /path/to/run_recount_pump.sh
/bin/bash run_recount_pump.sh \
    "${pump_sif_image}" \
    "${pump_sample_id}" \
    "${pump_param3}" \
    "${pump_param4}" \
    "${pump_param5}" \
    "${pump_working_dir}" \
    "${pump_fastq_file}" \
    "${pump_fastq_file2}" \
    "${pump_project_id}"

echo "run_recount_pump.sh executed successfully."


# --- Unifier 部分 ---
echo "Starting Unifier steps..."

# 1. 创建一个新的目录叫做unify_working
# 这个目录创建在原始的工作目录下
unify_working_dir="${working_directory}/unify_working"
echo "Creating Unifier working directory: ${unify_working_dir}"
mkdir -p "${unify_working_dir}" # -p 参数会在父目录不存在时一并创建
echo "Unifier working directory created: ${unify_working_dir}"

# >>> 添加创建 sample_metadata.tsv 文件功能 <<<
sample_metadata_file="${unify_working_dir}/sample_metadata.tsv"
echo "Creating sample metadata file: ${sample_metadata_file}"

# 写入 header 行
# echo -e 用来解释转义字符，\t 代表 Tab 键
echo -e "study_id\tsample_id" > "${sample_metadata_file}"

# 写入数据行
# 将当前的 project_id 和 sample_id 写入文件
# >> 表示追加内容，不会覆盖 header
echo -e "${project_id}\t${sample_id}" >> "${sample_metadata_file}"

echo "Sample metadata file created successfully."

# 2. (概念上)修改working_directory为原本的working_directory/unify_working
#    在脚本中，我们不修改原始的 $working_directory 变量，而是使用一个新的变量
#    unify_working_dir 来引用这个新目录，以避免混淆。
#    原始的工作目录仍然保存在 $working_directory 中，这对于构建一些参数是需要的。

# 3. 运行 /bin/bash run_recount_unify.sh
echo "Calling run_recount_unify.sh with derived parameters..."

# 根据你的需求构建传递给 run_recount_unify.sh 的参数
# 参数 1: working_directory + recount-unify_1.0.4.sif (原始工作目录下的sif文件)
unify_sif_image="${working_directory}/recount-unify_1.0.4.sif"

# 参数 2: grcm38 (固定值)
unify_param2="grcm38"

# 参数 3: working_directory (原始工作目录)
unify_param3="${working_directory}"

# 参数 4: working_directory+unifier_working (新创建的 unify 工作目录)
unify_param4="${unify_working_dir}"

# 参数 5: working_directory+output/{sample_id}_att0/ (输出目录，相对于原始工作目录)
unify_param5="${working_directory}/output/${sample_id}_att0/" # 构造输出路径

# 参数 6: working_directory+unifier_working/sample_metadata.tsv (元数据文件路径)
unify_param6="${unify_working_dir}/sample_metadata.tsv" # 构造元数据文件路径

# 参数 7: 20 (固定值)
unify_param7="20"

# 参数 8: sra:101 (固定值)
unify_param8="sra:101"

# 执行 run_recount_unify.sh 脚本
# set -e 会在run_recount_unify.sh失败时自动退出，无需显式检查 $?
# 确保 run_recount_unify.sh 文件有执行权限，并且在当前环境的 PATH 中，
# 或者你需要提供它的完整路径。
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

# --- 处理 Unifier 输出的 gene_sums 文件 ---
echo "Processing Unifier output gene_sums file..."

# 构建预期基因计数文件的**搜索**起始目录 (从这里开始递归查找)
# 这个目录通常是 Unifier 输出中 gene_sums 相关的顶级目录
gene_sums_search_start_dir="${unify_working_dir}/gene_sums_per_study/" # 从 gene_sums_per_study 目录开始查找

# 构建解压后文件存放的最终目标目录 (原始工作目录下新创建的子目录)
decompressed_gene_sums_dir="${working_directory}/final_output/"
echo "Ensuring final output directory exists: ${decompressed_gene_sums_dir}"
# 创建目标目录，如果已存在则不报错
mkdir -p "${decompressed_gene_sums_dir}"

# 构建查找的文件名模式
gene_sums_filename_pattern="*gene_sums.${project_id}.M023.gz*"

# 使用 find 命令递归查找匹配模式的文件
echo "Looking for gzipped gene sums file recursively matching pattern: '${gene_sums_filename_pattern}' starting from directory: ${gene_sums_search_start_dir}"

# find "${gene_sums_search_start_dir}" -name "${gene_sums_filename_pattern}" -print
# find 命令会输出匹配文件的完整路径，每个路径一行。
# 2>/dev/null 将 find 命令在搜索过程中可能遇到的错误（如没有权限访问某个子目录）重定向到空设备
# 确保起始目录存在，否则 find 会报错并触发 set -e
if [ ! -d "${gene_sums_search_start_dir}" ]; then
    echo "Error: Search start directory not found: ${gene_sums_search_start_dir}"
    echo "This indicates the Unifier step did not produce the expected output structure."
    exit 1
fi


found_gene_sums_files=$(find "${gene_sums_search_start_dir}" -name "${gene_sums_filename_pattern}" 2>/dev/null)

# 统计找到的文件的数量
# 如果 find 没有找到文件，found_gene_sums_files 变量是空的
if [ -z "$found_gene_sums_files" ]; then
    file_count=0
else
    # 统计 find 输出的行数，即找到的文件数量
    file_count=$(echo "${found_gene_sums_files}" | wc -l)
fi


# 根据找到的文件数量进行处理
if [ "$file_count" -eq 1 ]; then
    # 找到了正好一个匹配的文件
    # found_gene_sums_files 变量现在已经包含了找到文件的完整路径（例如 /path/to/.../file.gz）
    gzipped_gene_sums_file="$found_gene_sums_files" # 使用 find 找到的完整路径

    echo "Found exactly one gzipped gene sums file: ${gzipped_gene_sums_file}. Decompressing..."

    # 构建解压后文件在最终目标目录中的完整路径
    # 使用 basename "$gzipped_gene_sums_file" .gz 从找到的文件的完整路径中提取文件名并移除 .gz 后缀
    decompressed_gene_sums_file="${decompressed_gene_sums_dir}/$(basename "${gzipped_gene_sums_file}" .gz)"

    echo "Decompressing '${gzipped_gene_sums_file}' to '${decompressed_gene_sums_file}'"

    # 使用 gunzip -c 解压文件并将输出重定向到目标位置 (新的目录)
    # set -e 会在gunzip失败时自动退出
    gunzip -c "${gzipped_gene_sums_file}" > "${decompressed_gene_sums_file}"

    echo "Decompression successful. File saved."

    # (可选) 如果你不需要原始的 .gz 文件了，可以将其删除
    # echo "Removing original gzipped file: ${gzipped_gene_sums_file}"
    # rm "${gzipped_gene_sums_file}"

elif [ "$file_count" -eq 0 ]; then
    # 没有找到匹配的文件
    echo "Error: No file matching pattern '${gene_sums_filename_pattern}' found recursively in ${gene_sums_search_start_dir}"
    # 如果文件不存在，这是个错误情况，退出脚本
    exit 1
else
    # 找到多个匹配的文件
    echo "Error: Multiple files matching pattern '${gene_sums_filename_pattern}' found recursively in ${gene_sums_search_start_dir}:"
    echo "${found_gene_sums_files}" # 打印所有找到的文件名 (每个一行)
    echo "Please check the Unifier output or refine the pattern."
    # 找到多个文件也是一个错误情况，退出脚本
    exit 1
fi

# --- 脚本结束 ---
echo "Script finished successfully."

exit 0