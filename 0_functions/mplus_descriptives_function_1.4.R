#author: "Andrew M. Demetriou"

library("here")            # file logistics
library("tidyverse")       # data wrangling 
library("corrplot")        # visualization
library("MplusAutomation") # Mplus integration
library("boot")            # bootstrapping CIs

# ensure this script returns the same results on each run
set.seed(42) #the answer to life, the universe, and everything


get_random_intercepts_mplus <- function(
    fit, # output of mplus model run
         # 10 item character vector of variables in order
    intercept,
    DVs = c("y_power", "y_security", "y_conformity", "y_tradition", 
            "y_benevolence", "y_universalism", "y_self_direction", 
            "y_stimulation", "y_hedonism", "y_achievement")
    
){
  
  intercept <- intercept |> toupper()
  
  if(intercept == 'SUBJECT_ID'){
    prefix <- 'B2a_Y'
  }else if(intercept == 'ITEM_ID'){
    prefix <- 'B2b_Y'
  }else(print("error: wrong intercept identifier"))
    
  # this is the output from the bayesian sampling process
  factor_scores <- fit$results$savedata |>
    # .Mean represents the mean value of the resampling
    select(intercept, ends_with('.Mean'))
    
    # extract subject intercept SDs
    intercepts_df <- factor_scores |>
      # the 'B2a' are the subject intercepts
      select(intercept, starts_with(prefix))
    
    # reduce to a single row per participant
    intercepts_df <- aggregate(intercepts_df, 
        by=list(intercepts_df[, intercept]), FUN=mean) |>
        select(-Group.1 )
    
    colnames(intercepts_df) <- c(intercept, DVs)
    
    return(intercepts_df)
}


# retrieve standard deviation of an object
samplesd <- function(x, d) {
  return(sd(x[d]))
}

bootstrap_SD_list <- function(
     intercept_df, 
        intercept,
    DVs = c("y_power", "y_security", "y_conformity", "y_tradition", 
            "y_benevolence", "y_universalism", "y_self_direction", 
            "y_stimulation", "y_hedonism", "y_achievement")){
  
 # remove IDs from df
 boot_df <- intercept_df |>
   select(-intercept)
 
 # create list of bootstrapped outputs
 boots <- apply(boot_df, 2, function(y){
   b <- boot(y, samplesd,R=1000);
   boot.ci(b)
   }) 
 
 # create list of confidence intervals
 ci_list <-list(
 y_power          <- c(boots$y_power$t0, boots$y_power$normal),
 y_security       <- c(boots$y_security$t0, boots$y_security$normal),
 y_conformity     <- c(boots$y_conformity$t0, boots$y_conformity$normal),
 y_tradition      <- c(boots$y_tradition$t0, boots$y_tradition$normal),
 y_benevolence    <- c(boots$y_benevolence$t0, boots$y_benevolence$normal),
 y_universalism   <- c(boots$y_universalism$t0, boots$y_universalism$normal),
 y_self_direction <- c(boots$y_self_direction$t0, boots$y_self_direction$normal),
 y_stimulation    <- c(boots$y_stimulation$t0, boots$y_stimulation$normal),
 y_hedonism       <- c(boots$y_hedonism$t0, boots$y_hedonism$normal),
 y_achievement    <- c(boots$y_achievement$t0, boots$y_achievement$normal)
 )
 
 # rename the items in the list
 ci_list <- setNames(ci_list, DVs)
}


ci_list_item_to_row <- function(ci_list_row, intercept){
  
formatted_ci_list_row <- 
   ci_list_row |>
   as.data.frame() |> 
   t() |>
   as.data.frame() |>
   select(V1, V3, V4) |>
   rownames_to_column() |>
   as.data.frame()

colnames(formatted_ci_list_row) <- c("value", intercept, paste0(intercept, "_lower"), paste0(intercept, "_upper"))

return(formatted_ci_list_row)
}


format_ci_df <- function(
    ci_list, 
    intercept, 
    DVs = c("y_power", "y_security", "y_conformity", "y_tradition", 
            "y_benevolence", "y_universalism", "y_self_direction", 
            "y_stimulation", "y_hedonism", "y_achievement")){
    
    ci_list <- lapply(ci_list, ci_list_item_to_row, intercept = intercept)
    ci_df   <- rbindlist(ci_list, idcol = 'model') |>
      select(-value)
}


assemble_ci_dfs <- function(fit){
  
  # extract random effects dataframes from model object
  subject_intercept_df <- get_random_intercepts_mplus(fit, intercept = 'subject_ID')
  item_intercept_df    <- get_random_intercepts_mplus(fit, intercept = 'item_ID')
  
  # compute 95% bootstrapped confidence intervals
  subject_ci_list <- bootstrap_SD_list(subject_intercept_df, 'SUBJECT_ID')
  item_ci_list    <- bootstrap_SD_list(item_intercept_df, 'ITEM_ID')
  
  # convert ci lists to dataframes
  subject_ci_df <- format_ci_df(subject_ci_list, 'SUBJECT_ID')
  item_ci_df    <- format_ci_df(item_ci_list, 'ITEM_ID')
  
  # merge dfs
  random_effects_df <- merge(subject_ci_df, item_ci_df, by.x="model", by.y = "model")
  random_effects_df <- random_effects_df[c("y_power", "y_security", "y_conformity", "y_tradition", 
                                           "y_benevolence", "y_universalism", "y_self_direction", 
                                           "y_stimulation", "y_hedonism", "y_achievement"),]
}


build_mplus_correlation_matrix <- function(mplus_model_fit_object, human_or_machine='Y'){
  
  values <- c("power", "security", "conformity", "tradition", "benevolence", "universalism", "self_direction", "stimulation", "hedonism", "achievement")
  
  #human_or_machine <- 'M'
  #mplus_model_fit_object <- fit
  
  #extract mplus model correlations output
  mplus_correlations <- mplus_model_fit_object$results$parameters$stdyx.standardized |>
    # .WITH indicates all the correlations
    filter(grepl('.WITH', paramHeader)) |>
    select(paramHeader, param, est)  |>
    # Y is the human ratings, M are the machine ratings
    filter(grepl(human_or_machine, paramHeader)) |>
    filter(grepl(human_or_machine, param))
  
  
  #create vector with variable names
  variables <- paste0(human_or_machine, seq(1,10))
  
  
  # create a two column dataframe for each variable
  V1 <- mplus_correlations |>
    # select rows with correlations for the first variable
    filter(grepl(paste0(variables[1], '.WITH'), paramHeader)) |>
    # remove column
    select(-paramHeader) |>
    # add the unison correlation
    add_row(param = variables[1], est = 1) |>
    # order variables from 1-10
    arrange(match(param, variables)) |>
    rename(V1 = est)
  
  
  V2 <- mplus_correlations |>
    filter(grepl(paste0(variables[2], '.WITH'), paramHeader)) |>
    select(-paramHeader) |>
    add_row(param = variables[1], est = V1[2,2]) |>
    add_row(param = variables[2], est = 1) |>
    arrange(match(param, variables)) |>
    rename(V2 = est)
  
  V3 <- mplus_correlations |>
    filter(grepl(paste0(variables[3], '.WITH'), paramHeader)) |>
    select(-paramHeader) |>
    add_row(param = variables[1], est = V1[3,2]) |>
    add_row(param = variables[2], est = V2[3,2]) |>
    add_row(param = variables[3], est = 1) |>
    arrange(match(param, variables)) |>
    rename(V3 = est)
  
  V4 <- mplus_correlations |>
    filter(grepl(paste0(variables[4], '.WITH'), paramHeader)) |>
    select(-paramHeader) |>
    add_row(param = variables[1], est = V1[4,2]) |>
    add_row(param = variables[2], est = V2[4,2]) |>
    add_row(param = variables[3], est = V3[4,2]) |>
    add_row(param = variables[4], est = 1) |>
    arrange(match(param, variables)) |>
    rename(V4 = est)
  
  V5 <- mplus_correlations |>
    filter(grepl(paste0(variables[5], '.WITH'), paramHeader)) |>
    select(-paramHeader) |>
    add_row(param = variables[1], est = V1[5,2]) |>
    add_row(param = variables[2], est = V2[5,2]) |>
    add_row(param = variables[3], est = V3[5,2]) |>
    add_row(param = variables[4], est = V4[5,2]) |>
    add_row(param = variables[5], est = 1) |>
    arrange(match(param, variables)) |>
    rename(V5 = est)
  
  V6 <- mplus_correlations |>
    filter(grepl(paste0(variables[6], '.WITH'), paramHeader)) |>
    select(-paramHeader) |>
    add_row(param = variables[1], est = V1[6,2]) |>
    add_row(param = variables[2], est = V2[6,2]) |>
    add_row(param = variables[3], est = V3[6,2]) |>
    add_row(param = variables[4], est = V4[6,2]) |>
    add_row(param = variables[5], est = V5[6,2]) |>
    add_row(param = variables[6], est = 1) |>
    arrange(match(param, variables)) |>
    rename(V6 = est)
  
  V7 <- mplus_correlations |>
    filter(grepl(paste0(variables[7], '.WITH'), paramHeader)) |>
    select(-paramHeader) |>
    add_row(param = variables[1], est = V1[7,2]) |>
    add_row(param = variables[2], est = V2[7,2]) |>
    add_row(param = variables[3], est = V3[7,2]) |>
    add_row(param = variables[4], est = V4[7,2]) |>
    add_row(param = variables[5], est = V5[7,2]) |>
    add_row(param = variables[6], est = V6[7,2]) |>
    add_row(param = variables[7], est = 1) |>
    arrange(match(param, variables)) |>
    rename(V7 = est)
  
  V8 <- mplus_correlations |>
    filter(grepl(paste0(variables[8], '.WITH'), paramHeader)) |>
    select(-paramHeader) |>
    add_row(param = variables[1], est = V1[8,2]) |>
    add_row(param = variables[2], est = V2[8,2]) |>
    add_row(param = variables[3], est = V3[8,2]) |>
    add_row(param = variables[4], est = V4[8,2]) |>
    add_row(param = variables[5], est = V5[8,2]) |>
    add_row(param = variables[6], est = V6[8,2]) |>
    add_row(param = variables[7], est = V7[8,2]) |>
    add_row(param = variables[8], est = 1) |>
    arrange(match(param, variables)) |>
    rename(V8 = est)
  
  V9 <- mplus_correlations |>
    filter(grepl(paste0(variables[9], '.WITH'), paramHeader)) |>
    select(-paramHeader) |>
    add_row(param = variables[1], est = V1[9,2]) |>
    add_row(param = variables[2], est = V2[9,2]) |>
    add_row(param = variables[3], est = V3[9,2]) |>
    add_row(param = variables[4], est = V4[9,2]) |>
    add_row(param = variables[5], est = V5[9,2]) |>
    add_row(param = variables[6], est = V6[9,2]) |>
    add_row(param = variables[7], est = V7[9,2]) |>
    add_row(param = variables[8], est = V8[9,2]) |>
    add_row(param = variables[9], est = 1) |>
    arrange(match(param, variables)) |>
    rename(V9 = est)
  
  # build singular correlation matrix
  corr_mat    <- V1
  corr_mat$V2 <- V2$V2
  corr_mat$V3 <- V3$V3
  corr_mat$V4 <- V4$V4
  corr_mat$V5 <- V5$V5
  corr_mat$V6 <- V6$V6
  corr_mat$V7 <- V7$V7
  corr_mat$V8 <- V8$V8
  corr_mat$V9 <- V9$V9
  corr_mat$V10 <- c(
    V1[10,2], V2[10,2], V3[10,2], 
    V4[10,2], V5[10,2], V6[10,2], 
    V7[10,2], V8[10,2], V9[10,2], 1)
  
  corr_mat <- corr_mat |> select(-param)
  
  #format row names and column names
  colnames(corr_mat) <- variables
  rownames(corr_mat) <- variables
  
  return(corr_mat)
}
