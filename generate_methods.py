#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

# Create a new Document
doc = Document()

# Set default font
style = doc.styles['Normal']
font = style.font
font.name = 'Times New Roman'
font.size = Pt(12)

# Title
title = doc.add_heading('Methods', level=1)
title.alignment = WD_ALIGN_PARAGRAPH.CENTER

# Section 1: Data Collection and Preprocessing
heading1 = doc.add_heading('Data Collection and Preprocessing', level=2)

p1 = doc.add_paragraph(
    'Single-cell RNA sequencing (scRNA-seq) datasets were obtained from the Gene Expression Omnibus '
    '(GEO, https://www.ncbi.nlm.nih.gov/geo/) database [1], including GSE199515, GSE176078, and GSE161529. '
    'These datasets comprised 3 normal breast tissue samples and 16 TNBC tumor samples, totaling 84,837 '
    'high-quality cells after quality control and batch effect correction. Bulk transcriptomic data and '
    'clinical information for TNBC patients were downloaded from multiple sources: (1) The Cancer Genome '
    'Atlas (TCGA) breast cancer cohort was accessed via the UCSC Xena browser (https://xenabrowser.net/) [2], '
    'from which 116 TNBC patients with complete gene expression profiles and survival information were selected '
    'and randomly divided into training (n=82) and internal test (n=34) cohorts at a 7:3 ratio using stratified '
    'sampling; (2) GSE25066 dataset containing microarray data and clinical information from 508 TNBC samples '
    'was retrieved from GEO for external validation; (3) Additional validation was performed using the Molecular '
    'Taxonomy of Breast Cancer International Consortium (METABRIC) dataset obtained from the cBioPortal database '
    '(http://www.cbioportal.org/) [3]. After excluding non-primary breast cancer cases or patients lacking complete '
    'gene expression profiles, 298 primary TNBC patients from METABRIC were included. A curated list of 807 '
    'ubiquitination-related genes was obtained from a previous study [4].'
)

# Section 2: Single-Cell RNA Sequencing Data Processing
heading2 = doc.add_heading('Single-Cell RNA Sequencing Data Processing', level=2)

p2 = doc.add_paragraph(
    'scRNA-seq data processing and analysis were performed using the Seurat package (version 4.3.0) in R '
    '(version 4.2.0) [5, 6]. Raw count matrices were converted to Seurat objects using the CreateSeuratObject '
    'function with minimum feature count of 200 genes per cell and minimum cell count of 3 cells per feature. '
    'Quality control steps included: (1) Excluding low-quality cells expressing fewer than 200 genes; '
    '(2) Removing potential doublets using the DoubletFinder package (version 2.0.3) with expected doublet rate '
    'set to 0.075 [7]; (3) Filtering cells expressing more than 6,000 genes or with mitochondrial gene content '
    'exceeding 25% of total counts; (4) Normalizing gene expression matrices using the LogNormalize method with '
    'a scale factor of 10,000; (5) Identifying the 2,000 most highly variable features using variance-stabilizing '
    'transformation (vst) method; (6) Integrating individual datasets using the Harmony algorithm [8] to eliminate '
    'batch effects while preserving biological variation.'
)

# Section 3: Dimensionality Reduction, Clustering, and Cell Type Annotation
heading3 = doc.add_heading('Dimensionality Reduction, Clustering, and Cell Type Annotation', level=2)

p3 = doc.add_paragraph(
    'Gene expression data were scaled using the ScaleData function, regressing out mitochondrial percentage. '
    'Principal component analysis (PCA) was performed using the RunPCA function, and the first 50 principal '
    'components were retained based on elbow plot and jackstraw analysis. Unsupervised clustering was performed '
    'using the FindNeighbors and FindClusters functions with resolution parameter set to 0.1, yielding 11 distinct '
    'cell clusters. Dimensionality reduction for visualization was performed using Uniform Manifold Approximation '
    'and Projection (UMAP) [9] through the RunUMAP function. Cell type annotation was conducted through: '
    '(1) Automated preliminary annotation using the SingleR package [10] with Human Primary Cell Atlas reference; '
    '(2) Manual validation based on canonical marker genes identified by FindAllMarkers function; (3) Cross-referencing '
    'with the CellMarker 2.0 database (http://bio-bigdata.hrbmu.edu.cn/CellMarker/) [11]. Representative marker genes '
    'included: epithelial cells (EPCAM, KRT18), T cells (CD3D, CD3E), proliferating epithelial cells (MKI67, TOP2A), '
    'macrophages (CD68, CD163), fibroblasts (COL1A1, DCN), basal cells (KRT14, KRT5), endothelial cells (PECAM1, VWF), '
    'luminal epithelial cells (KRT8, KRT19), plasma cells (JCHAIN, MZB1), pericytes (RGS5, ACTA2), and B cells '
    '(CD79A, MS4A1).'
)

# Section 4: Differential Expression Analysis
heading4 = doc.add_heading('Differential Expression Analysis', level=2)

p4 = doc.add_paragraph(
    'Differentially expressed genes (DEGs) between TNBC and normal breast tissue across individual cell types were '
    'identified using the FindMarkers function in Seurat. For each cell type, genes were tested using the Wilcoxon '
    'rank-sum test with the following criteria: minimum percentage of cells expressing the gene in either group ≥ 25%, '
    'log2 fold-change threshold ≥ 0.25, and adjusted P value < 0.05 using Bonferroni correction. Gene Ontology (GO) '
    'enrichment analysis was performed using the clusterProfiler package (version 4.6.0) [12] with adjusted P value < 0.01 '
    'to identify enriched biological processes, cellular components, and molecular functions.'
)

# Section 5: Cell-Cell Communication Network Analysis
heading5 = doc.add_heading('Cell-Cell Communication Network Analysis', level=2)

p5 = doc.add_paragraph(
    'Cell-cell communication networks were analyzed using CellChat (version 1.6.0) [13]. Seurat objects were converted '
    'to CellChat format using the createCellChat function. The analysis included: (1) Identifying overexpressed ligands '
    'and receptors using identifyOverExpressedGenes and identifyOverExpressedInteractions functions; (2) Projecting gene '
    'expression data onto protein-protein interaction networks; (3) Computing communication probabilities using '
    'computeCommunProb function; (4) Inferring signaling pathways using computeCommunProbPathway function; '
    '(5) Aggregating networks using aggregateNet function. Separate CellChat objects were created for normal and TNBC '
    'tissues and merged using mergeCellChat function for comparison. Statistical significance was assessed using '
    'permutation tests with 100 iterations.'
)

# Section 6: Identification of T Cell-Related Ubiquitination Genes
heading6 = doc.add_heading('Identification of T Cell-Related Ubiquitination Genes', level=2)

p6 = doc.add_paragraph(
    'To identify T cell-related ubiquitination genes (TCRUG) with prognostic potential, we implemented a multi-step '
    'strategy. First, DEGs in T cells between TNBC and normal samples were extracted from single-cell analysis results. '
    'Second, these T cell DEGs were intersected with the curated database of 807 ubiquitination-related genes [4], '
    'generating a focused set of 177 TCRUG. Third, expression matrices for these 177 genes were extracted from bulk '
    'transcriptomic datasets for subsequent network analysis and prognostic model construction.'
)

# Section 7: Weighted Gene Co-expression Network Analysis
heading7 = doc.add_heading('Weighted Gene Co-expression Network Analysis', level=2)

p7 = doc.add_paragraph(
    'Weighted gene co-expression network analysis (WGCNA) was performed using the WGCNA package (version 1.71) [14] '
    'on the 177 TCRUG using expression data from GSE58812. The workflow included: (1) Sample quality assessment and '
    'outlier detection using hierarchical clustering; (2) Determining optimal soft-thresholding power (β=6) to achieve '
    'scale-free topology fit index (R²) > 0.85; (3) Calculating adjacency matrix and transforming to topological overlap '
    'matrix (TOM); (4) Hierarchical clustering and module identification using dynamic tree cut algorithm with minimum '
    'module size of 30 genes and deepSplit parameter of 2; (5) Calculating module eigengenes (MEs); (6) Correlating MEs '
    'with overall survival time using Pearson correlation. Modules with P < 0.05 were selected for further analysis.'
)

# Section 8: Construction and Validation of Prognostic Risk Model
heading8 = doc.add_heading('Construction and Validation of Prognostic Risk Model', level=2)

p8 = doc.add_paragraph(
    'A prognostic model was developed through a three-tiered filtering strategy. First, genes from the survival-associated '
    'WGCNA module (MEturquoise, 61 genes) were subjected to differential expression analysis between tumor and normal '
    'tissues using datasets GSE6522 and GSE6594 (P < 0.05), identifying 59 dysregulated genes. Second, univariate Cox '
    'regression analysis [15] identified 30 genes significantly associated with survival (P < 0.05). Third, Kaplan-Meier '
    'survival analysis using median expression cutoffs identified 21 genes with significant prognostic discrimination '
    '(log-rank P < 0.05). The intersection yielded 13 high-confidence prognostic genes.'
)

p8_2 = doc.add_paragraph(
    'LASSO penalized Cox regression was performed on the 13 candidate genes using the glmnet package (version 4.1-6) [16]. '
    'The optimal regularization parameter (λ) was determined by 10-fold cross-validation. This selected three genes—GMCL1, '
    'KRT8, and OTUB1—for the final model. Risk score was calculated as: Risk Score = Σ(βᵢ × Exprᵢ), where βᵢ is the '
    'LASSO-Cox coefficient and Exprᵢ is the normalized expression level. Patients were divided into high-risk and low-risk '
    'groups using the median risk score as cutoff.'
)

p8_3 = doc.add_paragraph(
    'Model validation was conducted across multiple cohorts. The TCGA-TNBC cohort (n=116) was randomly divided into '
    'training (n=82) and internal test (n=34) sets at a 7:3 ratio using stratified sampling. External validation used '
    'GSE25066 (n=508). For each cohort, Kaplan-Meier survival curves were compared using log-rank tests. Hazard ratios '
    '(HR) and 95% confidence intervals (CI) were calculated using Cox regression. Time-dependent ROC curve analysis was '
    'performed using the timeROC package [17] to evaluate discriminatory capacity at 2-year, 3-year, and 5-year survival '
    'timepoints, with area under the curve (AUC) values calculated.'
)

# Section 9: Assessment of Independent Prognostic Value
heading9 = doc.add_heading('Assessment of Independent Prognostic Value', level=2)

p9 = doc.add_paragraph(
    'Univariate and multivariate Cox regression analyses were conducted to assess independent prognostic value. Clinical '
    'variables included age at diagnosis (continuous), tumor stage (T1-T4), lymph node stage (N0-N3), tumor grade (Grade 1-3), '
    'and the molecular risk score (continuous). Variables with P < 0.1 in univariate analysis were incorporated into '
    'multivariate Cox regression. Hazard ratios, 95% confidence intervals, and P values were calculated. The proportional '
    'hazards assumption was verified using Schoenfeld residuals test.'
)

# Section 10: Development and Validation of Clinical Nomogram
heading10 = doc.add_heading('Development and Validation of Clinical Nomogram', level=2)

p10 = doc.add_paragraph(
    'An integrated nomogram was developed using the rms package (version 6.3-0) [18], incorporating the three-gene risk '
    'score and clinicopathological variables (age, T stage, N stage, tumor grade). Each variable was assigned points based '
    'on its regression coefficient, with total scores corresponding to predicted survival probabilities at 1, 3, and 5 years. '
    'Calibration was assessed by comparing predicted versus observed survival probabilities using calibration plots with '
    '1,000 bootstrap resamples. Discriminatory performance was evaluated by concordance index (C-index) and time-dependent '
    'AUC values. Decision curve analysis assessed clinical utility across different threshold probabilities.'
)

# Section 11: Statistical Analysis
heading11 = doc.add_heading('Statistical Analysis', level=2)

p11 = doc.add_paragraph(
    'All statistical analyses were performed using R software (version 4.2.0) [19]. Continuous variables were compared '
    'using Wilcoxon rank-sum test for non-normally distributed data or Student\'s t-test for normally distributed data '
    'after Shapiro-Wilk test. Categorical variables were compared using Chi-square test or Fisher\'s exact test as '
    'appropriate. Survival curves were generated using Kaplan-Meier method and compared using log-rank test. Cox '
    'proportional hazards regression [15] was used to evaluate prognostic factors and calculate hazard ratios with 95% '
    'confidence intervals. Time-dependent ROC curves were constructed using the timeROC package [17]. Nomogram construction '
    'and validation were performed using the rms package [18]. Multiple testing correction was applied using Bonferroni '
    'method or false discovery rate (FDR) approach where appropriate. Data visualization was performed using ggplot2 '
    '(version 3.4.0) [20], ComplexHeatmap (version 2.14.0) [21], and other R graphics packages. All tests were two-sided, '
    'and P < 0.05 was considered statistically significant unless otherwise specified.'
)

# Save the document
doc.save('/home/user/data_bricks/method_runse.docx')
print("Document generated successfully: method_runse.docx")
