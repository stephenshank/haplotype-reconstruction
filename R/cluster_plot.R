library(tidyverse)
df <- read_csv(snakemake@input[[1]]);
ggplot(df)+geom_point(aes(d1,d2, color=cluster))+facet_wrap(~block, ncol=5)
ggsave(snakemake@output[[1]])