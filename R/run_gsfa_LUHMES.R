## Recommend to run this script on a computing cluster that can guarantee 
## 30GB memory and 3.5 (typically ~3) hours of runtime without interruption.
## GSFA results were generated under default parameters with the output of
## "scaled.gene_exp" and "G_mat" from "preprocess_LUHMES.R" as GSFA input.
## Gibbs sampling was performed for 3000 iterations in one run,
## but can also be carried out in segments by setting "niter" to a smaller number
## and resuming the sampling using the "restart" option
## if only limited run time and memory can be allocated.
## Three output files:
## A full Gibbs sampling object; posterior mean estimates of parameters; an LFSR matrix.
library(GSFA)
library(optparse)
option_list <- list(
  make_option(
    "--expression_file", action = "store", default = NA, type = 'character',
    help = "RDS file of processed sample by gene expression matrix for GSFA input (Y) [required]"
  ),
  make_option(
    "--perturbation_file", action = "store", default = NA, type = 'character',
    help = "RDS file of sample by perturbation matrix for GSFA input (G) [required]"
  ),
  make_option(
    "--out_folder", action = "store", default = NA, type = 'character',
    help = "Directory of output folder (must end with a \'/\') [required]"
  ),
  make_option(
    "--init_method", action = "store", default = "svd", type = 'character',
    help = "Type of initialization method to use, can be \"svd\" or \"random\", default is %default"
  ),
  make_option(
    "--out_suffix", action = "store", default = "svd", type = 'character',
    help = "Suffix of the output file, reflecting the initializtion method, default is %default"
  ),
  make_option(
    "--K",  action = "store", default = 20, type = 'integer',
    help = "Number of factors to use, default is %default [auto-detected when restart=TRUE]"
  ),
  make_option(
    "--niter", action = "store", default = 3000, type = 'integer',
    help = "Number of iterations to sample, default is %default"
  ),
  make_option(
    "--average_niter", action = "store", default = 1000, type = 'integer',
    help = "Number of iterations to average over to obtain the posterior means, default is %default"
  ),
  make_option(
    "--random_seed", action = "store", default = 14314, type = 'integer',
    help = "Set a random seed for Gibbs sampling, default is %default [required for all types of initializations]"
  ),
  make_option(
    "--restart", action = "store", default = FALSE,
    help = "Flag to resume GSFA on previous result, default is %default"
  ),
  make_option(
    "--previous_res", action = "store", default = NA, type = 'character',
    help = "RDS file storing previous GSFA result to resume GSFA on [required when restart=TRUE]"
  ),
  make_option(
    "--permute", action = "store", default = FALSE,
    help = "Flag to perform permutation on the cells before GSFA, default is %default"
  ),
  make_option(
    "--perm_num",  action = "store", default = 1, type = 'integer',
    help = "Permutation index from 1 to 10, default is %default [required when permute==TRUE]"
  ),
  make_option(
    "--store_all_samples", action = "store", default = TRUE,
    help = "Flag to store samples throughout Gibbs iterations, can be turned off if storage is limited, default is %default"
  )
)
opt <- parse_args(OptionParser(option_list = option_list))

expression_file <- opt$expression_file
perturbation_file <- opt$perturbation_file
out_folder <- opt$out_folder
init_method <- opt$init_method
out_suffix <- opt$out_suffix
K <- opt$K
niter <- opt$niter
average_niter <- opt$average_niter
random_seed <- opt$random_seed
return_samples <- opt$store_all_samples

stopifnot(file.exists(expression_file) & file.exists(perturbation_file) &
            dir.exists(out_folder))
print("Loading input data ...")
scaled.gene_exp <- readRDS(expression_file)
G_mat <- readRDS(perturbation_file)

if (nrow(scaled.gene_exp) != nrow(G_mat)){
  scaled.gene_exp <- t(scaled.gene_exp)
}
stopifnot(rownames(G_mat) == rownames(scaled.gene_exp))

if (opt$restart){
  stopifnot(file.exists(opt$previous_res))
  prev_fit <- readRDS(opt$previous_res)
}

if (!opt$permute){
  set.seed(random_seed)
  out_dir <- paste0(out_folder, "gibbs_obj_k", K, ".", out_suffix, ".seed_", random_seed, ".rds")
} else {
  stopifnot(opt$perm_num %in% 1:10)
  seeds <- c(49553, 72704, 11932, 56826, 49707, 33357, 93747, 95392, 96675, 38186)
  random_seed <- seeds[opt$perm_num]
  print(paste("Permuting cell orders under seed", random_seed, "..."))
  set.seed(random_seed)
  
  new_cell_order <- sample(nrow(scaled.gene_exp))
  scaled.gene_exp <- scaled.gene_exp[new_cell_order, ]
  out_dir <- paste0(out_folder, "gibbs_obj_k", K, ".", paste0("perm_", opt$perm_num), 
                    ".", out_suffix, ".rds")
}
if (file.exists(out_dir)){
  warnings("Output file exists and will be overwritten!")
}

if (opt$restart == F){
  print(paste0("Performing GSFA with ", K, " factors and ", niter, " iterations."))
  print(paste0("Results will be saved at ", out_dir))
  fit <- fit_gsfa_multivar(Y = scaled.gene_exp, G = G_mat, K = K,
                           prior_type = "mixture_normal", init.method = init_method,
                           prior_w_s = 50, prior_w_r = 0.2,
                           prior_beta_s = 20, prior_beta_r = 0.2,
                           niter = niter, used_niter = average_niter,
                           verbose = T, return_samples = return_samples)
} else {
  print(paste0("Resuming GSFA on top of a previous result saved at ", opt$previous_res,
               " for ", niter, " iterations."))
  print(paste0("Results will be saved at ", out_dir))
  fit <- fit_gsfa_multivar(Y = scaled.gene_exp, G = G_mat, fit0 = prev_fit,
                           prior_type = "mixture_normal", init.method = init_method,
                           prior_w_s = 50, prior_w_r = 0.2,
                           prior_beta_s = 20, prior_beta_r = 0.2,
                           niter = niter, used_niter = average_niter,
                           verbose = T, return_samples = return_samples)
}
print("Finished! Saving the results...")
if (return_samples){
  saveRDS(fit, file = out_dir)
  big_items <- names(fit)[endsWith(names(fit), "samples")]
  for (i in big_items){
    fit[[i]] <- NULL
  }
}
saveRDS(fit, file = sub(pattern = ".rds", replacement = ".light.rds", x = out_dir))

lfsr_mat <- fit$lfsr
lfsr_mat <- lfsr_mat[, -ncol(lfsr_mat)]
print("# of genes that pass LFSR < 0.05:")
print(colSums(lfsr_mat < 0.05))
