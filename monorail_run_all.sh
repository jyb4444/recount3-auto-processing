#!/bin/bash
set -e  # 遇到错误立即退出

# =============================================================================
# Monorail 批处理脚本
# 用途: 对所有样本运行 recount-pump，然后运行一次 recount-unify 聚合所有结果
# =============================================================================

# 批处理模式：设置为1则自动跳过已完成的样本，设置为0则交互式询问
BATCH_MODE=0
if [[ "$1" == "--batch" ]] || [[ "$1" == "-b" ]]; then
    BATCH_MODE=1
    echo "=========================================="
    echo "批处理模式: 自动跳过已完成的样本"
    echo "=========================================="
fi

# 批处理模式：设置为1则自动跳过已完成的样本，不需要手动确认
BATCH_MODE=1  # 设置为0则每个已完成样本都会询问

# 配置路径
MONORAIL_DIR="/mnt/scratch/yuankeji/monorail-external"
DATA_DIR="/mnt/scratch/yuankeji/monorail-external-data"
OUTPUT_DIR="/mnt/scratch/yuankeji/monorail-external/output"
UNIFIER_WORKING_DIR="/mnt/scratch/yuankeji/monorail-external/unifier_working_all"

# 镜像路径
PUMP_IMAGE="${MONORAIL_DIR}/recount-rs5_1.0.6.sif"
UNIFIER_IMAGE="${MONORAIL_DIR}/recount-unify_1.0.4.sif"

# 参数
REFERENCE="grcm38"
NUM_CPUS=20
STUDY_ID="PRJ0004"
PROJECT_ID="loc:140"

# 样本列表（从数据目录自动获取）
SAMPLES=(M40 M41 M42 M43 M44 M45 M46 M47 M48 M49 M50 M51 M52 M53 M54 M55 M56 M57 M64 M65 M66 M67 M69 M70 M71 M73 M76 M77 M82 M84 M86)

# 初始 rail_id（可以根据需要调整）
RAIL_ID_START=280

# =============================================================================
# 步骤 1: 运行 recount-pump（对每个样本）
# =============================================================================

echo "=========================================="
echo "步骤 1: 运行 recount-pump"
echo "样本总数: ${#SAMPLES[@]}"
echo "=========================================="

cd ${MONORAIL_DIR}

for SAMPLE in "${SAMPLES[@]}"; do
    echo ""
    echo "处理样本: ${SAMPLE}"
    echo "------------------------------------------"
    
    # 检查输入文件是否存在
    FASTQ1="${DATA_DIR}/${SAMPLE}/${SAMPLE}_1.fq.gz"
    FASTQ2="${DATA_DIR}/${SAMPLE}/${SAMPLE}_2.fq.gz"
    
    if [[ ! -f ${FASTQ1} ]]; then
        echo "错误: ${FASTQ1} 不存在，跳过样本 ${SAMPLE}"
        continue
    fi
    
    if [[ ! -f ${FASTQ2} ]]; then
        echo "错误: ${FASTQ2} 不存在，跳过样本 ${SAMPLE}"
        continue
    fi
    
    # 检查输出是否已存在
    SKIP_SAMPLE=0
    if [[ -d "${OUTPUT_DIR}/${SAMPLE}_att0" ]]; then
        # 检查是否有 manifest 文件（pump 成功的标志）
        if [[ -f "${OUTPUT_DIR}/${SAMPLE}_att0/${SAMPLE}!${STUDY_ID}!${REFERENCE}!local.manifest" ]]; then
            if [[ ${BATCH_MODE} -eq 1 ]]; then
                echo "✓ 样本 ${SAMPLE} 已完成 pump，跳过"
                SKIP_SAMPLE=1
            else
                echo "✓ 样本 ${SAMPLE} 已完成 pump"
                read -p "  是否跳过? (y=跳过, n=删除并重新运行): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo "  跳过样本 ${SAMPLE}"
                    SKIP_SAMPLE=1
                else
                    echo "  删除并重新运行..."
                    rm -rf "${OUTPUT_DIR}/${SAMPLE}_att0"
                fi
            fi
        else
            echo "警告: ${OUTPUT_DIR}/${SAMPLE}_att0 存在但不完整"
            if [[ ${BATCH_MODE} -eq 1 ]]; then
                echo "批处理模式：清理并重新运行"
                rm -rf "${OUTPUT_DIR}/${SAMPLE}_att0"
            else
                read -p "是否重新运行此样本? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "跳过样本 ${SAMPLE}"
                    SKIP_SAMPLE=1
                else
                    # 清理不完整的输出
                    echo "清理不完整的输出..."
                    rm -rf "${OUTPUT_DIR}/${SAMPLE}_att0"
                fi
            fi
        fi
    fi
    
    if [[ ${SKIP_SAMPLE} -eq 0 ]]; then
        # 运行 pump
        echo "开始运行 pump..."
        ./run_recount_pump.sh \
            ${PUMP_IMAGE} \
            ${SAMPLE} \
            local \
            ${REFERENCE} \
            ${NUM_CPUS} \
            ${MONORAIL_DIR}/ \
            ${FASTQ1} \
            ${FASTQ2} \
            ${STUDY_ID}
        
        PUMP_EXIT_CODE=$?
        
        # 验证输出是否真的生成了
        if [[ -f "${OUTPUT_DIR}/${SAMPLE}_att0/${SAMPLE}!${STUDY_ID}!${REFERENCE}!local.manifest" ]]; then
            echo "✓ 样本 ${SAMPLE} pump 完成"
        elif [[ $PUMP_EXIT_CODE -eq 0 ]]; then
            # 退出码为0但没有manifest，可能是"Nothing to be done"
            echo "⚠ 样本 ${SAMPLE} pump 返回成功但未找到输出文件"
            echo "  这可能是因为 Snakemake 检测到工作已完成"
            read -p "  是否继续处理其他样本? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        else
            echo "✗ 样本 ${SAMPLE} pump 失败 (退出码: ${PUMP_EXIT_CODE})"
            if [[ ${BATCH_MODE} -eq 1 ]]; then
                echo "批处理模式：继续处理下一个样本"
            else
                read -p "是否继续处理其他样本? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
        fi
    fi
done

echo ""
echo "=========================================="
echo "所有样本的 pump 运行完成！"
echo "=========================================="

# =============================================================================
# 步骤 2: 准备 Unifier 输入
# =============================================================================

echo ""
echo "=========================================="
echo "步骤 2: 准备 Unifier 输入文件"
echo "=========================================="

# 创建新的工作目录
mkdir -p ${UNIFIER_WORKING_DIR}

# 创建 sample_metadata.tsv
echo "创建 sample_metadata.tsv..."
METADATA_FILE="${UNIFIER_WORKING_DIR}/sample_metadata.tsv"

echo -e "study_id\tsample_id" > ${METADATA_FILE}

for SAMPLE in "${SAMPLES[@]}"; do
    # 检查该样本的输出是否存在
    if [[ -d "${OUTPUT_DIR}/${SAMPLE}_att0" ]]; then
        echo -e "${STUDY_ID}\t${SAMPLE}" >> ${METADATA_FILE}
    else
        echo "警告: ${SAMPLE}_att0 不存在，不包含在 metadata 中"
    fi
done

echo "✓ sample_metadata.tsv 创建完成"
cat ${METADATA_FILE}

# 创建 ids.tsv（手动生成以避免 ERROR 问题）
echo ""
echo "创建 ids.tsv..."
IDS_FILE="${UNIFIER_WORKING_DIR}/ids.tsv"

# 清空文件（如果存在）
> ${IDS_FILE}

RAIL_ID=${RAIL_ID_START}
for SAMPLE in "${SAMPLES[@]}"; do
    if [[ -d "${OUTPUT_DIR}/${SAMPLE}_att0" ]]; then
        echo -e "${STUDY_ID}\t${SAMPLE}\t${RAIL_ID}" >> ${IDS_FILE}
        RAIL_ID=$((RAIL_ID + 1))
    fi
done

echo "✓ ids.tsv 创建完成"
cat ${IDS_FILE}

# =============================================================================
# 步骤 3: 运行 recount-unify
# =============================================================================

echo ""
echo "=========================================="
echo "步骤 3: 准备 Unifier 输入结构"
echo "=========================================="

# Unifier 需要特定的目录结构
# 格式: links/study_loworder/study/sample_loworder/sample/sample_in#_att0/
# 例如: links/04/PRJ0004/40/M40/M40_in2_att0/

LINKS_DIR="${UNIFIER_WORKING_DIR}/links"
mkdir -p ${LINKS_DIR}

echo "创建符号链接结构..."
LINK_COUNT=0
INPUT_ID=1

for SAMPLE in "${SAMPLES[@]}"; do
    if [[ -d "${OUTPUT_DIR}/${SAMPLE}_att0" ]]; then
        # 检查是否有 manifest 文件（pump 成功的标志）
        if [[ -f "${OUTPUT_DIR}/${SAMPLE}_att0/${SAMPLE}!${STUDY_ID}!${REFERENCE}!local.manifest" ]]; then
            # 计算 loworder（最后两位数字）
            STUDY_LOWORDER="${STUDY_ID: -2}"
            SAMPLE_LOWORDER="${SAMPLE: -2}"
            
            # 创建目录结构
            TARGET_DIR="${LINKS_DIR}/${STUDY_LOWORDER}/${STUDY_ID}/${SAMPLE_LOWORDER}/${SAMPLE}"
            mkdir -p ${TARGET_DIR}
            
            # 创建符号链接（带 input_id）
            LINK_NAME="${SAMPLE}_in${INPUT_ID}_att0"
            ln -sf "${OUTPUT_DIR}/${SAMPLE}_att0" "${TARGET_DIR}/${LINK_NAME}"
            
            # 创建 .done 文件
            touch "${TARGET_DIR}/${LINK_NAME}.done"
            
            echo "  ✓ ${SAMPLE} -> ${TARGET_DIR}/${LINK_NAME}"
            LINK_COUNT=$((LINK_COUNT + 1))
            INPUT_ID=$((INPUT_ID + 1))
        else
            echo "  ⚠ ${SAMPLE} 没有 manifest 文件，跳过"
        fi
    else
        echo "  ⚠ ${SAMPLE} 输出目录不存在，跳过"
    fi
done

echo "✓ 创建了 ${LINK_COUNT} 个样本的符号链接"

# =============================================================================
# 步骤 4: 运行 recount-unify
# =============================================================================

echo ""
echo "=========================================="
echo "步骤 4: 运行 recount-unify"
echo "=========================================="

cd ${MONORAIL_DIR}

# 设置环境变量
export SKIP_PREP=1      # 跳过准备步骤（使用我们创建的 links 和 ids.tsv）
export SKIP_FIND=1      # 跳过查找文件步骤（我们已经创建了 links）

echo "开始运行 unifier..."
/bin/bash run_recount_unify.sh \
    ${UNIFIER_IMAGE} \
    ${REFERENCE} \
    ${MONORAIL_DIR}/ \
    ${UNIFIER_WORKING_DIR}/ \
    ${OUTPUT_DIR}/ \
    ${METADATA_FILE} \
    ${NUM_CPUS} \
    ${PROJECT_ID}

if [[ $? -eq 0 ]]; then
    echo ""
    echo "=========================================="
    echo "✓ Unifier 运行成功！"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "✗ Unifier 运行失败"
    echo "=========================================="
    exit 1
fi

# =============================================================================
# 步骤 5: 整理输出结果
# =============================================================================

echo ""
echo "=========================================="
echo "步骤 5: 整理输出结果"
echo "=========================================="

FINAL_OUTPUT_DIR="/mnt/scratch/yuankeji/monorail_final_results"
mkdir -p ${FINAL_OUTPUT_DIR}

echo "复制结果到: ${FINAL_OUTPUT_DIR}"

# 复制主要结果
cp -r ${UNIFIER_WORKING_DIR}/gene_sums_per_study ${FINAL_OUTPUT_DIR}/ 2>/dev/null || echo "gene_sums_per_study 不存在"
cp -r ${UNIFIER_WORKING_DIR}/exon_sums_per_study ${FINAL_OUTPUT_DIR}/ 2>/dev/null || echo "exon_sums_per_study 不存在"
cp -r ${UNIFIER_WORKING_DIR}/junction_counts_per_study ${FINAL_OUTPUT_DIR}/ 2>/dev/null || echo "junction_counts_per_study 不存在"
cp -r ${UNIFIER_WORKING_DIR}/metadata ${FINAL_OUTPUT_DIR}/ 2>/dev/null || echo "metadata 不存在"

# 复制关键文件
cp ${UNIFIER_WORKING_DIR}/samples.tsv ${FINAL_OUTPUT_DIR}/ 2>/dev/null || echo "samples.tsv 不存在"
cp ${UNIFIER_WORKING_DIR}/qc.tsv ${FINAL_OUTPUT_DIR}/ 2>/dev/null || echo "qc.tsv 不存在"
cp ${IDS_FILE} ${FINAL_OUTPUT_DIR}/ 2>/dev/null || echo "ids.tsv 不存在"
cp ${METADATA_FILE} ${FINAL_OUTPUT_DIR}/ 2>/dev/null || echo "sample_metadata.tsv 不存在"

# 创建结果摘要
SUMMARY_FILE="${FINAL_OUTPUT_DIR}/SUMMARY.txt"
cat > ${SUMMARY_FILE} << EOF
Monorail Pipeline 运行摘要
=========================

运行时间: $(date)
参考基因组: ${REFERENCE}
项目ID: ${STUDY_ID}
样本总数: ${#SAMPLES[@]}

处理的样本:
$(cat ${METADATA_FILE} | tail -n +2 | cut -f 2 | tr '\n' ', ')

输出目录结构:
- gene_sums_per_study/: 基因表达量矩阵
- exon_sums_per_study/: 外显子表达量矩阵
- junction_counts_per_study/: 剪接位点计数
- metadata/: 样本元数据
- samples.tsv: 样本信息表
- qc.tsv: 质量控制统计
- ids.tsv: 样本ID映射

下一步:
1. 检查 qc.tsv 查看质量控制指标
2. 在 gene_sums_per_study/${STUDY_ID##*/}/ 中找到基因表达矩阵
3. 使用 R/recount3 包加载和分析数据
EOF

echo "✓ 结果已复制到: ${FINAL_OUTPUT_DIR}"
cat ${SUMMARY_FILE}

echo ""
echo "=========================================="
echo "全部完成！"
echo "结果位置: ${FINAL_OUTPUT_DIR}"
echo "=========================================="
