#!/bin/bash

# Slurm 脚本的头部设置
#SBATCH --job-name=monorail_batch  # 批量提交的主作业名称
#SBATCH --output=logs/batch_submission_%j.out # 主作业的标准输出文件
#SBATCH --error=logs/batch_submission_%j.err  # 主作业的标准错误文件
#SBATCH --time=30:00:00          # 主提交脚本的运行时间限制 (这个脚本本身运行很快)
#SBATCH --mem=32G                 # 主提交脚本的内存限制 (很小)
#SBATCH --ntasks=1               # 主提交脚本只运行一个任务

# 设置当命令失败时立即退出脚本
# 注意: 当尝试获取SRR ID失败时，我们希望跳过当前样本而不是退出整个脚本
# 因此，只在关键步骤（如文件复制失败）使用 set -e，或者在需要时检查命令的返回值。
# 对于curl/sed，我们会在获取SRR ID后进行显式检查。
# set -e #暂时禁用，将在需要时检查返回值或使用逻辑控制

# --- 用户需要配置的变量 ---
# 包含样本列表的文件路径 (假设格式是 Tab 分隔，第一列是 GSM ID，最后一列是 SRA 链接)
INPUT_SAMPLE_LIST="/mnt/scratch/yuankeji/monorail_parallel/sample_list.txt"

# 所有必要的脚本和 Singularity 镜像等文件的来源目录
# 这些文件将在 Slurm 作业运行前被复制到每个样本的工作目录中
SOURCE_FILES_DIR="/mnt/scratch/yuankeji/monorail-external5"

# 批量作业的工作目录的基础路径
# 每个样本的工作目录将是 BASE_WORKING_DIR/monorail-external_GSM_ID
BASE_WORKING_DIR="/mnt/scratch/yuankeji"

# 需要为每个样本作业复制的文件列表
# 请确保这些文件/目录存在于 SOURCE_FILES_DIR 中
# 根据之前的讨论和你的脚本内容，这些应该是运行 auto_recount3.sh 所需的文件
FILES_TO_COPY=(
    "auto_recount3.sh"          # 你要为每个样本运行的主脚本
    "run_recount_pump.sh"       # Pump 的子脚本
    "run_recount_unify.sh"      # Unifier 的子脚本
    "get_mouse_ref_indexes.sh"  # 参考基因组设置脚本
    "get_unify_refs.sh"         # Unifier 参考文件设置脚本
    "recount-rs5_1.0.6.sif"     # Pump 的 Singularity 镜像
    "recount-unify_1.0.4.sif"   # Unifier 的 Singularity 镜像
    "grcm38"                    # 参考基因组目录
    "grcm38_unify"              # Unifier 参考文件目录
)

# --------------------------

# 创建主提交脚本的日志目录
mkdir -p logs
mkdir -p logs/individual_jobs # 创建一个目录用于存放每个样本作业的 Slurm 日志

echo "--- Starting Batch Submission ---"
echo "Input Sample List: ${INPUT_SAMPLE_LIST}"
echo "Source Files Directory: ${SOURCE_FILES_DIR}"
echo "Base Working Directory: ${BASE_WORKING_DIR}"
echo "---"

# 检查输入文件是否存在
if [ ! -f "${INPUT_SAMPLE_LIST}" ]; then
    echo "Error: Input sample list file not found: ${INPUT_SAMPLE_LIST}"
    exit 1
fi

# 逐行读取输入文件
# 使用 read -r line 读取整行，然后使用 cut 和 awk 提取所需的字段
while read -r line || [[ -n "$line" ]]; do

    # 跳过空行或只有空白字符的行
    if [ -z "$(echo "${line}" | tr -d '[:space:]')" ]; then
        continue
    fi

    # --- 提取 GSM ID (第一列) ---
    # 使用 cut 命令以 Tab 为分隔符提取第一个字段
    gsm_id=$(echo "$line" | cut -f1 -d $'\t')

    # 移除 gsm_id 前后的空白字符，以防万一
    gsm_id=$(echo "${gsm_id}" | tr -d '[:space:]')

    # 检查是否成功提取到 GSM ID (至少第一列要有内容)
    if [ -z "$gsm_id" ]; then
        echo "Warning: Could not extract GSM ID from line: '$line'. Skipping this line."
        echo "---"
        continue # 跳过此行
    fi

    echo "Processing sample: ${gsm_id}"

    # --- 提取 SRA 链接部分 (最后一列) ---
    # 使用 awk 命令以 Tab 为分隔符提取最后一个字段 ($NF)
    sra_part=$(echo "$line" | awk -F'\t' '{print $NF}')

    # 检查提取到的 sra_part 是否以 "SRA: " 开头
    if [[ ! "$sra_part" =~ ^SRA: ]]; then
        echo "Warning: Last field for GSM ID ${gsm_id} does not start with 'SRA: '. Skipping this sample."
        echo "Input line part for SRA: '${sra_part}'"
        echo "Full line was: '$line'" # Added for debugging
        echo "---"
        continue # 跳过此样本
    fi

    # sra_part 的格式是 "SRA: https://www.ncbi.nlm.nih.gov/sra?term=SRX..."
    # 使用 bash 参数扩展提取 URL 部分 (移除开头的 "SRA: ")
    sra_url=${sra_part#SRA: }
    echo "check sra $sra_url"
    # 再次检查提取到的 URL 是否为空
    if [ -z "$sra_url" ]; then
        echo "Warning: Extracted SRA URL is empty for GSM ID ${gsm_id} after removing 'SRA: '. Skipping this sample."
        echo "Input line part for SRA: '${sra_part}'"
        echo "Full line was: '$line'" # Added for debugging
        echo "---"
        continue # 跳过此样本
    fi


    echo "Fetching SRA page from: ${sra_url}"

    # 使用 curl 获取页面内容，并使用 sed 提取 SRR ID
    # sed 命令解释:
    # -n: 不自动打印每一行
    # s/.../.../: 执行替换
    # .*href=".*"> : 匹配任意字符直到 href="..." 后面的 ">"
    # \(SRR[0-9]*\): 捕获一个组，匹配 "SRR" 后跟一个或多个数字
    # <.*/: 匹配 "<" 后跟任意字符直到行尾
    # \1: 替换为捕获的组 (SRR ID)
    # p: 打印发生替换的行
    # 添加对 curl 命令的错误检查
    page_content=$(curl -s "$sra_url")
    if [ $? -ne 0 ]; then
        echo "Error: curl failed to fetch SRA page for ${gsm_id} (URL: ${sra_url}). Skipping this sample."
        echo "---"
        continue
    fi

    srr_id=$(echo "$page_content" | sed -n 's/.*href=".*">\(SRR[0-9]*\)<.*/\1/p')

    # 检查是否成功提取到 SRR ID
    if [ -z "$srr_id" ]; then
        echo "Error: Could not extract SRR ID from SRA page for ${gsm_id} (URL: ${sra_url})."
        echo "Check if the SRA page contains the expected SRR link format."
        echo "Skipping this sample."
        echo "---"
        continue # 跳过此样本
    fi

    echo "Extracted SRR ID: ${srr_id}"
    # --- SRR ID 提取结束 ---

    # 构造当前样本的工作目录路径 (依然使用 GSM ID)
    SAMPLE_WORKING_DIR="${BASE_WORKING_DIR}/monorail_parallel/monorail-external_${gsm_id}"
    echo "Sample Working Directory: ${SAMPLE_WORKING_DIR}"

    # 为当前样本创建工作目录
    if ! mkdir -p "${SAMPLE_WORKING_DIR}"; then
        echo "Error: Failed to create directory ${SAMPLE_WORKING_DIR}. Skipping this sample."
        echo "---"
        continue # 跳过此样本
    fi
    echo "Created directory: ${SAMPLE_WORKING_DIR}"

    echo "Copying necessary files to ${SAMPLE_WORKING_DIR}..."
    # 将必要的文件复制到当前样本的工作目录中
    copy_failed=false
    for file_item in "${FILES_TO_COPY[@]}"; do
        SOURCE_PATH="${SOURCE_FILES_DIR}/${file_item}"
        DEST_PATH="${SAMPLE_WORKING_DIR}/"
        if [ -e "${SOURCE_PATH}" ]; then # 检查源文件/目录是否存在
            # 使用 -r 选项以防复制的是目录
            if ! cp -r "${SOURCE_PATH}" "${DEST_PATH}"; then
                echo "Error: Failed to copy ${file_item} to ${SAMPLE_WORKING_DIR}. Individual job for ${gsm_id} might fail."
                copy_failed=true # 标记复制失败
            fi
        else
            echo "Warning: Source file/directory not found for copying: ${SOURCE_PATH}. Individual job for ${gsm_id} might fail."
            copy_failed=true # 标记复制失败
        fi
    done

    # 如果任何文件复制失败，则跳过此样本的 Slurm 提交
    if [ "$copy_failed" = true ]; then
        echo "File copying failed for ${gsm_id}. Skipping Slurm submission."
        echo "---"
        continue
    fi

    echo "Finished copying files for ${gsm_id}."

    # 构造要提交给 Slurm 的命令
    # COMMAND_TO_RUN="/bin/bash [复制到样本目录的脚本路径] [参数1 SRR_ID] [参数2 GSM_ID] [参数3 样本工作目录路径]"
    # **重要**: 根据你的描述，第一个参数现在是 SRR ID
    COMMAND_TO_RUN="/bin/bash ${SAMPLE_WORKING_DIR}/auto_recount3.sh ${srr_id} ${gsm_id} ${SAMPLE_WORKING_DIR}"

    # 构造该样本作业的 Slurm 日志文件路径 (依然使用 GSM ID for clarity)
    SBATCH_OUT_LOG="logs/individual_jobs/${gsm_id}_slurm-%j.out"
    SBATCH_ERR_LOG="logs/individual_jobs/${gsm_id}_slurm-%j.err"

    echo "Submitting Slurm job for ${gsm_id} (SRR: ${srr_id})..."
    # 使用 sbatch 命令提交单个样本的作业
    # --job-name: 单个作业的名称，包含 GSM ID
    # --output, --error: 指定该作业的日志文件
    # --chdir: 让作业在新创建的样本工作目录中运行
    # --time, --mem, --cpus-per-task: 为单个样本作业指定资源 (请根据你的数据和集群调整这些值!)
    # 使用 --export=ALL 将所有当前环境变量传递给作业
    sbatch \
        --job-name="mono_${gsm_id}" \
        --output="${SBATCH_OUT_LOG}" \
        --error="${SBATCH_ERR_LOG}" \
        --chdir="${SAMPLE_WORKING_DIR}" \
        --time=03:00:00 \
        --mem=32G \
        --cpus-per-task=20 \
        --export=ALL \
        --wrap "${COMMAND_TO_RUN}"

    echo "Job submitted for ${gsm_id}. Slurm logs will be in logs/individual_jobs/"
    echo "---"

# 从指定输入文件读取
done < "${INPUT_SAMPLE_LIST}"

echo "--- All individual sample jobs have been submitted to Slurm ---"

exit 0