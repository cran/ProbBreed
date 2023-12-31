## Function extr_outs
##
##' @title
##' Extracting outputs from [ProbBreed::bayes_met()] objects
##'
##' @description
##' This function extracts outputs of the Bayesian model fitted
##' using [ProbBreed::bayes_met()], and provides some diagnostics about the model
##'
##' @details
##' More details about the usage of `extr_outs`, as well as the other function of
##' the `ProbBreed` package can be found at \url{https://saulo-chaves.github.io/ProbBreed_site/}.
##'
##'
##' @param data A data frame containing the observations
##' @param trait A character representing the name of the column that
##' corresponds to the analysed trait
##' @param model An object containing the Bayesian model fitted using `rstan`
##' @param probs A vector with two elements representing the probabilities
##' (in decimal scale) that will be considered for computing the quantiles.
##' @param check.stan.diag A logical value indicating whether the function should
##' extract some diagnostic using native `rstan` functions.
##' @param verbose A logical value. If `TRUE`, the function will indicate the
##' completed steps. Defaults to `FALSE`
##' @param ... Passed to [rstan::stan_diag()]
##' @return The function returns a list with:
##' \itemize{
##' \item \code{post} : a list with the posterior of the effects, and the data
##' generated by the model
##' \item \code{map} : a list with the maximum posterior values of each effect
##' \item \code{ppcheck} : a matrix containing the p-values of maximum, minimum,
##' median, mean and standard deviation; effective number of parameters, WAIC2
##' value, Rhat and effective sample size.
##' \item \code{plots} : a list with three types of ggplots: histograms, trace plots and density
##' plots. These will be available for all effects declared at the `effects` argument.
##' \item \code{stan_plots}: If `check.stan.diag = TRUE`, a list with plots generated by [rstan::stan_diag()]
##' }
##'
##' @seealso [rstan::stan_diag()], [ggplot2::ggplot()], [rstan::check_hmc_diagnostics()]
##'
##' @import rstan ggplot2
##' @importFrom utils write.csv
##' @importFrom rlang .data
##'
##' @examples
##' \donttest{
##' mod = bayes_met(data = maize,
##'                 gen = "Hybrid",
##'                 loc = "Location",
##'                 repl = c("Rep", "Block"),
##'                 year = NULL,
##'                 reg = 'Region',
##'                 res.het = FALSE,
##'                 trait = 'GY',
##'                 iter = 6000, cores = 4, chains = 4)
##'
##' outs = extr_outs(data = maize, trait = "GY", model = mod,
##'                  probs = c(0.05, 0.95),
##'                  check.stan.diag = TRUE,
##'                  verbose = TRUE)
##'                  }
##' @export

extr_outs = function(data, trait, model, probs = c(0.025, 0.975),
                     check.stan.diag = TRUE, verbose = FALSE, ...){

  requireNamespace('ggplot2')
  requireNamespace('rstan')

  # Data
  data = if(any(is.na(data[,trait]))) data[-which(is.na(data[,trait])),] else data

  # Extract stan results
  out <- rstan::extract(model, permuted = TRUE)

  effects = names(out)[which(names(out) %in% c('r','b','m', 'l', 't', 'g', 'gl','gt','gm'))]
  nenv = ncol(out$l)

  # Posterior effects ------------------------
  post = list()
  for (i in effects) {
    post[[i]] = out[[i]]
  }

  names(post)[which(names(post) == 'l')] = "location"
  names(post)[which(names(post) == 'g')] = "genotype"
  names(post)[which(names(post) == 'gl')] = "gen.loc"
  if("r" %in% effects){names(post)[which(names(post) == 'r')] = "replicate"}
  if("b" %in% effects){names(post)[which(names(post) == 'b')] = "block"}
  if("m" %in% effects){
    names(post)[which(names(post) == 'm')] = "region"
    names(post)[which(names(post) == 'gm')] = "gen.reg"
    }
  if("t" %in% effects){
    names(post)[which(names(post) == 't')] = "year"
    names(post)[which(names(post) == 'gt')] = "gen.year"
  }

  if(verbose)  message('1. Posterior effects extracted')

  # Variances --------------------
  if(!'sigma_vec' %in% names(out)){

    variances = NULL
    std.dev = NULL
    naive.se = NULL
    prob = matrix(NA, nrow = 2, ncol = length(c(effects,'sigma')),
                  dimnames = list(probs, c(effects,'sigma')))
    # var.plots = list()
    for (i in c(effects,'sigma')) {
      if(i == 'sigma') all_variances = out[['sigma']]^2 else all_variances = out[[paste("s",i,sep='_')]]^2
      variances[i] = mean(all_variances)
      std.dev[i] = sd(all_variances)
      naive.se[i] = sd(all_variances)/sqrt(length(all_variances))
      prob[,i] = as.matrix(quantile(all_variances, probs = probs))
    }
    variances = data.frame(
      'effect' = c(effects,'error'),
      'var' = round(variances,3),
      'sd' = round(std.dev,3),
      'naive.se' = round(naive.se,3),
      'HPD1' = round(prob[1,],3),
      'HPD2' = round(prob[2,],3),
      row.names = NULL
    )

    colnames(variances)[which(colnames(variances) %in% c("HPD1",'HPD2'))] = c(
      paste('HPD',probs[1], sep = '_'),
      paste('HPD',probs[2], sep = '_')
    )

    rm(all_variances)
    rm(i)

  } else {

    variances = NULL
    std.dev = NULL
    naive.se = NULL
    prob = matrix(NA, nrow = 2, ncol = length(effects),
                  dimnames = list(probs, effects))
    for (i in c(effects)) {
      all_variances = out[[paste("s",i,sep='_')]]^2
      variances[i] = mean(all_variances)
      std.dev[i] = sd(all_variances)
      naive.se[i] = sd(all_variances)/sqrt(length(all_variances))
      prob[,i] = as.matrix(quantile(all_variances, probs = probs))
    }

    variances = data.frame(
      'effect' = c(effects, paste0('error_env', 1:nenv)),
      'var' = c(round(variances, 3), round(apply(out[['sigma']]^2, 2, mean),3)),
      'sd' = c(round(std.dev,3), round(apply(out[['sigma']]^2, 2, sd),3)),
      'naive.se' = c(round(naive.se,3),
                     round(apply(out[['sigma']]^2, 2,
                           function(x) sd(x)/sqrt(length(x))), 3)),
      'HPD1' = c(round(prob[1,],3), round(apply(out[['sigma']]^2, 2,
                                   function(x) quantile(x, probs = probs))[1,],3)),
      'HPD2' = c(round(prob[2,],3), round(apply(out[['sigma']]^2, 2,
                                 function(x) quantile(x, probs = probs))[2,],3)),
      row.names = NULL
    )

    rm(all_variances)
    rm(i)

    colnames(variances)[which(colnames(variances) %in% c("HPD1",'HPD2'))] = c(
      paste('HPD',probs[1], sep = '_'),
      paste('HPD',probs[2], sep = '_')
    )
  }

  variances$effect[which(variances$effect == 'l')] = "location"
  variances$effect[which(variances$effect == 'g')] = "genotype"
  variances$effect[which(variances$effect == 'gl')] = "gen.loc"
  if("r" %in% effects){variances$effect[which(variances$effect == 'r')] = "replicate"}
  if("b" %in% effects){variances$effect[which(variances$effect == 'b')] = "block"}
  if("m" %in% effects){
    variances$effect[which(variances$effect == 'm')] = "region"
    variances$effect[which(variances$effect == 'gm')] = "gen.reg"
  }
  if("t" %in% effects){
    variances$effect[which(variances$effect == 't')] = "year"
    variances$effect[which(variances$effect == 'gt')] = "gen.year"
  }

  if(verbose) message('2. Variances extracted')

  # Maximum posterior values (MAP) ------------------------
  get_map <- function(posterior) {
    posterior <- as.matrix(posterior)
    if (ncol(posterior) > 1) {
      den = apply(posterior, 2, density)
      map = unlist(lapply(den, function(den)
        den$x[which.max(den$y)]))
    }
    else {
      den = density(posterior)
      map = den$x[which.max(den$y)]
    }
    return(map)
  }
  map = lapply(post, get_map)

  if(verbose) message('3. Maximum posterior values extracted')

  # Data generated by the model -----------------
  post[['sampled.Y']] <- out[['y_gen']]

  # Diagnostics -------------------
  ns = length(out$mu)
  y = data[,trait]
  N = length(y)
  temp = apply(out$y_gen, 1, function(x) {
    c(
      max = max(x) > max(y),
      min = min(x) > min(y),
      median = quantile(x, 0.5) > quantile(y, 0.5),
      mean = mean(x) > mean(y),
      sd = sd(x) > sd(y)
    )
  })
  p.val_max = sum(temp["max",]) / ns
  p.val_min = sum(temp["min",]) / ns
  p.val_median = sum(temp["median.50%",]) / ns
  p.val_mean = sum(temp["mean",]) / ns
  p.val_sd = sum(temp["sd",]) / ns

  temp_v = apply(out$y_log_like, 2, function(x) {
    c(val = log((1 / ns) * sum(exp(x))),
      var = var(x))
  })
  lppd = sum(temp_v["val", ])
  p_WAIC2 = sum(temp_v["var", ]) # Effective number of parameters
  elppd_WAIC2 = lppd - p_WAIC2
  WAIC2 = -2 * elppd_WAIC2
  output_p_check = round(t(
    cbind(
      p.val_max = p.val_max,
      p.val_min = p.val_min,
      p.val_median = p.val_median,
      p.val_mean = p.val_mean,
      p.val_sd = p.val_sd,
      Eff_No_parameters = p_WAIC2,
      WAIC2 = WAIC2,
      mean_Rhat = mean(summary(model)$summar[,"Rhat"]),
      Eff_sample_size = mean(summary(model)$summar[,"n_eff"])/ns
    )
  ), 4)
  colnames(output_p_check) <- "Diagnostics"

  if(verbose) message('4. Goodness-of-fit diagnostics computed')

  # Plots section -------------------
  df.post.list = lapply(post, function(x){
    data.frame(
      value = c(x),
      iter = rep(seq(1, model@stan_args[[1]]$iter - model@stan_args[[1]]$warmup),
                 times = ncol(x) * length(model@stan_args)),
      chain = rep(seq(1, length(model@stan_args)),
                  each = model@stan_args[[1]]$iter - model@stan_args[[1]]$warmup)
    )
  })


  histograms = list()
  for (i in names(df.post.list)) {
    histograms[[i]] = ggplot(data = df.post.list[[i]],
                             aes(x = .data$value, after_stat(density))) +
      geom_histogram(bins = 30, color = 'black', fill = '#33a02c') +
      labs(x = paste('Values of', i), y = 'Density')
  }

  traceplots = list()
  for (i in names(df.post.list)[-which(names(df.post.list) == 'sampled.Y')]) {
    traceplots[[i]] = ggplot(data = df.post.list[[i]],
                             aes(y = .data$value, color = factor(.data$chain),
                                 x = .data$iter)) +
      geom_line(aes(group = factor(.data$chain), linetype = factor(.data$chain))) +
      scale_colour_viridis_d(option = 'viridis', direction = -1) +
      labs(y = paste(i, "effect"), x = 'Iterations',
           colour = 'Chain', linetype = 'Chain') +
      theme(legend.position = 'top')
  }

  # df.post.list$Sampled.Y = rbind(df.post.list$Sampled.Y,
  #                                data.frame(value = y, iter = 1:length(y),
  #                                           chain = 'Real'))
  densities = list()
  for (i in names(df.post.list)[-which(names(df.post.list) == 'sampled.Y')]) {
    densities[[i]] = ggplot(data = df.post.list[[i]],
                            aes(x = .data$value)) +
      geom_density(linewidth = 1, fill = '#33a02c', color = '#33a02c',
                   alpha = .8)  +
      labs(x = paste(i, "effect"), y = 'Frequency')
  }

  temp = df.post.list$sampled.Y
  temp$chain = "Sampled"
  temp = rbind(temp, data.frame(value = y, iter = 1:length(y), chain = 'Empirical'))

  densities$sampled.Y = ggplot(data = temp, aes(x = .data$value, color = .data$chain)) +
    geom_density(linewidth = 1.3, alpha = .5)  +
    labs(x = "Y", y = 'Frequency', fill = '', color = '') +
    theme(legend.position = 'top') +
    #scale_fill_manual(values = c('Real' = '#1f78b4', 'Sampled' = "#33a02c")) +
    scale_color_manual(values = c('Empirical' = '#1f78b4', 'Sampled' = "#33a02c"))

  rm(temp)

  plots = list(histograms = histograms, traceplots = traceplots, densities = densities)

  if(verbose) message('5. Function plots built')

  if(check.stan.diag){
    stan.plot.list = list(
      diag = stan_diag(model, ...),
      rhat = stan_rhat(model),
      ess = stan_ess(model),
      mcse = stan_mcse(model)
    )

    rstan::check_hmc_diagnostics(model)

    if(verbose) message('6. Stan diagnostic plots built')

    results = list(post, variances, map, output_p_check, plots, stan.plot.list)
    names(results) = c('post', 'variances', 'map', 'ppcheck', 'plots', 'stan_plots')
  }else{
    results = list(post, variances, map, output_p_check, plots)
    names(results) = c('post', 'variances', 'map', 'ppcheck', 'plots')
  }

  return(results)
}

