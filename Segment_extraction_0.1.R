library(tuneR)
library(dplyr)
library(fs)
library(stringr)

# === CONFIG ===
input_csv <- "B:/diverses/HearTheSpecies/Database/Test_Insect_Model/AEG18_RP/results.csv"  # Your model's output
audio_folder <- "B:/2023/2024/HearTheSpecies_Grasslands/AEG18/AEG18_RP"
output_folder <- "B:/diverses/HearTheSpecies/Database/Test_Insect_Model/segments3"
segment_length <- 4   # seconds
n_per_class    <- 30  # max segments per species

# === READ & PREP DATA ===
preds <- read.csv(input_csv) %>%
  mutate(
    # parse start/end (in seconds)
    start = as.numeric(sub("^(\\d+\\.?\\d*)-.*", "\\1", offset)),
    end   = as.numeric(sub(".*-(\\d+\\.?\\d*)$", "\\1", offset))
  ) %>%
  filter(!is.na(start), !is.na(end)) 

# Identify “species score” columns (all numeric, except our new start/end)
skip_cols <- c("offset","prediction","start","end","filename")
species_cols <- preds %>% 
  select(-one_of(skip_cols)) %>% 
  select_if(is.numeric) %>% 
  names()

# ensure output folder exists
dir_create(output_folder)

# === LOOP OVER SPECIES ===
for (sp in species_cols) {
  message("Processing species: ", sp)
  
  # take all rows _with_ a non-zero score, then rank
  top_rows <- preds %>%
    filter(.data[[sp]] > 0) %>%
    arrange(desc(.data[[sp]])) %>%
    slice_head(n = n_per_class)
  
  if (nrow(top_rows) == 0) {
    message("  → no segments with positive score; skipping.")
    next
  }
  
  # make species folder
  sp_dir <- file.path(output_folder, sp)
  dir_create(sp_dir)
  
  # extract each top segment
  for (i in seq_len(nrow(top_rows))) {
    row <- top_rows[i, ]
    
    # load audio
    wav_path <- file.path(audio_folder, row$filename)
    if (!file.exists(wav_path)) {
      warning("Missing file: ", wav_path); next
    }
    wav <- readWave(wav_path)
    sr  <- wav@samp.rate
    
    # compute sample indices
    from_samp <- as.integer(row$start * sr)
    to_samp   <- from_samp + as.integer(segment_length * sr)
    if (to_samp > length(wav@left)) {
      warning("Segment exceeds bounds for ", row$filename); next
    }
    
    seg <- extractWave(wav, from = from_samp, to = to_samp, xunit = "samples")
    
    # build filename: <orig>_<score>.wav
    base <- tools::file_path_sans_ext(basename(row$filename))
    score <- round(row[[sp]], 2)
    out  <- sprintf("%s_%.2f.wav", base, score)
    
    writeWave(seg, file.path(sp_dir, out))
  }
}

filelist <- list.files(output_folder, recursive = T)

table1 <- as.data.frame(filelist) |> 
  mutate(file = basename(filelist),
         species = str_extract(filelist, "^[^/]+"),
         score =  str_extract(filelist, "[0-9]+\\.[0-9]+(?=\\.wav$)"))
write.csv(table1, "B:/diverses/HearTheSpecies/Database/Test_Insect_Model/segments3/validation_segments_3.csv",
          row.names = F, quote = F)
