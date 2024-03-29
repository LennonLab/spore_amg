# plotting function to aid in scrutinizing viral scaffolds with potential AMGs


# Load packages needed ----------------------------------------------------
library(here)
library(tidyverse)
library(gggenes)
library(cowplot)
library(qpdf)


# Function ------------------------------------------------------------

plot_amg_scaffolds <- function(
  data_dir, # main directory of DRAM results
  sets, # dataset(s) to be analyzed (folder name in data_dir)
  sets_name=sets[1], # name of folder in which the plots will be stored
  amg_name, # gene name to be marked on scaffolds
  ko_amg # the KO identifier of the focal gene
){
  #> list of sporulation genes -------------------------------------------------------
  # Marking all sporulation genes on plot
  spor_genes <- read_csv(here("spor_gene_list/data/dram_spore_genes.csv"), progress = FALSE) %>% 
    # genes with KO
    filter(!is.na(gene_id.ko)) %>% 
    separate(gene_description, into = c("symbol", "description"), sep = ";") %>% 
    rename(ko = gene_id.ko)
  
  spor_ko <- 
    unique(spor_genes$ko)
  
  # > Enriched sporulation genes -------------------------------------------------
  # list of all enriched genes - these too will be noted on plot
  
  d.enriched <- read_csv(here("dram_metaG/data/enrichment/spor_enriched.csv"),progress = FALSE) 
  
  #enriched KOs 
  enriched_ko <- d.enriched$gene_id 
  
  # > get scaffold annotations  --------------------------------------------------
  # Iterate over all datasets and pull out the full annotation data 
  # for scaffold containing the AMG(s)  of interest
  
  #initialize tibble to collect data
  d.annot <- tibble()
  
  for (cur_set in sets){
    # get scaffold names from amg summary
    d.amg <- read_tsv(paste(data_dir, cur_set, "amg_summary.tsv", sep = "/"),progress = FALSE) %>% 
      filter(gene_id %in% ko_amg)
    
    # get full annotation for scaffolds
    
    # >> filtering function from chunked reading ----------------------------------
    f <- function(.data, pos) {
      filter(.data, scaffold %in% d.amg$scaffold) 
    }
    # name of file with scaffold annotations
    annot_file <- 
      list.files(paste(data_dir, cur_set, sep = "/"), pattern = "annotation", full.names = T)
    
    # read annotations
    annot <- read_tsv_chunked(annot_file,
                              DataFrameCallback$new(f), 
                              chunk_size = 10000,
                              progress = FALSE) 
    #skip empty data
    if (nrow(annot) < 1) {next}
    
    # add index and set
    annot$idx <- 
      annot %>% 
      group_by(scaffold) %>% 
      group_indices()
    
    annot$set <- cur_set
    
    annot <- annot %>% relocate(set, idx)
    
    # there is some inconsistency on column headers
    if (!"kegg_id" %in% colnames(annot)){
      if("ko_id" %in% colnames(annot)){
        annot <- 
          annot %>% 
          rename(kegg_id = ko_id)
      }
    }
    
    d.annot <- bind_rows(d.annot, annot)
    
  }
  
rm(annot)


# stop if no data
if(is.null(dim(d.annot)) | nrow(d.annot)<1){
  # make folder for plots
  if (!dir.exists(here("dram_metaG/plots", "scrutinize", amg_name))){
    dir.create(
      here("dram_metaG/plots", "scrutinize", amg_name),
      recursive = T
    )
  }
  file.create(here("dram_metaG/plots", "scrutinize", amg_name,
                   paste0(amg_name,"_",sets_name,"_no_data.info")))
  
  return("no data found")
}

  # > add informative properties for AMG --------------------------------------

# kegg_hit & pfam_hits
  # Phages will typically have many genes with no annotation ("NA") 
  # or hypothetical annotations. Bacteria typically have well annotated stretches.
d.annot <- d.annot %>% 
  mutate(has_annot = !(is.na(kegg_hit) & is.na(pfam_hits)))


# Hallmark viral gene terms in annotation
v_hallmark <- 
  c( "virion", "capsid", "tail", "terminase", "Baseplate",
     "phage", "virus", "Reverse transcriptase", "head")

d.annot <- d.annot %>% 
  mutate(viral_hallmark = 
           str_detect(kegg_hit, str_c(v_hallmark, collapse = "|") %>%
                        regex(ignore_case = T))|
           str_detect(pfam_hits, str_c(v_hallmark, collapse = "|")%>%
                        regex(ignore_case = T))) %>%
  mutate(viral_hallmark = if_else(is.na(viral_hallmark), FALSE, viral_hallmark)) %>% 
  # false positives (lamin and laminin tail domains and hammerhead)
    # combine annotations to overcome NA in one of the columns
  mutate(tst=paste(kegg_hit,pfam_hits, sep = ";")) %>% 
  mutate(viral_hallmark = 
           if_else(
             str_detect(tst, regex("laminin", ignore_case = T))|
               str_detect(tst, regex("(^|_| )lamin(_| |$)", ignore_case = T))|
               str_detect(tst, regex("hammerhead", ignore_case = T)),
             FALSE, viral_hallmark)) %>% 
  select(-tst)
  
# hypothetical genes are a special class
d.annot <-
  d.annot %>% 
  mutate(one_NA = is.na(kegg_hit) | is.na(pfam_hits)) %>% 
  mutate(hypothetical = 
           case_when(
             #both hypothetical
             str_detect(kegg_hit, regex("hypothetical|unknown", ignore_case = T))&
               str_detect(pfam_hits, regex("hypothetical|unknown", ignore_case = T)) ~ TRUE,
             
             # one hypothetical an other NA
             str_detect(kegg_hit, regex("hypothetical|unknown", ignore_case = T))&
               one_NA ~ TRUE,
             str_detect(pfam_hits, regex("hypothetical|unknown", ignore_case = T))&
               one_NA ~ TRUE,
             TRUE ~ FALSE
           )
         )
  
  
           
###
# combine 
d.annot <- d.annot %>% 
  mutate(gene_type = case_when(
    viral_hallmark ~ "viral",
    hypothetical ~ "hypothetical",
    has_annot ~ "other annotation",
    TRUE ~ "unannotated")) %>% 
  mutate(gene_type = factor(
    gene_type, levels = c("other annotation","hypothetical","unannotated","viral")))
  
    
  # ) %>% as_factor() %>% fct_relevel("other annotation"))

# add vir_sorter cat
d.annot <- 
  d.annot %>% 
  mutate(v.cat = str_extract(scaffold, "cat_.$")) 

  #>  plot --------------------------------------------------------------------
# https://cran.r-project.org/web/packages/gggenes/vignettes/introduction-to-gggenes.html

# make folder for plots
if (!dir.exists(here("dram_metaG/plots", "scrutinize", amg_name, sets_name))){
  dir.create(
    here("dram_metaG/plots", "scrutinize", amg_name, sets_name),
    recursive = T
  )
}

# parameters for pagination

row_page <- 10
cur_row_page <- row_page
col_page <- 1
page_h <- 11

n_scaffolds <- d.annot %>% 
  select(set, idx) %>% 
  distinct() %>% 
  nrow()

n.pages <-  ceiling(n_scaffolds/(row_page  * col_page) )




d.annot <-  d.annot%>%
  mutate(set_label = str_replace_all(set, "-|_", " "))

# list of scaffolds to split across pages
scafs <-  d.annot %>% 
  select(set, idx, scaffold) %>% 
  distinct() %>% 
  arrange(set, idx)

# limit number of plots (max 200)
for(pg in 1: min(n.pages, 20)){
  
  
  # corrections for last page if needed
  if(pg == n.pages){
    cur_row_page <- n_scaffolds - (row_page*(pg-1))
    page_h = page_h * ((cur_row_page+1)/row_page)
  }
  
  n.scafs <- seq(from = pg*row_page-row_page+1, length.out = cur_row_page)
  
  d.cur <- d.annot  %>% 
    filter(scaffold %in% scafs$scaffold[n.scafs]) 
  p <- d.cur %>% 

    ggplot(aes(y = strandedness/3,
               xmin = start_position,
               xmax = end_position,
               fill = gene_type,
               forward = strandedness
    )) +

    # middle line
    geom_hline(yintercept = 0, color = "black", size=0.1)+

    # mark other sporulation genes with grey background
    geom_rect(data = d.cur %>%
                filter((kegg_hit %in% spor_ko) | (kegg_id %in% spor_ko)),
              aes(xmin = start_position, xmax = end_position),
              ymin = -Inf, ymax = Inf, fill = "grey70") +

    # mark enriched sporulation genes with cyan background
    geom_rect(data = d.cur %>%
              filter((kegg_id %in% enriched_ko)),
              aes(xmin = start_position, xmax = end_position),
              ymin = -Inf, ymax = Inf, fill = "cyan3") +

    # mark amg with pink background
    geom_rect(data = d.cur %>%
                filter(str_detect(kegg_hit, ko_amg) | (kegg_id %in% ko_amg)),
              aes(xmin = start_position, xmax = end_position),
              ymin = -Inf, ymax = Inf, fill = "pink") +
    
    # mark plot amg with label
    geom_text(x = Inf, y = -0.9, label = amg_name, color = "red", hjust =1.1, size=2) +


    # plot all genes
    geom_gene_arrow(color = "black") +

    # mark amg with red arrow
    geom_gene_arrow(data = d.cur %>%
                      filter(str_detect(kegg_hit, ko_amg) | (kegg_id %in% ko_amg)),# %>%
                    # filter(idx %in% n_genomes),
                    aes(y=strandedness/3),
                    size=0.5, fill = "red") +

    # label with gene number
    geom_gene_label(aes(label = gene_position),
                    align = "centre") +

    # wrap across scaffolds
    facet_wrap(
      set_label ~ idx + v.cat,
      scales = "free_x", strip.position = "left",
      ncol = col_page, nrow = cur_row_page,
      labeller =  labeller(set_label = label_wrap_gen(width = 10))
    )+

    # make nice
    theme_classic()+
    panel_border(color = "black", size=0.5)+
    theme(axis.text.y = element_blank(),
          legend.position = "bottom",
          # strip.background = element_blank(),
          strip.text = element_text(size = 8),
          axis.title.y = element_blank(),
          axis.ticks.y = element_blank())+
    scale_x_continuous(expand = c(0, 0))+
    scale_fill_viridis_d()+
    ylim(-1,1)+
    guides(fill = guide_legend(title = "gene\ncolor"))+
    labs(caption = "background: sporulation gene (grey); enriched sporulation gene (cyan); focal sporulation gene (pink)")

  # save single page of plots
  file_name <- paste0(amg_name,"_genomes_p0",pg,".pdf")
  ggsave(here("dram_metaG/plots", "scrutinize", amg_name, sets_name, file_name),
         plot = p,
         width = 8, height = page_h)
}

# combine pages
pgs <- list.files(here("dram_metaG/plots", "scrutinize", amg_name, sets_name),
                  pattern = "pdf", full.names = T)
  #sort numericalty by page numbers
  pgs <-pgs[str_order(pgs,numeric = T)]
  
pdf_combine(pgs,
            output = here("dram_metaG/plots", "scrutinize", amg_name,
                          paste0(amg_name,"_",sets_name,".pdf")))
# delete single page files
unlink(here("dram_metaG/plots", "scrutinize", amg_name, sets_name), recursive = T)


# > save annotations plotted -----------------------------------------------------
if (!dir.exists(here("dram_metaG/data", "scrutinize", amg_name))){
  dir.create(
    here("dram_metaG/data", "scrutinize"),
    recursive = T
  )
}

write_csv(d.annot,
          here("dram_metaG/data", "scrutinize", 
               paste0(amg_name, "_", sets_name,"_annot.csv")))

return(paste("done", amg_name, sets_name))
}
# End of function ------------------------------------------