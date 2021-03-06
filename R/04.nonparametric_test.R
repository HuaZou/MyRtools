#' Wilcoxon Rank-Sum Test
#'
#' @description
#' Tests for the difference between two independent variables; takes into account magnitude and direction of difference
#'
#' @details 07/18/2019  ShenZhen China
#' @author  Hua Zou
#'
#' @param x x is data.frame with sampleID and group; sampleID connected to y
#' @param y y is table rownames->taxonomy; colnames->sampleID
#' @param DNAID names of sampleID to connect x and y
#' @param GROUP names of group information, only contain two levels if grp1 or grp2 haven't been provided
#' @param grp1  one of groups to be converted into 0
#' @param grp2  one of groups to be converted into 1
#'
#' @usage wilcox_rank(x, y, DNAID, GROUP, grp1=NULL, grp2=NULL)
#' @examples result <- wilcox_rank(phen, prof, "SampleID", "Stage", "BASE", "WASH")
#'
#' @return   Returns a result of Wilcoxon Rank-Sum Test
#' @return   Type:       kind of data
#' @return   Block:      group information
#' @return   Num:        number of group
#' @return   P-value:    P by Wilcoxon Rank-Sum Test
#' @return   FDR:        adjusted by BH
#' @return   Enrichment: directory by median or directory by rank
#' @return   Occurence:  occurence of two groups
#' @return   median:     both or each group
#' @return   rank:       each group
#' @return   FDR:        adjusted P value by BH
#' @return   Odds Ratio:     95% Confidence interval
#'
#' @export
#'
wilcox_rank <- function(x, y, DNAID, GROUP,
                            grp1=NULL, grp2=NULL){

  # determine x with two cols and names are corret
  phe <- x %>% select(c(DNAID, GROUP))
  colnames(phe)[which(colnames(phe) == DNAID)] <- "SampleID"
  colnames(phe)[which(colnames(phe) == GROUP)] <- "Stage"
  if (length(which(colnames(phe)%in%c("SampleID","Stage"))) != 2){
    warning("x without 2 cols: DNAID, GROUP")
  }

  # select groups
  if(length(grp1)){
    phe.cln <- phe %>% filter(Stage%in%c(grp1, grp2)) %>%
      mutate(Stage=factor(Stage, levels = c(grp1, grp2)))
    pr <- c(grp1, grp2)
  } else{
    phe.cln <- phe %>% mutate(Stage=factor(Stage))
    pr <- levels(phe.cln$Stage)
  }

  if (length(levels(phe.cln$Stage)) > 2) {
    stop("The levels of `group` are more than 2")
  }

  # profile
  sid <- intersect(phe.cln$SampleID, colnames(y))
  prf <- y %>% select(sid) %>%
    rownames_to_column("tmp") %>%
    # occurrence of rows more than 0.1
    filter(apply(select(., -one_of("tmp")), 1, function(x){sum(x > 0)/length(x)}) > 0.3) %>%
    data.frame() %>% column_to_rownames("tmp") %>%
    t() %>% data.frame()

  # judge no row of profile filter
  if (ncol(prf) == 0) {
    stop("No row of profile to be choosed\n")
  }

  # merge phenotype and profile
  mdat <- inner_join(phe.cln %>% filter(SampleID%in%sid),
                     prf %>% rownames_to_column("SampleID"),
                     by = "SampleID")
  dat.phe <- mdat %>% select(c(1:2))
  dat.prf <- mdat %>% select(-2)

  res <- apply(dat.prf[, -1], 2, function(x, grp){
    dat <- as.numeric(x)
    p <- signif(wilcox.test(dat ~ grp, paired = F)$p.value, 6)
    # median
    md <- signif(median(dat), 4)
    mdn <- signif(tapply(dat, grp, median), 4)
    if ( mdn[1] > mdn[2] & p < 0.05) {
      enrich1 <- pr[1]
    } else if (mdn[1] < mdn[2] & p < 0.05) {
      enrich1 <- pr[2]
    } else if (p > 0.05 | mdn[1] == mdn[2]){
      enrich1 <- "No significance"
    }

    # rank
    rk <- rank(dat)
    rnk <- signif(tapply(rk, grp, mean), 4)
    if ( rnk[1] > rnk[2] & p < 0.05) {
      enrich2 <- pr[1]
    } else if (rnk[1] < rnk[2] & p < 0.05) {
      enrich2 <- pr[2]
    } else if (p > 0.05 | rnk[1] == rnk[2]){
      enrich2 <- "No significance"
    }
    occ <- signif(tapply(dat, grp, function(x){
      round(sum(x > 0)/length(x), 4)}), 4)

    res <- c(p,enrich1,enrich2,occ,md,mdn,rnk)
    return(res)
  }, dat.phe$Stage) %>%
    t(.) %>% data.frame(.) %>%
    rownames_to_column("type") %>%
    varhandle::unfactor(.)

  colnames(res)[2:11] <- c("Pvalue", "Enrich_median", "Enrich_rank",
                           paste0(pr, "_occurence"), "median_all",
                           paste0(pr, "_median"), paste0(pr, "_rank"))
  res$Block <- paste0(pr[1], "_vs_", pr[2])
  number <- as.numeric(table(dat.phe$Stage))
  res$Num <- paste0(pr[1], number[1], "_vs_",
                    pr[2], number[2])
  res.cln <- res %>% select(c(1,12:13, 2:11)) %>%
    mutate(Pvalue=as.numeric(Pvalue)) %>%
    mutate(FDR=p.adjust(Pvalue, method = "BH")) %>%
    arrange(FDR, Pvalue)
  res2 <- res.cln[,c(1:4,14,5:13)]


  # scale profile
  dat.prf.cln <- prf[, -1]
  dat.phe.cln <- dat.phe %>% mutate(Group=ifelse(Stage==pr[1], 0, 1))
  idx <- which(colnames(dat.phe.cln) == "Group")

  # glm result for odd ratios 95%CI
  glmFun <- function(m, n){
    # calculate the glm between profile and group information
    #
    # Args:
    #   m:  result of group information which must to be numeric
    #   n:  taxonomy to be glm
    #
    # Returns:
    #   the glm result of between taxonomy group
    dat.glm <- data.frame(group=m, marker=scale(n, center=T, scale=T))
    model <- summary(glm(group ~ marker, data = dat.glm,
                         family = binomial(link = "logit")))
    res <- signif(exp(model$coefficients["marker",1]) +
                    qnorm(c(0.025,0.5,0.975)) * model$coefficients["marker",1], 2)

    return(res)
  }

  glm_res <- t(apply(dat.prf.cln, 2, function(x, group){
    res <- glmFun(group, as.numeric(x))
    return(res)
  }, group = dat.phe.cln[, idx]))
  Odd <- glm_res %>% data.frame() %>%
    setNames(c("upper", "expected","lower")) %>%
    mutate("Odds Ratio (95% CI)" = paste0(expected, " (", lower, ";", upper, ")"))
  Odd$type <- rownames(glm_res)

  res_merge <- inner_join(res2,
                          Odd[, c(4:5)], by = "type")

  return(res_merge)
}


#' Wilcoxon Sign-Rank Test
#'
#' @description
#' Tests for the difference between two related variables; takes into account the magnitude and direction of difference
#'
#' @details 07/18/2019 ShenZhen China
#' @author  Hua Zou
#'
#' @param x x is data.frame with sampleID and group; sampleID connected to y
#' @param y y is table rownames->taxonomy; colnames->sampleID
#' @param DNAID names of sampleID to connect x and y
#' @param PID   id for paired test
#' @param GROUP names of group information, only contain two levels if grp1 or grp2 haven't been provided
#' @param grp1  one of groups to be converted into 0
#' @param grp2  one of groups to be converted into 1
#'
#' @usage wilcox_rank(x, y, DNAID, PID, GROUP, grp1=NULL, grp2=NULL)
#' @examples result <- wilcox_sign(phen, prof, "SampleID", "ID", "Stage", "BASE", "WASH")
#' @return  Returns a result of Wilcoxon Sign-Rank Test
#' @return  type:       kind of data
#' @return  Block:      group information
#' @return  Num:        number of group
#' @return  P-value:    P by Wilcoxon Sign-Rank Test
#' @return  FDR:        adjusted by BH
#' @return  Enrichment: directory by median or directory by rank
#' @return  Occurence:  occurence of two groups
#' @return  median:     both or each group
#' @return  rank:       each group
#' @return  FDR:        adjusted P value by BH
#' @return  Odds Ratio:     95% Confidence interval
#'
#' @export
#'
wilcox_sign <- function(x, y, DNAID, PID, GROUP,
                        grp1=NULL, grp2=NULL){

  # determine x with two cols and names are corret
  phe <- x %>% select(DNAID, PID, GROUP)
  colnames(phe)[which(colnames(phe) == DNAID)] <- "SampleID"
  colnames(phe)[which(colnames(phe) == PID)] <- "ID"
  colnames(phe)[which(colnames(phe) == GROUP)] <- "Stage"
  if (length(which(colnames(phe)%in%c("SampleID","ID","Stage"))) != 3){
    warning("x without 2 cols: DNAID, ID, GROUP")
  }

  # select groups
  if(length(grp1)){
    phe.cln <- phe %>% filter(Stage%in%c(grp1, grp2)) %>%
      mutate(Stage=factor(Stage, levels = c(grp1, grp2))) %>%
      arrange(ID, Stage)
    pr <- c(grp1, grp2)
  } else {
    phe.cln <- phe %>% mutate(Stage=factor(Stage)) %>%
      arrange(ID, Stage)
    pr <- levels(phe.cln$Stage)
  }

  if (length(levels(phe.cln$Stage)) > 2) {
    stop("The levels of `group` are more than 2")
  }

  # profile
  sid <- intersect(phe.cln$SampleID, colnames(y))
  prf <- y %>% select(sid) %>%
    rownames_to_column("tmp") %>%
    # occurrence of rows more than 0.3
    filter(apply(select(., -one_of("tmp")), 1, function(x){sum(x[!is.na(x)] != 0)/length(x)}) > 0.3) %>%
    data.frame() %>% column_to_rownames("tmp") %>%
    t() %>% data.frame()

  # judge no row of profile filter
  if (ncol(prf) == 0) {
    stop("No row of profile to be choosed\n")
  }

  # determine the right order and group levels
  for(i in 1:nrow(prf)){
    if ((rownames(prf) != phe.cln$SampleID)[i]) {
      stop(paste0(i, " Wrong"))
    }
  }

  # merge phenotype and profile
  mdat <- inner_join(phe.cln %>% filter(SampleID%in%sid),
                     prf %>% rownames_to_column("SampleID"),
                     by = "SampleID")

  dat.phe <- mdat %>% select(c(1:3))
  dat.prf.tmp <- mdat %>% select(-c(1:3))
  dat.prf <- apply(dat.prf.tmp, 2, function(x){
    as.numeric(as.character(x))}) %>% data.frame()

  res <- apply(dat.prf, 2, function(x, grp){

    origin <- data.frame(value=as.numeric(x), grp)
    number <- tapply(origin$value, origin$Stage, function(x){sum(!is.na(x))})
    Num <- paste0(pr[1], number[1], "_vs_",
                  pr[2], number[2])
    # remove NA data
    dat <- origin %>% na.omit()
    intersectFun <- function(x){
      tmp <- x %>% mutate(Stage = factor(Stage))
      id <- unique(as.character(tmp$ID))
      for (i in 1:length(levels(tmp$Stage))) {
        id <- intersect(id,
          unlist(tmp %>% filter(Stage == levels(Stage)[i]) %>% select(ID)))
      }
      return(id)
    }
    dat.cln <- dat %>% filter(ID%in%intersectFun(dat)) %>%
      arrange(ID, Stage)

    p <- signif(wilcox.test(value ~ Stage, data=dat.cln, paired=T)$p.value, 6)

    # median
    md <- signif(median(dat.cln$value), 4)
    mdn <- signif(tapply(dat.cln$value, dat.cln$Stage, median), 4)
    if ( mdn[1] > mdn[2] & p < 0.05) {
      enrich1 <- pr[1]
    } else if (mdn[1] < mdn[2] & p < 0.05) {
      enrich1 <- pr[2]
    } else if (p > 0.05 | mdn[1] == mdn[2]){
      enrich1 <- "No significance"
    }

    # rank
    rk <- rank(dat.cln$value)
    rnk <- signif(tapply(rk, dat.cln$Stage, mean), 4)
    if ( rnk[1] > rnk[2] & p < 0.05) {
      enrich2 <- pr[1]
    } else if (rnk[1] < rnk[2] & p < 0.05) {
      enrich2 <- pr[2]
    } else if (p > 0.05 | rnk[1] == rnk[2]){
      enrich2 <- "No significance"
    }
    occ <- signif(tapply(dat.cln$value, dat.cln$Stage, function(x){
      round(sum(x > 0)/length(x), 4)}), 4)
    Pair <- nrow(dat.cln)

    res <- c(Num,Pair,p,enrich1,enrich2,occ,md,mdn,rnk)

    return(res)
  }, dat.phe) %>%
    t(.) %>% data.frame(.) %>%
    rownames_to_column("type") %>%
    varhandle::unfactor(.)

  colnames(res)[2:ncol(res)] <- c("Number","Paired","Pvalue",
                                  "Enrich_median", "Enrich_rank",
                                  paste0(pr, "_occurence"), "median_all",
                                  paste0(pr, "_median"), paste0(pr, "_rank"))
  res$Block <- paste0(pr[1], "_vs_", pr[2])
  res.cln <- res %>% select(c(1,14,2:13)) %>%
    mutate(Pvalue=as.numeric(Pvalue)) %>%
    mutate(FDR=p.adjust(Pvalue, method = "BH")) %>%
    arrange(FDR, Pvalue)
  res2 <- res.cln[,c(1:5,15,6:14)]


  # scale profile
  dat.prf.cln <- dat.prf[, -1]
  dat.phe.cln <- dat.phe %>% mutate(Group=ifelse(Stage==pr[1], 0, 1))
  idx <- which(colnames(dat.phe.cln) == "Group")

  # glm result for odd ratios 95%CI
  glmFun <- function(m, n){
    # calculate the glm between profile and group information
    #
    # Args:
    #   m:  result of group information which must to be numeric
    #   n:  taxonomy to be glm
    #
    # Returns:
    #   the glm result of between taxonomy group
    dat.glm <- data.frame(group=m, marker=scale(n, center=T, scale=T)) %>% na.omit()
    model <- summary(glm(group ~ marker, data = dat.glm,
                         family = binomial(link = "logit")))
    res <- signif(exp(model$coefficients["marker",1]) +
                    qnorm(c(0.025,0.5,0.975)) * model$coefficients["marker",1], 2)

    return(res)
  }

  glm_res <- t(apply(dat.prf.cln, 2, function(x, group){
    res <- glmFun(group, as.numeric(x))
    return(res)
  }, group = dat.phe.cln[, idx]))
  Odd <- glm_res %>% data.frame() %>%
    setNames(c("upper", "expected","lower")) %>%
    mutate("Odds Ratio (95% CI)" = paste0(expected, " (", lower, ";", upper, ")"))
  Odd$type <- rownames(glm_res)

  res_merge <- inner_join(res2,
                          Odd[, c(4:5)], by = "type")

  return(res_merge)
}


#' Kruskal Test
#'
#' @description
#' The Kruskal–Wallis test by ranks, Kruskal–Wallis H test (named after William Kruskal and W. Allen Wallis),
#' or one-way ANOVA on ranks is a non-parametric method for testing whether samples originate from the same distribution.
#' It is used for comparing two or more independent samples of equal or different sample sizes.
#'  It extends the Mann–Whitney U test, which is used for comparing only two groups
#'
#' @details 07/18/2019  ShenZhen China
#' @author  Hua Zou
#'
#' @param x x with sampleID and group; sampleID connected to y
#' @param y y table rownames->taxonomy; colnames->sampleID
#' @param DNAID names of sampleID to connect x and y
#' @param GROUP names of group information
#' @param grp1  one of groups
#' @param grp2  one of groups
#' @param grp3  one of groups
#'
#' @usage kruskal_test(x, y, DNAID, GROUP, grp1=NULL, grp2=NULL, grp3=NULL)
#' @examples result <- kruskal_test(phen, prof, "SampleID", "Stage")
#' @return Returns a result of Kruskal Test
#' @return  type:       kind of data
#' @return  Number:     number of group
#' @return  P-value:    Pvalue by kruskal test or pvalue by post test
#' @return  Mean+SD:    each group
#' @return  Median:     each group
#'
#' @export
#'
kruskal_test <- function(x, y, DNAID, GROUP, FILTER=T,
                         grp1=NULL, grp2=NULL,grp3=NULL){

  # determine x with two cols and names are corret
  phe <- x %>% select(DNAID, GROUP)
  colnames(phe)[which(colnames(phe) == DNAID)] <- "SampleID"
  colnames(phe)[which(colnames(phe) == GROUP)] <- "Stage"
  if (length(which(colnames(phe)%in%c("SampleID","Stage"))) != 3){
    warning("x without 2 cols: DNAID, GROUP")
  }

  # select groups
  if(length(grp1)){
    phe.cln <- phe %>% filter(Stage%in%c(grp1, grp2, grp3)) %>%
      mutate(Stage=factor(Stage, levels = c(grp1, grp2, grp3)))
    pr <- c(grp1, grp2, grp3)
  } else {
    phe.cln <- phe %>% mutate(Stage=factor(Stage))
    pr <- levels(phe.cln$Stage)
  }

  if (length(levels(phe.cln$Stage)) < 2) {
    stop("The levels of `GROUP` no more than 2")
  }

  # profile
  sid <- intersect(phe.cln$SampleID, colnames(y))
  prf <- y %>% select(sid) %>%
    rownames_to_column("tmp") %>%
    # occurrence of rows more than 0.1
    filter(apply(select(., -one_of("tmp")), 1, function(x){sum(x > 0)/length(x)}) > 0.3) %>%
    data.frame() %>% column_to_rownames("tmp") %>%
    t() %>% data.frame()

  # judge no row of profile filter
  if (ncol(prf) == 0) {
    stop("No row of profile to be choosed\n")
  }

  # determine the right order and group levels
  for(i in 1:nrow(prf)){
    if ((rownames(prf) != phe.cln$SampleID)[i]) {
      stop(paste0(i, " Wrong"))
    }
  }

  # merge phenotype and profile
  mdat <- inner_join(phe.cln %>% filter(SampleID%in%sid),
                     prf %>% rownames_to_column("SampleID"),
                     by = "SampleID")
  dat.phe <- mdat %>% select(c(1:2))
  dat.prf <- mdat %>% select(-2)
  idx <- which(colnames(dat.phe) == "Stage")

  kru.res <- apply(dat.prf[, -1], 2, function(x, grp){
    dat <- data.frame(y=as.numeric(x), group=grp) %>% na.omit()
    # p value; mean±sd
    p <- signif(kruskal.test(y ~ group, data = dat)$p.value, 4)
    mn <- tapply(dat$y, dat$group, function(x){
      num = paste(signif(mean(x), 4), "+/-", signif(sd(x), 4))
      return(num)
    })
    res <- c(p, mn)
    return(res)
  }, dat.phe[, idx]) %>% t(.) %>% data.frame(.) %>%
    rownames_to_column("tmp") %>% varhandle::unfactor(.)

  fr <- dat.phe$Stage
  cl <- unlist(lapply(levels(fr), function(x){paste0(x, "\nMean+/-Sd")}))
  colnames(kru.res)[2:ncol(kru.res)] <- c("P.value.kw", cl)

  # filter by p value < 0.05 or run all
  if (FILTER) {
    kw <- kru.res %>% filter(P.value.kw < 0.05)
    if (nrow(kw) == 0){
      res <- kru.res
      return(res)
    } else {
      kw.prf <- dat.prf %>% filter(rownames(.) %in% kw$tmp)
    }
  } else {
    kw <- kru.res
    kw.prf <- dat.prf
  }

  post.res <- apply(kw.prf, 1, function(x, grp){
    dat <- data.frame(y=as.numeric(x), group=grp) %>%
      unstack() %>% t() %>% t() %>% na.omit()
    # p value; mean+/-sd
    p <- PMCMR::posthoc.durbin.test(dat, p.adj="none")$p.value
    p.val <- p[!upper.tri(p)]
    return(c(p.val, nrow(dat)))
  }, datTol[, idx]) %>% t(.) %>% data.frame(.) %>%
    varhandle::unfactor(.)

  # names
  rownames(post.res) <- kw$tmp
  n <- length(levels(fr))
  cl <- NULL
  for(i in 1:(n-1)){
    for(j in (i+1):n){
      cl <- c(cl, paste("P.value\n", levels(fr)[i], "vs", levels(fr)[j]))
    }
  }
  colnames(post.res)[1:(n+1)] <- c(cl, "Times")

  # cbind results
  res <- left_join(kw, post.res %>% rownames_to_column("tmp"), by = "tmp")
  colnames(res)[which(colnames(res)=="tmp")] <- "type"

  return(res)
}


#' Friedman Test
#'
#' @description
#'The Friedman test is a non-parametric statistical test developed by Milton Friedman.
#'Similar to the parametric repeated measures ANOVA, it is used to detect differences
#'in treatments across multiple test attempts. The procedure involves ranking each row (or block) together,
#'then considering the values of ranks by columns
#'
#' @details 07/18/2019  ShenZhen China
#' @author  Hua Zou
#'
#' @param x x with sampleID and group; sampleID connected to x
#' @param y y table rownames->taxonomy; colnames->sampleID
#' @param DNAID names of sampleID to connect x and y
#' @param PID   id for paired test
#' @param GROUP names of group information
#' @param grp1  one of groups
#' @param grp2  one of groups
#' @param grp3  one of groups
#'
#' @usage friedman_test(x, y, DNAID, PID, GROUP,grp1=NULL, grp2=NULL,grp3=NULL)
#' @examples result <- friedman_test(phen, prof, "SampleID", "ID", "Stage")
#' @return Returns a result of Friedman Test
#' @return  type:       kind of data
#' @return  Number:     number of group
#' @return  P-value:    Pvalue by Friedman Test or  pvalue by post test
#' @return  FDR:        correct by BH in friedman test
#' @return  Mean+SD:    each group
#' @return  Median:     each group
#'
#' @export
#'
friedman_test <- function(x, y, DNAID, PID, GROUP,
                          grp1=NULL, grp2=NULL,grp3=NULL){

  # determine x with two cols and names are corret
  phe <- x %>% select(DNAID, PID, GROUP)
  colnames(phe)[which(colnames(phe) == DNAID)] <- "SampleID"
  colnames(phe)[which(colnames(phe) == PID)] <- "ID"
  colnames(phe)[which(colnames(phe) == GROUP)] <- "Stage"
  if (length(which(colnames(phe)%in%c("SampleID","ID","Stage"))) != 3){
    warning("x without 2 cols: DNAID, ID, GROUP")
  }

  # select groups
  if(length(grp1)){
    phe.cln <- phe %>% filter(Stage%in%c(grp1, grp2, grp3)) %>%
      mutate(Stage=factor(Stage, levels = c(grp1, grp2, grp3))) %>%
      arrange(ID, Stage)
    pr <- c(grp1, grp2, grp3)
  } else {
    phe.cln <- phe %>% mutate(Stage=factor(Stage)) %>%
      arrange(ID, Stage)
    pr <- levels(phe.cln$Stage)
  }

  if (length(levels(phe.cln$Stage)) < 2) {
    stop("The levels of `GROUP` no more than 2")
  }

  # profile
  sid <- intersect(phe.cln$SampleID, colnames(y))
  prf <- y %>% select(sid) %>%
    rownames_to_column("tmp") %>%
    # occurrence of rows more than 0.1
    filter(apply(select(., -one_of("tmp")), 1, function(x){sum(x > 0)/length(x)}) > 0.3) %>%
    data.frame() %>% column_to_rownames("tmp") %>%
    t() %>% data.frame()

  # judge no row of profile filter
  if (ncol(prf) == 0) {
    stop("No row of profile to be choosed\n")
  }

  # determine the right order and group levels
  for(i in 1:nrow(prf)){
    if ((rownames(prf) != phe.cln$SampleID)[i]) {
      stop(paste0(i, " Wrong"))
    }
  }

  # merge phenotype and profile
  mdat <- inner_join(phe.cln %>% filter(SampleID%in%sid),
                     prf %>% rownames_to_column("SampleID"),
                     by = "SampleID")
  dat.phe <- mdat %>% select(c(1:3))
  dat.prf <- mdat %>% select(-c(2:3))

  res <- apply(dat.prf[, -1], 2, function(x, grp){
    dat <- data.frame(y=as.numeric(x), grp)
    nmatrix <- matrix(NA, nrow = length(levels(dat$ID)),
                      ncol = length(pr),
                      byrow = T)
    colnames(nmatrix) <- pr
    rownames(nmatrix) <- levels(dat$ID)
    for(i in 1:nrow(nmatrix)){
      for(j in 1:ncol(nmatrix)){
        tmp <- dat %>% filter(ID%in% rownames(nmatrix)[i] & Stage%in%colnames(nmatrix)[j]) %>%
          select(y) %>% as.numeric()
        if(length(tmp) == 0){
          nmatrix[i, j] <- NA
        } else {
          nmatrix[i, j] <- tmp
        }
      }
    }

    # friedman p value; mean±sd
    p <- signif(friedman.test(nmatrix)$p.value, 4)
    mn <- apply(nmatrix, 2, function(x){
      num <- paste(signif(mean(x[!is.na(x)]), 4),
                   signif(sd(x[!is.na(x)]), 4),
                   collapse = "+/-")})
    md <- apply(nmatrix, 2, function(x){
      signif(median(x[!is.na(x)]), 4)})
    nu <- apply(nmatrix, 2, function(x){
      length(x)})
    Num <-  paste(paste(pr, nu, sep="_"), collapse = " vs ")

    # post test
    postp <- signif(PMCMR::posthoc.durbin.test(nmatrix, p.adj="none")$p.value, 4)
    p.val <- postp[!upper.tri(postp)]

    res <- c(p, mn, md, Num, p.val)

    return(res)
  }, dat.phe[, c(2:3)]) %>% t(.) %>% data.frame(.) %>%
    rownames_to_column("tmp") %>% varhandle::unfactor(.)

  mean_sd <- unlist(lapply(pr, function(x){paste0(x, "\nMean+/-Sd")}))
  MD <- unlist(lapply(pr, function(x){paste0(x, "_Median")}))
  post_name <- NULL
  for(i in 1:(length(pr)-1)){
    for(j in (i+1):length(pr)){
      post_name <- c(post_name, paste("P.value\n", pr[i], "vs", pr[j], collapse = ""))
    }
  }
  colnames(res)[2:ncol(res)] <- c("P.value", mean_sd, MD, "Number", post_name)
  res$FDR <- with(res, p.adjust(as.numeric(P.value), method = "BH"))

  return(res[, c(1,9,2,13,10:12,3:8)])
}

