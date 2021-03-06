#' \code{theme_box} A ggplot2 theme for boxplot
#'
#' @export
#'
theme_box <- function(){
  theme_bw(base_size=12) +
  theme(
    plot.title = element_text(size=10, color="black", face="bold", hjust=.5),
    axis.title = element_text(size=10, color="black", face="bold"),
    axis.text = element_text(size=9, color="black"),
    axis.ticks.length = unit(-0.05, "in"),
    axis.text.y = element_text(margin=unit(c(0.3,0.3,0.3,0.3), "cm"), size=9),
    axis.text.x = element_text(margin=unit(c(0.3,0.3,0.3,0.3), "cm")),
    text = element_text(size=8, color="black"),
    strip.text = element_text(size=9, color="black", face="bold"),
    panel.grid = element_blank())
}
