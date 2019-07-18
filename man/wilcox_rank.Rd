% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/14.nonparametric_test.R
\name{wilcox_rank}
\alias{wilcox_rank}
\title{Wilcoxon Rank-Sum Test}
\usage{
result <- wilcox_rank(phen, prof, "SampleID", "Stage", "BASE", "WASH")
}
\arguments{
\item{DNAID}{names of sampleID to connect phen and prof}

\item{GROUP}{names of group information, only contail two levels if grp1 or grp2 haven't been provided}

\item{grp1}{one of groups to be converted into 0}

\item{grp2}{one of groups to be converted into 1}

\item{phen}{phenotype with sampleID and group; sampleID connected to profile.}

\item{prof}{profile table rownames->taxonomy; colnames->sampleID}
}
\value{
Returns a result of Wilcoxon Rank-Sum Test
  type:       kind of data
  Block:      group information
  Num:        number of group
  P-value:    P by Wilcoxon Rank-Sum Test
  FDR:        adjusted by BH
  Enrichment: directory by median
              directory by rank
  Occurence:  occurence of two groups
  median:     both or each group
  rank:       each group
  FDR:        adjusted P value by BH
  Odds Ratio:     95% Confidence interval
}
\description{
Tests for the difference between two independent variables; takes into account magnitude and direction of difference
}
\details{
07/18/2019
}
\author{
Hua Zou
}