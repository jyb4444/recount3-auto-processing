For the single fastq file to run, you can use the following structure and reference from the monorail-external repo for details.

Pump:
./run_recount_pump.sh /mnt/scratch/yuankeji/monorail-external/recount-rs5_1.0.6.sif M40 local grcm38 20 /mnt/scratch/yuankeji/monorail-external/ /mnt/scratch/yuankeji/monorail-external-data/M40/M40_1.fq.gz /mnt/scratch/yuankeji/monorail-external-data/M40/M40_2.fq.gz PRJ0004

Unifier:
/bin/bash run_recount_unify.sh /mnt/scratch/yuankeji/monorail-external/recount-unify_1.0.4.sif grcm38 /mnt/scratch/yuankeji/monorail-external/ /mnt/scratch/yuankeji/monorail-external/unifier_working/ /mnt/scratch/yuankeji/monorail-external/output/ /mnt/scratch/yuankeji/monorail-external/unifier_working/sample_metadata.tsv 20 loc:140

If you have multiple samples need to handle, you can use the monorail_run_all.sh to run it and you can get all gene expression in one file.

# Monorail 批处理流程使用指南

这是一个自动化的 Monorail RNA-seq 分析流程脚本，用于批量处理多个样本，从 FASTQ 文件到基因表达矩阵。

## 📋 目录

- [快速开始](#快速开始)
- [系统要求](#系统要求)
- [安装配置](#安装配置)
- [使用方法](#使用方法)
- [输出结果](#输出结果)
- [常见问题](#常见问题)
- [高级用法](#高级用法)

---

## 🚀 快速开始

```bash
# 1. 确保 Singularity 已安装
singularity --version

# 2. 准备脚本
cd /your/working/directory
chmod +x monorail_run_all.sh

# 3. 检查配置（编辑脚本开头的路径）
vim monorail_run_all.sh

# 4. 运行（批处理模式，自动跳过已完成的样本）
./monorail_run_all.sh --batch

# 5. 查看结果
ls /your/results/directory/
```

---

## 💻 系统要求

### 必需软件
- **Singularity** 2.6+ 或 3.x+
- **Bash** 4.0+
- **足够的磁盘空间**：每个样本约 10-100 MB（取决于测序深度）

### 硬件建议
- **CPU**: 至少 20 核（可在脚本中调整）
- **内存**: 至少 32 GB（人类样本需要更多）
- **磁盘**: 根据样本数量，建议至少 100 GB 可用空间

### 输入数据格式
- FASTQ 文件（可以是 gzipped `.fq.gz` 或未压缩 `.fq`）
- 支持双端测序（paired-end）
- 文件命名格式：`SAMPLE_1.fq.gz` 和 `SAMPLE_2.fq.gz`

---

## 🔧 安装配置

### 1. 下载 Monorail 镜像

```bash
# 下载 recount-pump 镜像
singularity pull docker://quay.io/benlangmead/recount-rs5:1.0.6

# 下载 recount-unify 镜像
singularity pull docker://quay.io/broadsword/recount-unify:1.0.4
```

### 2. 下载参考基因组索引

对于小鼠（grcm38）：
```bash
cd /your/reference/directory
./get_mouse_ref_indexes.sh
./get_unify_refs.sh grcm38
```

对于人类（hg38）：
```bash
cd /your/reference/directory
./get_human_ref_indexes.sh
./get_unify_refs.sh hg38
```

### 3. 配置脚本路径

编辑 `monorail_run_all.sh`，修改以下变量：

```bash
# 配置路径（在脚本的第 14-17 行）
MONORAIL_DIR="/path/to/monorail-external"          # Monorail 主目录
DATA_DIR="/path/to/your/fastq/files"                # FASTQ 文件所在目录
OUTPUT_DIR="/path/to/monorail-external/output"      # Pump 输出目录
UNIFIER_WORKING_DIR="/path/to/unifier_working_all"  # Unifier 工作目录

# 参数配置（在脚本的第 24-28 行）
REFERENCE="grcm38"        # 或 "hg38" 对于人类
NUM_CPUS=20               # 根据你的系统调整
STUDY_ID="PRJ0004"        # 你的项目ID
PROJECT_ID="loc:140"      # 项目编号（100-249之间）
```

### 4. 准备数据目录结构

```bash
# 你的数据目录应该是这样的结构：
/path/to/your/fastq/files/
├── M40/
│   ├── M40_1.fq.gz
│   └── M40_2.fq.gz
├── M41/
│   ├── M41_1.fq.gz
│   └── M41_2.fq.gz
├── M42/
│   ├── M42_1.fq.gz
│   └── M42_2.fq.gz
└── ...
```

或者，如果只有样本列表，修改脚本中的 `SAMPLES` 数组（第 31 行）：

```bash
# 自动检测所有样本（默认）
SAMPLES=($(ls -d ${DATA_DIR}/*/ 2>/dev/null | xargs -n1 basename))

# 或者手动指定
SAMPLES=(M40 M41 M42 M43 M44)
```

---

## 📖 使用方法

### 基本用法

#### 1. 交互式模式（推荐首次使用）

```bash
./monorail_run_all.sh
```

**特点**：
- 对每个已完成的样本会询问是否跳过
- 遇到错误时会询问是否继续
- 适合首次运行、调试、或不确定哪些样本需要重新运行

**交互示例**：
```
处理样本: M40
------------------------------------------
✓ 样本 M40 已完成 pump
  是否跳过? (y=跳过, n=删除并重新运行): y
  跳过样本 M40
```

#### 2. 批处理模式（推荐大规模运行）

```bash
./monorail_run_all.sh --batch
# 或
./monorail_run_all.sh -b
```

**特点**：
- 自动跳过所有已完成的样本
- 遇到错误继续处理下一个样本
- 适合大批量处理、无人值守运行、续跑中断的任务

### 运行流程

脚本会自动执行以下步骤：

```
步骤 1: 运行 recount-pump (对每个样本)
   └─> 比对、定量、生成 BigWig 文件
   
步骤 2: 准备 Unifier 输入
   ├─> 创建 sample_metadata.tsv
   └─> 创建 ids.tsv（样本ID映射）
   
步骤 3: 创建符号链接结构
   └─> 为 Unifier 准备输入目录结构
   
步骤 4: 运行 recount-unify
   └─> 聚合所有样本的表达数据
   
步骤 5: 整理结果
   └─> 复制到最终结果目录
```

### 运行时间估算

- **Pump**: 约 5-30 分钟/样本（取决于测序深度和 CPU 数量）
- **Unifier**: 约 10-60 分钟（取决于样本数量）
- **31 个样本总计**: 约 3-15 小时

---

## 📦 输出结果

### 结果目录结构

所有结果保存在最终结果目录中（默认：`/mnt/scratch/yuankeji/monorail_final_results/`）：

```
monorail_final_results/
├── gene_sums_per_study/           # ⭐ 基因表达矩阵（主要结果）
│   └── 04/PRJ0004/
│       ├── loc_gene_sums_PRJ0004.M023      # 小鼠基因
│       ├── loc_gene_sums_PRJ0004.ERCC      # ERCC 对照
│       └── loc_gene_sums_PRJ0004.SIRV      # SIRV 对照
│
├── exon_sums_per_study/           # 外显子表达矩阵
│   └── 04/PRJ0004/
│       └── loc_exon_sums_PRJ0004.M023
│
├── junction_counts_per_study/     # 剪接位点计数
│   └── 04/PRJ0004/
│       ├── loc_junctions_PRJ0004.ID.gz
│       ├── loc_junctions_PRJ0004.MM.gz
│       └── loc_junctions_PRJ0004.RR.gz
│
├── metadata/                       # 元数据
│   └── PRJ0004/
│       └── loc.recount_project.PRJ0004.MD.gz
│
├── samples.tsv                     # 样本信息表
├── qc.tsv                          # 质量控制报告
├── ids.tsv                         # 样本ID映射
├── sample_metadata.tsv             # 输入元数据
└── SUMMARY.txt                     # 运行摘要
```

### 主要结果文件

#### 1. 基因表达矩阵 ⭐

**文件**: `gene_sums_per_study/04/PRJ0004/loc_gene_sums_PRJ0004.M023`

这是**最重要**的输出文件，包含：
- 所有样本的所有基因表达量
- 格式：基因 × 样本矩阵
- 数值：原始 read counts（未标准化）

**文件格式**：
```
##annotation=M023
##date.generated=2025-11-18 11:30:32
gene_id                  M40    M41    M42    M43    ...
ENSMUSG00000000001.1     1234   2345   3456   4567   ...
ENSMUSG00000000002.2     567    890    123    456    ...
...
```

**大小**: 约 55,421 行（基因数） × 你的样本数

#### 2. 质量控制报告

**文件**: `qc.tsv`

包含每个样本的质量指标：
- 比对率
- 测序深度
- 重复率
- 检测到的基因数
- 剪接位点数量

#### 3. 样本信息

**文件**: `samples.tsv`

包含每个样本的元数据和统计信息。

---

## 🔬 下游分析

### 在 R 中读取基因表达矩阵

```r
# 读取基因表达数据
gene_counts <- read.table(
    "gene_sums_per_study/04/PRJ0004/loc_gene_sums_PRJ0004.M023",
    header = TRUE,
    row.names = 1,
    comment.char = "#"
)

# 查看数据
dim(gene_counts)           # 维度：基因数 × 样本数
head(gene_counts)          # 前几行
colnames(gene_counts)      # 样本名称

# 基本统计
colSums(gene_counts)                    # 每个样本的总 reads
colSums(gene_counts > 0)                # 每个样本检测到的基因数
```

### 使用 DESeq2 进行差异表达分析

```r
library(DESeq2)

# 1. 准备样本信息表
sample_info <- data.frame(
    sample_id = colnames(gene_counts),
    condition = c(rep("control", 15), rep("treatment", 16)),  # 根据实际情况修改
    row.names = colnames(gene_counts)
)

# 2. 创建 DESeq2 对象
dds <- DESeqDataSetFromMatrix(
    countData = gene_counts,
    colData = sample_info,
    design = ~ condition
)

# 3. 过滤低表达基因
keep <- rowSums(counts(dds)) >= 10
dds <- dds[keep,]

# 4. 运行差异表达分析
dds <- DESeq(dds)
res <- results(dds)

# 5. 查看结果
summary(res)
head(res[order(res$padj),])

# 6. 可视化
plotMA(res)
plotDispEsts(dds)

# PCA 图
vsd <- vst(dds, blind = FALSE)
plotPCA(vsd, intgroup = "condition")
```

### 使用 edgeR

```r
library(edgeR)

# 1. 创建 DGEList 对象
group <- factor(c(rep("control", 15), rep("treatment", 16)))
dge <- DGEList(counts = gene_counts, group = group)

# 2. 过滤低表达基因
keep <- filterByExpr(dge)
dge <- dge[keep, , keep.lib.sizes = FALSE]

# 3. 标准化
dge <- calcNormFactors(dge)

# 4. 设计矩阵和离散度估计
design <- model.matrix(~group)
dge <- estimateDisp(dge, design)

# 5. 差异表达分析
fit <- glmQLFit(dge, design)
qlf <- glmQLFTest(fit, coef = 2)

# 6. 查看结果
topTags(qlf)
```

### 数据质量检查

```r
# 1. 测序深度分布
library(ggplot2)
depth <- data.frame(
    sample = colnames(gene_counts),
    total_reads = colSums(gene_counts)
)
ggplot(depth, aes(x = sample, y = total_reads)) +
    geom_bar(stat = "identity") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    labs(title = "Sequencing Depth per Sample")

# 2. 基因检测率
detected <- colSums(gene_counts > 0)
barplot(detected, las = 2, main = "Number of Detected Genes")

# 3. 样本相关性热图
library(pheatmap)
cor_matrix <- cor(log2(gene_counts + 1))
pheatmap(cor_matrix, 
         clustering_distance_rows = "correlation",
         clustering_distance_cols = "correlation")

# 4. PCA 分析
pca <- prcomp(t(log2(gene_counts + 1)), scale. = TRUE)
pca_data <- data.frame(
    PC1 = pca$x[,1],
    PC2 = pca$x[,2],
    sample = colnames(gene_counts)
)
ggplot(pca_data, aes(x = PC1, y = PC2, label = sample)) +
    geom_point(size = 3) +
    geom_text(vjust = -1) +
    labs(title = "PCA of Gene Expression")
```

---

## ❓ 常见问题

### Q1: 如何处理已完成的样本？

**A**: 使用批处理模式会自动跳过：
```bash
./monorail_run_all.sh --batch
```

或在交互模式中选择 "y" 跳过。

### Q2: 某个样本失败了怎么办？

**A**: 
```bash
# 1. 查看该样本的日志
ls -lh output/SAMPLE_att0/*.log
tail output/SAMPLE_att0/*.log

# 2. 删除失败的输出
rm -rf output/SAMPLE_att0

# 3. 重新运行（会只处理缺失的样本）
./monorail_run_all.sh --batch
```

### Q3: 中断后如何继续？

**A**: 直接重新运行脚本即可，已完成的样本会被自动跳过：
```bash
./monorail_run_all.sh --batch
```

### Q4: 如何只处理特定的几个样本？

**A**: 编辑脚本，修改 `SAMPLES` 数组：
```bash
# 在脚本的第 31 行左右
SAMPLES=(M40 M41 M42)  # 只处理这三个样本
```

### Q5: 如何强制重新运行所有样本？

**A**: 
```bash
# 删除所有 pump 输出
rm -rf /path/to/output/*_att0

# 删除 unifier 工作目录
rm -rf /path/to/unifier_working_all

# 重新运行
./monorail_run_all.sh --batch
```

### Q6: 内存不足怎么办？

**A**: 
1. 减少 CPU 数量（在脚本中修改 `NUM_CPUS`）
2. 对于人类基因组，至少需要 32 GB 内存
3. 考虑分批处理样本

### Q7: 磁盘空间不足怎么办？

**A**: 
- Pump 输出约 10-100 MB/样本
- 可以在 pump 完成后删除中间文件（BAM 文件）
- 设置环境变量 `KEEP_BAM=0`（默认不保留）

### Q8: 如何查看运行进度？

**A**: 
```bash
# 查看已完成的样本数
ls -d output/*_att0 | wc -l

# 实时监控某个样本的运行
tail -f output/M40_att0/std.out

# 查看 Unifier 进度
tail -f unifier_working_all/recount-unify.output.sums.txt
```

### Q9: ids.tsv 出现 ERROR 怎么办？

**A**: 脚本已经处理了这个问题，使用 `SKIP_PREP=1` 和手动创建的 `ids.tsv`。如果仍然出现，手动清理：
```bash
# 删除 ERROR 行
grep -v "ERROR" unifier_working_all/ids.tsv > ids.tsv.clean
mv ids.tsv.clean unifier_working_all/ids.tsv
```

### Q10: 如何更改 rail_id 起始值？

**A**: 编辑脚本中的 `RAIL_ID_START` 变量（第 34 行）：
```bash
RAIL_ID_START=1400000  # 改成你想要的值
```

---

## 🔧 高级用法

### 自定义参数

#### 修改 CPU 数量
```bash
# 在脚本中（第 27 行）
NUM_CPUS=40  # 根据你的系统调整
```

#### 保留 BAM 文件
```bash
# 在运行脚本前设置环境变量
export KEEP_BAM=1
./monorail_run_all.sh --batch
```

#### 使用不同的参考基因组
```bash
# 在脚本中（第 26 行）
REFERENCE="hg38"  # 对于人类样本
```

### 分批处理大量样本

如果有 100+ 个样本，建议分批处理：

```bash
# 1. 修改脚本，只处理一部分样本
SAMPLES=(M40 M41 M42 ... M60)  # 第一批

# 2. 运行第一批
./monorail_run_all.sh --batch

# 3. 修改脚本，处理下一批
SAMPLES=(M61 M62 M63 ... M80)  # 第二批

# 4. 运行第二批
./monorail_run_all.sh --batch

# 5. 所有批次完成后，运行一次 Unifier 聚合所有结果
```

### 在集群上运行

如果使用 SLURM 或其他作业调度系统：

```bash
#!/bin/bash
#SBATCH --job-name=monorail
#SBATCH --cpus-per-task=20
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=monorail_%j.log

module load singularity

cd /path/to/working/directory
./monorail_run_all.sh --batch
```

### 并行处理样本

如果想同时运行多个样本的 pump（需要足够的资源）：

```bash
# 使用 GNU parallel（需要安装）
export SKIP_UNIFIER=1  # 先只运行 pump

# 并行运行 pump（4个样本同时）
parallel -j 4 './run_recount_pump.sh ...' ::: M40 M41 M42 M43

# 所有 pump 完成后，运行 unifier
./monorail_run_all.sh --batch
```

---

## 📚 参考资源

### Monorail 文档
- GitHub: https://github.com/langmead-lab/monorail-external
- recount3 论文: Wilks et al. (2021) Genome Biology

### recount3 R 包
- Bioconductor: http://bioconductor.org/packages/release/bioc/html/recount3.html
- 使用 recount3 加载自定义数据

### 相关工具
- DESeq2: https://bioconductor.org/packages/DESeq2/
- edgeR: https://bioconductor.org/packages/edgeR/
- STAR: https://github.com/alexdobin/STAR
- Salmon: https://github.com/COMBINE-lab/salmon

---

## 📝 引用

如果使用 Monorail 进行分析，请引用：

> Wilks, C., Zheng, S.C., Chen, F.Y. et al. recount3: summaries and queries for large-scale RNA-seq expression and splicing. Genome Biol 22, 323 (2021). https://doi.org/10.1186/s13059-021-02533-6

---

## 🐛 故障排除

### 日志文件位置

- **Pump 日志**: `output/SAMPLE_att0/*.log`
- **Unifier 日志**: `unifier_working_all/.snakemake/log/*.log`
- **脚本输出**: 保存终端输出到文件：`./monorail_run_all.sh --batch 2>&1 | tee run.log`

### 常见错误

#### 错误 1: "Missing input files for rule tar_logs: links"
**解决**: 脚本已经修复此问题，确保使用最新版本。

#### 错误 2: "FATAL: container creation failed"
**解决**: 检查 Singularity 镜像路径是否正确。

#### 错误 3: 内存溢出 (OOM)
**解决**: 减少 `NUM_CPUS` 或增加系统内存。

#### 错误 4: 找不到参考文件
**解决**: 
```bash
# 重新下载参考文件
cd /path/to/monorail-external
./get_mouse_ref_indexes.sh  # 或 get_human_ref_indexes.sh
./get_unify_refs.sh grcm38  # 或 hg38
```

---

## 📞 获取帮助

如果遇到问题：

1. **检查日志文件**：查看详细的错误信息
2. **查看 GitHub Issues**: https://github.com/langmead-lab/monorail-external/issues
3. **Monorail 文档**: 阅读原始文档了解更多细节

---

## 📄 许可证

Monorail 使用 MIT 许可证。

---

## 🎉 完成！

恭喜！你现在已经掌握了如何使用 Monorail 批处理脚本。祝你的 RNA-seq 分析顺利！

如有任何问题或建议，欢迎反馈。