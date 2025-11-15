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
    'These datasets comprised 3 normal breast tissue samples and 16 triple-negative breast cancer (TNBC) tumor '
    'samples, totaling 84,837 high-quality cells after rigorous quality control and batch effect correction. '
    'Bulk transcriptomic data and corresponding clinical information for TNBC patients were retrieved from '
    'multiple public repositories: (1) The Cancer Genome Atlas (TCGA) breast cancer cohort was accessed via the '
    'UCSC Xena browser (https://xenabrowser.net/) [2], from which 116 TNBC patients with complete gene expression '
    'profiles and survival data were identified and randomly divided into training (n=82) and internal test (n=34) '
    'cohorts using a 7:3 ratio through stratified sampling to maintain balanced outcome distributions; '
    '(2) The GSE25066 dataset, containing microarray-based expression data and clinical annotations from 508 TNBC '
    'samples, was retrieved from GEO for independent external validation; (3) Additional validation was performed '
    'using the Molecular Taxonomy of Breast Cancer International Consortium (METABRIC) dataset obtained from the '
    'cBioPortal database (http://www.cbioportal.org/) [3]. Following exclusion of non-primary breast cancer cases '
    'and patients lacking complete gene expression profiles, 298 primary TNBC patients from METABRIC were included '
    'in the validation cohort. A curated list of 807 ubiquitination-related genes was obtained from a comprehensive '
    'literature-based study [4].'
)

# Section 2: Single-Cell RNA Sequencing Data Processing
heading2 = doc.add_heading('Single-Cell RNA Sequencing Data Processing', level=2)

p2 = doc.add_paragraph(
    'All scRNA-seq data processing and downstream analyses were performed using the Seurat package (version 4.3.0) '
    'implemented in R (version 4.2.0) [5, 6]. Raw count matrices were converted to Seurat objects using the '
    'CreateSeuratObject function with the following initial filtering parameters: minimum feature count of 200 genes '
    'per cell and minimum cell count of 3 cells per feature to ensure data quality. Quality control and preprocessing '
    'comprised multiple sequential steps: (1) Low-quality cells expressing fewer than 200 genes were excluded to remove '
    'empty droplets and cellular debris; (2) Potential doublets were systematically identified and removed using the '
    'DoubletFinder package (version 2.0.3) with the expected doublet formation rate set to 0.075 (7.5%) according to '
    '10x Genomics technical specifications [7]; (3) Cells expressing more than 6,000 genes or exhibiting mitochondrial '
    'gene content exceeding 25% of total transcript counts were filtered out to eliminate potential multiplets and '
    'dead or dying cells; (4) Gene expression matrices were normalized using the LogNormalize method implemented in the '
    'NormalizeData function with a scaling factor of 10,000 to account for differences in sequencing depth across cells; '
    '(5) The 2,000 most highly variable features were identified using the variance-stabilizing transformation (vst) '
    'method in the FindVariableFeatures function to capture biological variation while reducing technical noise; '
    '(6) To eliminate technical batch effects while preserving genuine biological variation across datasets, individual '
    'datasets were integrated using the Harmony algorithm [8], which has been demonstrated to perform robustly and '
    'efficiently across diverse single-cell experimental platforms and biological contexts.'
)

# Section 3: Dimensionality Reduction, Clustering, and Cell Type Annotation
heading3 = doc.add_heading('Dimensionality Reduction, Clustering, and Cell Type Annotation', level=2)

p3 = doc.add_paragraph(
    'Following successful integration, gene expression data were scaled using the ScaleData function to generate '
    'z-scores for each variable gene, with regression to remove unwanted sources of variation including mitochondrial '
    'gene percentage. Principal component analysis (PCA) was performed on the scaled data using the RunPCA function, '
    'and the optimal number of principal components (PCs) was determined through systematic examination of elbow plots '
    'and jackstraw resampling analysis. Based on these comprehensive evaluations, the first 50 principal components were '
    'retained for subsequent downstream analyses to capture the majority of biological variation. Unsupervised graph-based '
    'clustering was performed using the FindNeighbors and FindClusters functions with the resolution parameter set to 0.1 '
    'to identify major cell types while avoiding over-fragmentation, ultimately yielding 11 distinct cell clusters. '
    'For visualization purposes, dimensionality reduction was performed using Uniform Manifold Approximation and Projection '
    '(UMAP) [9] through the RunUMAP function, which projects high-dimensional data into two-dimensional space while '
    'preserving both local and global structure. Cell type annotation was conducted through a rigorous multi-step approach: '
    '(1) Automated preliminary annotation was performed using the SingleR package [10] with reference datasets from the '
    'Human Primary Cell Atlas to provide initial cell type assignments; (2) Manual curation and validation were conducted '
    'based on canonical marker genes identified through the FindAllMarkers function using Wilcoxon rank-sum tests; '
    '(3) Cross-referencing with established markers from extensive literature review and the CellMarker 2.0 database '
    '(http://bio-bigdata.hrbmu.edu.cn/CellMarker/) [11] to ensure annotation accuracy. Representative marker genes used '
    'for definitive annotation included: epithelial cells (EPCAM, KRT18), T cells (CD3D, CD3E), proliferating epithelial '
    'cells (MKI67, TOP2A), macrophages (CD68, CD163), fibroblasts (COL1A1, DCN), basal cells (KRT14, KRT5), endothelial '
    'cells (PECAM1, VWF), luminal epithelial cells (KRT8, KRT19), plasma cells (JCHAIN, MZB1), pericytes (RGS5, ACTA2), '
    'and B cells (CD79A, MS4A1).'
)

# Section 4: Differential Expression Analysis
heading4 = doc.add_heading('Differential Expression Analysis', level=2)

p4 = doc.add_paragraph(
    'To comprehensively characterize transcriptional differences between TNBC tumor tissues and adjacent normal breast '
    'tissue across individual cell types, differentially expressed genes (DEGs) were identified using the FindMarkers '
    'function implemented in Seurat. For each annotated cell type, genes showing differential expression between tumor '
    'and normal samples were identified using the non-parametric Wilcoxon rank-sum test with the following stringent '
    'statistical criteria: minimum percentage of cells expressing the gene in either group ≥ 25%, absolute log2 '
    'fold-change threshold ≥ 0.25, and adjusted P value < 0.05 using Bonferroni correction for multiple hypothesis testing. '
    'To identify distinctive markers specific to each cell cluster for robust annotation purposes, the FindAllMarkers '
    'function was employed with identical statistical parameters. Functional enrichment analysis based on Gene Ontology (GO) '
    'terms was performed using the clusterProfiler package (version 4.6.0) [12] with a significance threshold of adjusted '
    'P value < 0.01 to identify biological processes, cellular components, and molecular functions significantly enriched '
    'in the identified DEGs, thereby providing biological context to the observed transcriptional changes.'
)

# Section 5: Cell-Cell Communication Network Analysis
heading5 = doc.add_heading('Cell-Cell Communication Network Analysis', level=2)

p5 = doc.add_paragraph(
    'To systematically characterize intercellular communication networks within the TNBC tumor microenvironment, we employed '
    'CellChat (version 1.6.0) [13], a state-of-the-art computational framework that quantitatively infers cell-cell communication '
    'based on expression patterns of known ligand-receptor pairs and their associated cofactors. Seurat objects containing '
    'normalized expression data and validated cell type annotations were converted to the CellChat-compatible format using the '
    'createCellChat function. The comprehensive analysis workflow comprised the following sequential steps: (1) Preprocessing of '
    'expression data using identifyOverExpressedGenes and identifyOverExpressedInteractions functions to identify significantly '
    'overexpressed ligands and receptors in each cell type compared to the overall population; (2) Projection of gene expression '
    'data onto the protein-protein interaction (PPI) network using the projectData function to account for potential cofactors '
    'and regulatory proteins; (3) Computation of communication probability between all cell type pairs using the computeCommunProb '
    'function with default mass-action-based modeling parameters; (4) Inference of cellular communication networks at the signaling '
    'pathway level using the computeCommunProbPathway function to aggregate individual ligand-receptor interactions into biologically '
    'meaningful pathways; (5) Calculation of aggregated cell-cell communication networks using the aggregateNet function to quantify '
    'overall interaction strength between cell populations. To systematically compare communication patterns between normal breast '
    'tissue and TNBC tumor microenvironments, separate CellChat objects were created for each condition and subsequently merged using '
    'the mergeCellChat function. Differential patterns in signaling pathway activity, interaction strength, and information flow were '
    'visualized using built-in visualization functions including netVisual_circle for circular network plots, netVisual_heatmap for '
    'heatmap representations, and rankNet for ranking pathway activities. Statistical significance of differential interactions was '
    'rigorously assessed using permutation tests with 100 iterations to establish empirical null distributions.'
)

# Section 6: Identification of T Cell-Related Ubiquitination Genes
heading6 = doc.add_heading('Identification of T Cell-Related Ubiquitination Genes', level=2)

p6 = doc.add_paragraph(
    'To identify T cell-related ubiquitination genes (TCRUG) with prognostic potential in TNBC, we implemented a systematic '
    'multi-step integration strategy. First, differentially expressed genes (DEGs) in T cells between TNBC and normal samples '
    'were extracted from the single-cell analysis results based on the statistical criteria described above. Second, these '
    'T cell-specific DEGs were intersected with the curated database of 807 ubiquitination-related genes [4] to generate a '
    'focused set of 177 candidate TCRUG that are both T cell-relevant and involved in ubiquitination processes. Third, expression '
    'matrices for these 177 genes were extracted from bulk transcriptomic datasets for subsequent weighted gene co-expression '
    'network analysis and prognostic model construction, thereby bridging single-cell insights with bulk tumor profiling data.'
)

# Section 7: Weighted Gene Co-expression Network Analysis
heading7 = doc.add_heading('Weighted Gene Co-expression Network Analysis', level=2)

p7 = doc.add_paragraph(
    'To identify functionally coordinated gene modules within the 177 candidate TCRUG, weighted gene co-expression network '
    'analysis (WGCNA) was performed using the WGCNA package (version 1.71) in R [14]. Expression data from the GSE58812 dataset '
    'were utilized as the discovery cohort. The comprehensive analysis workflow included the following steps: (1) Assessment of '
    'sample quality and outlier detection using hierarchical clustering with the hclust function to ensure data integrity; '
    '(2) Construction of a scale-free topology network by determining the optimal soft-thresholding power (β) through systematic '
    'evaluation of values ranging from 1 to 20, with β=6 selected to achieve a scale-free topology fit index (R²) > 0.85, '
    'consistent with the scale-free property of biological networks; (3) Calculation of the adjacency matrix using the adjacency '
    'function with the selected soft-thresholding power to quantify co-expression relationships; (4) Transformation of the adjacency '
    'matrix to a topological overlap matrix (TOM) to measure network interconnectedness and reduce noise from spurious correlations; '
    '(5) Hierarchical clustering of genes based on TOM-based dissimilarity measures; (6) Module identification using the dynamic '
    'tree cut algorithm with minimum module size set to 30 genes and deepSplit parameter set to 2 to identify robust co-expression '
    'modules; (7) Calculation of module eigengenes (MEs) representing the first principal component of expression patterns for each '
    'identified module, thereby summarizing module behavior; (8) Correlation analysis between MEs and clinical phenotypes, particularly '
    'overall survival time, using Pearson correlation coefficients with statistical significance determined by Student asymptotic '
    'P values. Gene modules demonstrating significant correlation with survival outcomes (P < 0.05) were selected for further '
    'prognostic analysis to identify clinically relevant co-expression patterns.'
)

# Section 8: Construction and Validation of Prognostic Risk Model
heading8 = doc.add_heading('Construction and Validation of Prognostic Risk Model', level=2)

p8 = doc.add_paragraph(
    'A robust prognostic model was developed through a rigorous three-tiered filtering strategy to ensure both biological relevance '
    'and clinical significance. First, genes from the survival-associated WGCNA module (MEturquoise, containing 61 genes) were '
    'subjected to differential expression analysis between tumor and adjacent normal tissues using the independent datasets GSE6522 '
    'and GSE6594, with the significance threshold set at P < 0.05, successfully identifying 59 significantly dysregulated genes. '
    'Second, univariate Cox proportional hazards regression analysis [15] was performed on these 59 genes using the coxph function '
    'from the survival package, with overall survival as the primary outcome variable, identifying 30 genes significantly associated '
    'with patient survival (P < 0.05). Third, Kaplan-Meier survival analysis was conducted for each of the 30 candidate genes by '
    'stratifying patients into high and low expression groups based on median expression values, with survival differences rigorously '
    'evaluated using the log-rank test, ultimately identifying 21 genes demonstrating significant prognostic discrimination (P < 0.05). '
    'The intersection of these three independent analytical approaches yielded 13 high-confidence prognostic genes that were consistently '
    'validated across all methodological frameworks, thereby minimizing false-positive discoveries.'
)

p8_2 = doc.add_paragraph(
    'To construct a parsimonious prognostic signature while preventing overfitting and ensuring model generalizability, least absolute '
    'shrinkage and selection operator (LASSO) penalized Cox regression analysis was performed on the 13 candidate genes using the glmnet '
    'package (version 4.1-6) [16]. The optimal regularization parameter (λ) was determined through 10-fold cross-validation by identifying '
    'the λ value that minimized partial likelihood deviance, balancing model complexity and predictive performance. This rigorous procedure '
    'selected three genes—GMCL1, KRT8, and OTUB1—with non-zero regression coefficients for inclusion in the final prognostic model. '
    'The risk score for each patient was calculated using the following formula: Risk Score = Σ(βᵢ × Exprᵢ), where βᵢ represents the '
    'LASSO-Cox regression coefficient for gene i and Exprᵢ denotes the normalized expression level of gene i. Patients were dichotomized '
    'into high-risk and low-risk groups using the median risk score as the cutoff threshold to ensure balanced group sizes for subsequent '
    'survival analyses.'
)

p8_3 = doc.add_paragraph(
    'Comprehensive model validation was conducted across multiple independent cohorts to rigorously assess generalizability and robustness. '
    'The TCGA-TNBC cohort (n=116) served as the primary validation dataset, with patients randomly partitioned into training (n=82) and '
    'internal test (n=34) sets using a 7:3 ratio through stratified sampling based on survival status to maintain balanced clinical outcomes. '
    'External validation was performed using the GSE25066 dataset (n=508), which represents an independent patient population profiled on '
    'different microarray platforms and treated according to varying therapeutic protocols, thereby testing model robustness across technical '
    'and clinical heterogeneity. For each validation cohort, Kaplan-Meier survival curves were generated to compare overall survival between '
    'high-risk and low-risk groups, with statistical significance rigorously evaluated using the log-rank test. Hazard ratios (HR) and '
    'corresponding 95% confidence intervals (CI) were calculated using Cox proportional hazards regression to quantify risk magnitude. '
    'Time-dependent receiver operating characteristic (ROC) curve analysis was performed using the timeROC package [17] to evaluate the '
    'discriminatory capacity of the risk model at clinically relevant 2-year, 3-year, and 5-year survival timepoints, with area under the '
    'curve (AUC) values calculated as quantitative measures of predictive accuracy and model discrimination.'
)

# Section 9: Assessment of Independent Prognostic Value
heading9 = doc.add_heading('Assessment of Independent Prognostic Value', level=2)

p9 = doc.add_paragraph(
    'To determine whether the three-gene risk score provides prognostic information independent of established clinicopathological parameters, '
    'comprehensive univariate and multivariate Cox proportional hazards regression analyses were conducted. Clinical variables incorporated in '
    'the analysis comprised age at diagnosis (analyzed as a continuous variable), tumor stage (categorized as T1-T4), lymph node stage '
    '(categorized as N0-N3), tumor grade (categorized as Grade 1-3), and the molecular risk score (analyzed as a continuous variable). Univariate '
    'Cox regression was initially performed to identify individual prognostic factors associated with overall survival. Subsequently, all variables '
    'demonstrating P < 0.1 in univariate analysis were incorporated into a comprehensive multivariate Cox regression model to assess independent '
    'prognostic significance while adjusting for potential confounding factors. Hazard ratios, 95% confidence intervals, and corresponding P values '
    'were calculated for each variable in both univariate and multivariate models to quantify their prognostic impact. The proportional hazards '
    'assumption, a critical requirement for valid Cox regression inference, was rigorously verified using Schoenfeld residuals tests to ensure model '
    'assumptions were satisfied.'
)

# Section 10: Development and Validation of Clinical Nomogram
heading10 = doc.add_heading('Development and Validation of Clinical Nomogram', level=2)

p10 = doc.add_paragraph(
    'To facilitate clinical application and enable individualized risk assessment in routine oncological practice, an integrated predictive nomogram '
    'was developed using the rms package (version 6.3-0) in R [18]. The nomogram incorporated the three-gene risk score along with significant '
    'clinicopathological variables including age, tumor stage (T stage), lymph node stage (N stage), and tumor grade. Each predictor variable was '
    'assigned a point value proportional to its regression coefficient in the multivariate Cox model, with total accumulated point scores corresponding '
    'to predicted survival probabilities at clinically meaningful 1-year, 3-year, and 5-year post-diagnosis timepoints. The nomogram was constructed '
    'using the nomogram function, which graphically displays the relative contribution of each variable to individualized survival prediction. '
    'Model calibration, assessing agreement between predicted and observed outcomes, was rigorously evaluated by comparing nomogram-predicted versus '
    'actual observed survival probabilities at 1, 3, and 5 years using calibration plots generated by the calibrate function with 1,000 bootstrap '
    'resamples to correct for optimism and overfitting. Calibration curves display the relationship between nomogram-predicted probabilities and '
    'actual observed survival rates, with the 45-degree reference line representing perfect calibration. Discriminatory performance of the nomogram '
    'was comprehensively evaluated by calculating the concordance index (C-index) and comparing time-dependent AUC values against individual prognostic '
    'factors to demonstrate added predictive value. Decision curve analysis was performed to assess the clinical utility and net benefit of the nomogram '
    'by quantifying the clinical value across different threshold probabilities, thereby informing clinical decision-making.'
)

# Section 11: Statistical Analysis
heading11 = doc.add_heading('Statistical Analysis', level=2)

p11 = doc.add_paragraph(
    'All statistical analyses were performed using R software (version 4.2.0, R Foundation for Statistical Computing, Vienna, Austria) [19]. '
    'Continuous variables were compared between two groups using the non-parametric Wilcoxon rank-sum test (Mann-Whitney U test) for non-normally '
    'distributed data or the parametric Student\'s t-test for normally distributed data following assessment with the Shapiro-Wilk normality test. '
    'Categorical variables were compared using the Chi-square test or Fisher\'s exact test as appropriate based on expected cell frequencies. '
    'Survival curves were generated using the Kaplan-Meier method and compared between groups using the log-rank test. Univariate and multivariate '
    'Cox proportional hazards regression models [15] were employed to evaluate prognostic factors and calculate hazard ratios with corresponding 95% '
    'confidence intervals. Time-dependent receiver operating characteristic (ROC) curves were constructed using the timeROC package [17] to assess model '
    'performance at specific time points. Nomogram construction, calibration, and validation were performed using the rms package [18]. Multiple testing '
    'correction was applied using the Bonferroni method or false discovery rate (FDR) approach where appropriate to control for type I error inflation. '
    'Data visualization was performed using ggplot2 (version 3.4.0) [20], ComplexHeatmap (version 2.14.0) [21], and other standard R graphics packages '
    'to generate publication-quality figures. All statistical tests were two-sided, and P values < 0.05 were considered statistically significant unless '
    'otherwise explicitly specified.'
)

# Save the document
doc.save('/home/user/data_bricks/method_runse.docx')
print("Document generated successfully: method_runse.docx")
