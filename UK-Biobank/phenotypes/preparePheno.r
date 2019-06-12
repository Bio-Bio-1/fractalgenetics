#################
## libraries ####
#################
options(import.path=c("/homes/hannah/analysis/fractalgenetics/fractal-analysis-processing",
                      "/homes/hannah/projects"))
options(bitmapType = 'cairo', device = 'pdf')

modules::import_package('ggplot2', attach=TRUE)
modules::import_package('GGally', attach=TRUE)
optparse <- modules::import_package('optparse')
ukbtools <- modules::import_package('ukbtools')
related <- modules::import('GWAS/relatedness')
autofd <- modules::import('AutoFD_interpolation')
smooth <- modules::import('utils/smoothAddR2')


#################################
## parameters and input data ####
#################################
option_list <- list(
    make_option(c("-u", "--ukbdir"), action="store", dest="rawdir",
               type="character", help="Path to ukb directory with decrypted ukb
               key.html file [default: %default].", default=NULL),
    make_option(c("-o", "--outdir"), action="store", dest="outdir",
               type="character", help="Path to output directory [default:
               %default].", default=NULL),
    make_option(c("-p", "--pheno"), action="store", dest="pheno",
               type="character", help="Path to fd phenotype file [default:
               %default].", default=NULL),
    make_option(c("-c", "--cov"), action="store", dest="cov",
               type="character", help="Path to LV volume covariate file
               [default: %default].", default=NULL),
    make_option(c("-i", "--interpolate"), action="store", dest="interpolate",
               type="integer", help="Number of slices to interpolate to
               [default: %default].", default=9),
    make_option(c("-s", "--samples"), action="store", dest="samples",
               type="character", help="Path to ukb genotype samples file
               [default: %default].", default=NULL),
    make_option(c("-r", "--relatedness"), action="store", dest="relatedness",
               type="character", help="Path to relatedness file generated by
               ukbgene rel [default: %default].", default=NULL),
    make_option(c("-e", "--europeans"), action="store", dest="europeans",
               type="character", help="Path to European samples file generated
               by ancestry.smk [default: %default].", default=NULL),
    make_option(c("-pcs", "--pcs"), action="store", dest="pcs",
                ptions(import.path="/homes/hannah/GWAS/analysis/fd")
               type="character", help="Path to pca output file generated by
               flashpca [default: %default].", default=NULL),
    optparse$make_option(c("--debug"), action="store_true",
               dest="debug", default=FALSE, type="logical",
               help="If set, predefined arguments are used to test the script
               [default: %default].")
)

args <- optparse$parse_args(OptionParser(option_list=option_list))

if (args$debug) {
    args <- list()
    args$rawdir <- "~/data/ukbb/ukb-hrt/rawdata"
    args$outdir <- "~/data/ukbb/ukb-hrt/phenotypes"
    args$pheno <- "~/data/ukbb/ukb-hrt/rawdata/190402_fractal_dimension_26k.csv"
    args$interpolate <- 9
    args$cov <- "~/data/ukbb/ukb-hrt/rawdata/VentricularVolumes.csv"
    args$samples <- "~/data/ukbb/ukb-hrt/rawdata/ukb18545_imp_chr1_v3_s487378.sample"
    args$relatedness <-"~/data/ukbb/ukb-hrt/rawdata/ukb18545_rel_s488346.dat"
    args$europeans <- "~/data/ukbb/ukb-hrt/ancestry/European_samples.csv"
    args$pcs <- "~/data/ukbb/ukb-hrt/ancestry/ukb_imp_genome_v3_maf0.1.pruned.European.pca"
}

## ukb phenotype files converted via ukb_tools:
# http://biobank.ctsu.ox.ac.uk/showcase/docs/UsingUKBData.pdf
# ukb_unpack ukb22219.enc key
# ukb_conv ukb22219.enc_ukb r
# ukb_conv ukb22219.enc_ukb docs
# get rosetta error, but according to
# https://biobank.ctsu.ox.ac.uk/crystal/exinfo.cgi?src=faq#rosetta, nothing to
# worry about

## ukb genotype files via https://biobank.ndph.ox.ac.uk/showcase/refer.cgi?id=664
# ukbgene rel ukb22219.enc
# ukbgene imp -c1 -m

################
## analysis ####
################

## FD measurements ####
dataFD <- data.table::fread(args$pheno, data.table=FALSE,
                            stringsAsFactors=FALSE, na.strings=c("NA", "NaN"))
rownames(dataFD) <- dataFD[, 1]
colnames(dataFD)[colnames(dataFD) == 'FD - Slice 1'] <- 'Slice 1'
dataFD <- dataFD[,grepl("Slice \\d{1,2}", colnames(dataFD))]
colnames(dataFD) <- gsub(" ", "", colnames(dataFD))

# Exclude individuals where less than 6 slices were measured
NaN_values <- c("Sparse myocardium", "Meagre blood pool","FD measure failed")
fd_notNA <- apply(dataFD, 1,  function(x) {
                length(which(!(is.na(x) | x %in% NaN_values))) > 5
                            })
dataFD <- dataFD[fd_notNA, ]

# interpolate FD slice measures
FDi <- autofd$interpolate$fracDecimate(data=dataFD,
                                       interpNoSlices=args$interpolate,
                                       id.col.name='rownames')
# summary fd measurements
summaryFDi <- data.frame(t(apply(as.matrix(FDi), 1,
                                          autofd$stats$summaryStatistics,
                       discard=FALSE, sections="BMA")))

# plot distribution of FD along heart
FDalongHeart <- reshape2::melt(FDi, value.name = "FD")
colnames(FDalongHeart)[1:2] <- c("ID", "Slice")

FDalongHeart$Slice <- as.factor(as.numeric(gsub("Slice_", "",
                                                FDalongHeart$Slice)))
FDalongHeart$Location <- "Apical section"
FDalongHeart$Location[as.numeric(FDalongHeart$Slice) <= 3] <- "Basal section"
FDalongHeart$Location[as.numeric(FDalongHeart$Slice) <= 6 &
                      as.numeric(FDalongHeart$Slice) > 3] <- "Mid section"
FDalongHeart$Location <- factor(FDalongHeart$Location,
                                levels=c("Basal section", "Mid section",
                                         "Apical section"))

p_fd <- ggplot(data=FDalongHeart)
p_fd <- p_fd + geom_boxplot(aes(x=Slice, y=FD, color=Location)) +
    scale_color_manual(values=c('#67a9cf','#1c9099','#016c59')) +
    labs(x="Slice", y="FD") +
    theme_bw()

ggsave(plot=p_fd, file=paste(args$outdir, "/FDAlongHeart_slices",
                             args$interpolate, ".pdf", sep=""),
       height=4, width=4, units="in")


## LV volume measurements ####
lvv <- data.table::fread(args$cov, data.table=FALSE,
                            stringsAsFactors=FALSE, na.strings=c("NA", "NaN"))
hr <- data.table::fread(paste(args$rawdir, "/20181124_HR_from_CMR.csv", sep=""),
                        data.table=FALSE, stringsAsFactors=FALSE)

lvv <- merge(hr, lvv, by="ID")
lvv$SV <- lvv$LVEDV - lvv$LVESV
lvv$CO <- lvv$SV * lvv$HR
rownames(lvv) <- lvv[, 1]

lvv <- dplyr::select(lvv, ID, LVEDV, LVESV, LVEF, LVM, SV, CO, HR)

## ukbb bulk data ####
# ukbb phenotypes
ukbb <- ukb_df(fileset="ukb22219", path=args$rawdir)
saveRDS(ukbb, paste(args$rawdir, "/ukb22219.rds", sep=""))

ukbb_fd <- dplyr::filter(ukbb, eid %in% rownames(dataFD))
saveRDS(ukbb_fd, paste(args$rawdir, "/ukb22219_fd.rds", sep=""))

# ukbb genotype samples via ukbgene imp -c1 -m
samples <- data.table::fread(args$samples, data.table=FALSE, skip=2,
                             stringsAsFactors=FALSE,
                             col.names=c("ID_1", "ID_2", "missing", "sex"))

# ukbb relatedness file via ukbgene rel
relatedness <- data.table::fread(args$relatedness, data.table=FALSE,
                             stringsAsFactors=FALSE)
# European ancestry via ancestry.smk
europeans <- data.table::fread(args$europeans, data.table=FALSE,
                            stringsAsFactors=FALSE, col.names="ID")

# Principal components of European ancestry via ancestry.smk
pcs <- data.table::fread(args$pcs, data.table=FALSE, stringsAsFactors=FALSE)

## get covariates data ####
# grep columns with covariates sex, age, bmi and weight
sex <- which(grepl("genetic_sex_", colnames(ukbb_fd)))
age <- which(grepl("age_when_attended_assessment_centre",
    colnames(ukbb_fd)))
bmi <- which(grepl("bmi_", colnames(ukbb_fd)))
weight <- which(grepl("^weight_", colnames(ukbb_fd)))
systolic <-  which(grepl('systolic_blood_pressure_automated_reading',
                         colnames(ukbb_fd)))
diastolic <-  which(grepl('diastolic_blood_pressure_automated_reading',
                          colnames(ukbb_fd)))

# manually check which columns are relevant and most complete
sexNA <- is.na(ukbb_fd[,sex]) # length(which(sexNA)) -> 461
allSex <- ukbb_fd[!sexNA,] #  nrow(allSex) -> 19235

ageNA <- apply(ukbb_fd[!sexNA, age], 2, function(x)
    length(which(is.na(x)))) # 0,14298,1167
weightNA <- apply(ukbb_fd[!sexNA, weight], 2, function(x)
    length(which(is.na(x)))) # 28,14258,440
bmiNA <- apply(ukbb_fd[!sexNA, bmi] , 2, function(x)
    length(which(is.na(x)))) # 31,14259,479
relevant <- c(sex, age[which.min(ageNA)], weight[which.min(weightNA)],
    bmi[which.min(bmiNA)])

covs <- allSex[, relevant]
covs$genetic_sex_f22001_0_0 <- as.numeric(covs$genetic_sex_f22001_0_0)
index_noNA <- which(apply(covs, 1, function(x) !any(is.na(x))))
covs_noNA <- covs[index_noNA,]
covs_noNA <- as.data.frame(apply(covs_noNA, 2, as.numeric))
rownames(covs_noNA) <- allSex$eid[index_noNA]

covs_noNA$height_f21002_comp <-
    sqrt(covs_noNA$weight_f21002_0_0/covs_noNA$body_mass_index_bmi_f21001_0_0)


## Merge FD measures and covariates to order by samples ####
fd_all <- merge(dplyr::select(summaryFDi, MeanGlobalFD, MeanBasalFD, MeanMidFD,
                              MeanApicalFD),
                FDi, by=0)
fd_all <- merge(fd_all, lvv, by=1)
fd_all <- merge(fd_all, covs_noNA, by.x=1, by.y=0)
fd_all$genetic_sex_f22001_0_0 <- as.factor(fd_all$genetic_sex_f22001_0_0)
fd_all$BSA <- sqrt(fd_all$weight_f21002_0_0 * fd_all$height_f21002_comp*
                                   100/3600)
fd_all$LVEDVi <- fd_all$LVEDV/fd_all$BSA
fd_all$LVESVi <- fd_all$LVESV/fd_all$BSA
fd_all$LVEFi <- fd_all$LVEF/fd_all$BSA
fd_all$LVMi <- fd_all$LVM/fd_all$BSA

fd_pheno <- dplyr::select(fd_all, MeanBasalFD, MeanMidFD, MeanApicalFD)

fd_cov <- dplyr::select(fd_all, genetic_sex_f22001_0_0,
    age_when_attended_assessment_centre_f21003_0_0, weight_f21002_0_0,
    body_mass_index_bmi_f21001_0_0, height_f21002_comp)

slices <- paste("Slice_", 1:args$interpolate, sep="")
fd_slices <- dplyr::select(fd_all, slices)

fd_lvv <- dplyr::select(fd_all, LVEDV, LVESV, LVM, SV, CO, HR)

write.table(fd_all, paste(args$outdir, "/FD_all_slices", args$interpolate,
                          ".csv", sep=""),
            sep=",", row.names=fd_all$Row.names, col.names=NA, quote=FALSE)
write.table(fd_pheno, paste(args$outdir, "/FD_phenotypes_slices",
                            args$interpolate, ".csv", sep=""),
            sep=",", row.names=fd_all$Row.names, col.names=NA, quote=FALSE)
write.table(fd_cov, paste(args$outdir, "/FD_covariates.csv", sep=""),
            sep=",", row.names=fd_all$Row.names, col.names=NA, quote=FALSE)
write.table(fd_lvv, paste(args$outdir, "/FD_LVV.csv", sep=""),
            sep=",", row.names=fd_all$Row.names, col.names=NA, quote=FALSE)


## Plot distribution of covariates ####
df <- dplyr::select(fd_all, MeanBasalFD, MeanMidFD, MeanApicalFD, LVEDV, SV, CO,
                    genetic_sex_f22001_0_0,
                    age_when_attended_assessment_centre_f21003_0_0,
                    weight_f21002_0_0,
                    body_mass_index_bmi_f21001_0_0, height_f21002_comp)
p <- ggpairs(df,
             upper = list(continuous = wrap("density", col="#b30000",
                                            size=0.1)),
             diag = list(continuous = wrap("densityDiag", size=0.4)),
             lower = list(continuous = wrap("smooth", alpha=0.5,size=0.1,
                                            pch=20),
                          combo = wrap("facethist")),
             columnLabels = c("meanBasalFD", "meanMidFD", "meanApicalFD",
                              "EDV~(ml)", "SV~(ml)", "CO~(ml/min)", "Sex~(f/m)",
                              "Age~(years)", "Height~(m)",
                              "Weight~(kg)", "BMI~(kg/m^2)"),
             labeller = 'label_parsed',
             axisLabels = "show") +
    theme_bw() +
    theme(panel.grid = element_blank(),
          axis.text = element_text(size=6),
          axis.text.x = element_text(angle=90),
          strip.text = element_text(size=8),
          strip.background = element_rect(fill="white", colour=NA))
p[6,5] <- p[6,5] + geom_histogram(binwidth=3
ggsave(plot=p, file=paste(args$outdir, "/pairs_fdcovariates.png", sep=""),
       height=12, width=12, units="in")

df_small <- dplyr::select(fd_all,
                    genetic_sex_f22001_0_0,
                    age_when_attended_assessment_centre_f21003_0_0,
                    weight_f21002_0_0,
                    body_mass_index_bmi_f21001_0_0, height_f21002_comp,
                    SV, MeanGlobalFD)
p <- ggpairs(df_small,
             upper = list(continuous = wrap("smooth", alpha=0.5,size=0.1,
                                            pch=20),
                          combo = wrap("facethist")),
             diag = list(continuous = wrap("densityDiag", size=0.4)),
             lower = list(continuous = wrap("smooth", alpha=0.5,size=0.1,
                                            pch=20),
                          combo = wrap("facethist")),
             columnLabels = c("Sex~(f/m)",
                              "Age~(years)", "Height~(m)",
                              "Weight~(kg)", "BMI~(kg/m^2)", "SV~(ml)",
                              "global~FD"),
             labeller = 'label_parsed',
             axisLabels = "show") +
    theme_bw() +
    theme(panel.grid = element_blank(),
          axis.text = element_text(size=6),
          axis.text.x = element_text(angle=90),
          strip.text = element_text(size=8),
          strip.background = element_rect(fill="white", colour=NA))
ggsave(plot=p, file=paste(args$outdir, "/pairs_fdcovariates_small.pdf", sep=""),
       height=12, width=12, units="in")

## Plot correlation of FD with qrs duration
qrs <- merge(ukbb_fd[,c(1,901)], summaryFDi, by.x=1, by.y=0)
qrs$qrs_duration_f12340_2_0 <- as.numeric(qrs$qrs_duration_f12340_2_0)
p_qrs <- ggplot(qrs, aes(x=qrs_duration_f12340_2_0, y=MeanGlobalFD))
p_qrs <- p_qrs +
    smooth$stat_smooth_func(geom="text", method="lm", hjust=0, parse=TRUE,
                            xpos=200, ypos=1.3, vjust=0, color="black") +
    geom_smooth(method="lm", se=FALSE) +
    xlab('QRS duration') +
    ylab('Mean global FD') +
    geom_point(size=1) +
    theme_bw()
ggsave(plot=p_qrs, file=paste(args$outdir, "/FD_QRS.pdf", sep=""),
       height=8, width=8, units="in")


## Filter phenotypes for ethnicity and relatedness ####
related_samples <- related$smartRelatednessFilter(fd_all$Row.names, relatedness)
related2filter <- c(related_samples$related2filter,
                    related_samples$related2decide$ID1)

fd_norelated <- fd_all[!fd_all$Row.names %in% related2filter,]
fd_europeans_norelated <- fd_norelated[fd_norelated$Row.names %in% europeans$ID,]
rownames(fd_europeans_norelated) <- fd_europeans_norelated[,1]

## Test association with all covs and principal components ####
fd_europeans_norelated <- merge(fd_europeans_norelated, pcs[,-1], by=1)
index_pheno <- which(grepl("FD", colnames(fd_europeans_norelated)))
index_slices <- which(grepl("Slice_", colnames(fd_europeans_norelated)))
index_volumes <- 15:21
index_cov <- c(22:26, 32:ncol(fd_europeans_norelated))

lm_fd_pcs <- sapply(index_pheno, function(x) {
    tmp <- lm(y ~ ., data=data.frame(y=fd_europeans_norelated[,x],
                                     fd_europeans_norelated[,index_cov]))
    summary(tmp)$coefficient[,4]
})
colnames(lm_fd_pcs) <- colnames(fd_europeans_norelated)[index_pheno]
rownames(lm_fd_pcs) <- c("intercept",
    colnames(fd_europeans_norelated)[index_cov])
sigAssociations <- which(apply(lm_fd_pcs, 1, function(x) any(x < 0.01)))

fd_europeans_norelated <- fd_europeans_norelated[,c(1,index_pheno, index_slices,
    index_volumes,
    which(colnames(fd_europeans_norelated) %in% names(sigAssociations)))]

rownames(fd_europeans_norelated) <- fd_europeans_norelated$Row.names
write.table(lm_fd_pcs[sigAssociations,],
            paste(args$outdir, "/FD_cov_associations.csv", sep=""), sep=",",
            row.names=TRUE, col.names=NA, quote=FALSE)

write.table(fd_europeans_norelated,
            paste(args$outdir, "/FD_all_EUnorel.csv", sep=""),
            sep=",",
            row.names=fd_europeans_norelated$Row.names, col.names=NA,
            quote=FALSE)
write.table(fd_europeans_norelated[,index_pheno],
            paste(args$outdir, "/FD_phenotypes_EUnorel.csv", sep=""),
            sep=",",
            row.names=fd_europeans_norelated$Row.names, col.names=NA,
            quote=FALSE)
write.table(fd_europeans_norelated[,-c(1, index_pheno, index_slices,
                                       index_volumes)],
            paste(args$outdir, "/FD_covariates_EUnorel.csv", sep=""), sep=",",
            row.names=fd_europeans_norelated$Row.names, col.names=NA,
            quote=FALSE)
write.table(fd_europeans_norelated[, index_slices],
            paste(args$outdir, "/FD_slices_EUnorel.csv", sep=""), sep=",",
            row.names=fd_europeans_norelated$Row.names, col.names=NA,
            quote=FALSE)
write.table(fd_europeans_norelated[, index_volumes],
            paste(args$outdir, "/FD_volumes_EUnorel.csv", sep=""), sep=",",
            row.names=fd_europeans_norelated$Row.names, col.names=NA,
            quote=FALSE)

## Format phenotypes and covariates for bgenie ####
# Everything has to be matched to order in sample file; excluded and missing
# samples will have to be included in phenotypes and covariates and values set
# to -999

fd_bgenie <- merge(samples, fd_europeans_norelated, by=1, all.x=TRUE, sort=FALSE)
fd_bgenie <- fd_bgenie[match(samples$ID_1, fd_bgenie$ID_1),]
fd_bgenie$genetic_sex_f22001_0_0 <- as.numeric(fd_bgenie$genetic_sex_f22001_0_0)
fd_bgenie[is.na(fd_bgenie)] <- -999

write.table(fd_bgenie[, (index_pheno + 3)],
            paste(args$outdir, "/FD_phenotypes_bgenie.txt", sep=""), sep=" ",
            row.names=FALSE, col.names=TRUE, quote=FALSE)
write.table(fd_bgenie[, (index_slices + 3)],
            paste(args$outdir, "/FD_slices_bgenie.txt", sep=""), sep=" ",
            row.names=FALSE, col.names=TRUE, quote=FALSE)
write.table(fd_bgenie[,-c(1:4, index_pheno + 3, index_slices + 3,
                          index_volumes + 3)],
            paste(args$outdir, "/FD_covariates_bgenie.txt", sep=""), sep=" ",
            row.names=FALSE, col.names=TRUE, quote=FALSE)
write.table(fd_bgenie[,(index_volumes + 3)],
            paste(args$outdir, "/FD_volumes_bgenie.txt", sep=""), sep=" ",
            row.names=FALSE, col.names=TRUE, quote=FALSE)

## Blood pressure phenotypes ####
systolicNA <- apply(ukbb_fd[!sexNA, systolic] , 2, function(x)
    length(which(is.na(x)))) # 796,1108,14233,14228,3362,3343
diastolicNA <- apply(ukbb_fd[!sexNA, diastolic] , 2, function(x)
    length(which(is.na(x)))) # 796,1108,14232,14228,3362,3343
bp <- allSex[,c(systolic[which.min(systolic)],
                diastolic[which.min(diastolic)])]
bpIndex_noNA <- which(apply(bp, 1, function(x) !any(is.na(x))))
bp_noNA <- bp[bpIndex_noNA,]
bp_noNA <- as.data.frame(apply(bp_noNA, 2, as.numeric))
rownames(bp_noNA) <- allSex$eid[bpIndex_noNA]

## Filter blood pressure phenotypes for ethnicity and relatedness ####
bp_europeans_norelated <- merge(bp_noNA, fd_europeans_norelated[,-c(1:26)], by=0)

index_bp <- which(grepl("blood_pressure", colnames(bp_europeans_norelated)))
index_cov <-
    which(!grepl("blood_pressure", colnames(bp_europeans_norelated)))[-1]

lm_bp <- sapply(index_bp, function(x) {
    tmp <- lm(y ~ ., data=data.frame(y=bp_europeans_norelated[,x],
                                     bp_europeans_norelated[,index_cov]))
    summary(tmp)$coefficient[,4]
    })

colnames(lm_bp) <- colnames(bp_europeans_norelated)[index_bp]
rownames(lm_bp) <- c("intercept", colnames(bp_europeans_norelated)[index_cov])
sigAssociations_bp <- which(apply(lm_bp, 1, function(x) any(x < 0.01)))

bp_europeans_norelated <-
    bp_europeans_norelated[,c(1, index_bp,
                              which(colnames(bp_europeans_norelated) %in%
                                     names(sigAssociations_bp)))]

write.table(lm_bp[sigAssociations_bp,],
            paste(args$outdir, "/BP_cov_associations.csv", sep=""), sep=",",
            row.names=TRUE, col.names=NA, quote=FALSE)

write.table(bp_europeans_norelated[,index_bp],
            paste(args$outdir, "/BP_phenotypes_EUnorel.csv", sep=""),
            sep=",", row.names=bp_europeans_norelated$Row.names, col.names=NA,
            quote=FALSE)
write.table(bp_europeans_norelated[,-c(1, index_bp)],
            paste(args$outdir, "/BP_covariates_EUnorel.csv", sep=""), sep=",",
            row.names=bp_europeans_norelated$Row.names, col.names=NA,
            quote=FALSE)

## Format bp phenotypes and covariates for bgenie ####
bp_bgenie <- merge(samples, bp_europeans_norelated, by=1, all.x=TRUE, sort=FALSE)
bp_bgenie <- bp_bgenie[match(samples$ID_1, bp_bgenie$ID_1),]
bp_bgenie$genetic_sex_f22001_0_0 <- as.numeric(bp_bgenie$genetic_sex_f22001_0_0)
bp_bgenie[is.na(bp_bgenie)] <- -999

write.table(bp_bgenie[, (index_bp + 3)],
            paste(args$outdir, "/BP_phenotypes_bgenie.txt", sep=""), sep=" ",
            row.names=FALSE, col.names=TRUE, quote=FALSE)
write.table(bp_bgenie[,-c(1:4, index_bp + 3)],
            paste(args$outdir, "/BP_covariates_bgenie.txt", sep=""), sep=" ",
            row.names=FALSE, col.names=TRUE, quote=FALSE)

## Cardiac volume phenotypes ####
hr <- data.table::fread(paste(args$rawdir, "/20181124_HR_from_CMR.csv", sep=""),
                        data.table=FALSE, stringsAsFactors=FALSE)

lvv <- data.table::fread(paste(args$rawdir, "/VentricularVolumes.csv", sep=""),
                        data.table=FALSE, stringsAsFactors=FALSE)

lvv.hr <- merge(hr, lvv, by="ID")
lvv.hr$SV <- lvv.hr$LVEDV - lvv.hr$LVESV
lvv.hr$CO <- lvv.hr$SV * lvv.hr$HR

## Filter cardiac volume for ethnicity and relatedness ####
vv_europeans_norelated <- merge(lvv.hr, fd_europeans_norelated[,-c(1:26)], by=0)

index_bp <- which(grepl("blood_pressure", colnames(bp_europeans_norelated)))
index_cov <-
    which(!grepl("blood_pressure", colnames(bp_europeans_norelated)))[-1]

lm_bp <- sapply(index_bp, function(x) {
    tmp <- lm(y ~ ., data=data.frame(y=bp_europeans_norelated[,x],
                                     bp_europeans_norelated[,index_cov]))
    summary(tmp)$coefficient[,4]
    })

colnames(lm_bp) <- colnames(bp_europeans_norelated)[index_bp]
rownames(lm_bp) <- c("intercept", colnames(bp_europeans_norelated)[index_cov])
sigAssociations_bp <- which(apply(lm_bp, 1, function(x) any(x < 0.01)))

bp_europeans_norelated <-
    bp_europeans_norelated[,c(1, index_bp,
                              which(colnames(bp_europeans_norelated) %in%
                                     names(sigAssociations_bp)))]

write.table(lm_bp[sigAssociations_bp,],
            paste(args$outdir, "/BP_cov_associations.csv", sep=""), sep=",",
            row.names=TRUE, col.names=NA, quote=FALSE)

write.table(bp_europeans_norelated[,index_bp],
            paste(args$outdir, "/BP_phenotypes_EUnorel.csv", sep=""),
            sep=",", row.names=bp_europeans_norelated$Row.names, col.names=NA,
            quote=FALSE)
write.table(bp_europeans_norelated[,-c(1, index_bp)],
            paste(args$outdir, "/BP_covariates_EUnorel.csv", sep=""), sep=",",
            row.names=bp_europeans_norelated$Row.names, col.names=NA,
            quote=FALSE)

## Format bp phenotypes and covariates for bgenie ####
bp_bgenie <- merge(samples, bp_europeans_norelated, by=1, all.x=TRUE, sort=FALSE)
bp_bgenie <- bp_bgenie[match(samples$ID_1, bp_bgenie$ID_1),]
bp_bgenie$genetic_sex_f22001_0_0 <- as.numeric(bp_bgenie$genetic_sex_f22001_0_0)
bp_bgenie[is.na(bp_bgenie)] <- -999

write.table(bp_bgenie[, (index_bp + 3)],
            paste(args$outdir, "/BP_phenotypes_bgenie.txt", sep=""), sep=" ",
            row.names=FALSE, col.names=TRUE, quote=FALSE)
write.table(bp_bgenie[,-c(1:4, index_bp + 3)],
            paste(args$outdir, "/BP_covariates_bgenie.txt", sep=""), sep=" ",
            row.names=FALSE, col.names=TRUE, quote=FALSE)
