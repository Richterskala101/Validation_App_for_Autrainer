library(tuneR)
library(dplyr)
library(fs)

# === CONFIG ===
input_csv <- "//myr/home/darend/Documents/Predictions_ABGS_BeSound_Sandra/results.csv"  # Your model's output
audio_folder <- "//myr/home/darend/Documents/Predictions_ABGS_BeSound_Sandra/test"
output_folder <- "//myr/home/darend/Documents/Predictions_ABGS_BeSound_Sandra/Segments"
segment_length <- 10  # in seconds
n_per_class <- 30    # number of segments to export per class

# === READ PREDICTIONS ===
preds <- read.csv(input_csv)
preds <- preds %>%
  select(-output) |> 
  mutate(label = gsub("\\[|\\]|'", "", prediction),
         start = as.numeric(sub("^(\\d+\\.\\d+)-.*", "\\1", offset)),
         end = as.numeric(sub(".*-(\\d+\\.\\d+)$", "\\1", offset)))
  
  

# === EXPORT SEGMENTS ===
dir_create(output_folder)

for (i in seq_len(nrow(preds))) {
  row <- preds[i, ]
  class_dir <- file.path(output_folder, row$label)
  dir_create(class_dir)
  
  # Load original file
  wav_path <- file.path(audio_folder, row$file)
  if (!file.exists(wav_path)) next
  
  wav <- readWave(wav_path)
  
  # Calculate start and end in samples
  samp_rate <- wav@samp.rate
  start_sample <- as.integer(row$start * samp_rate)
  end_sample <- start_sample + segment_length #* samp_rate - 1
  
  if (end_sample > length(wav@left)) next  # skip if out of bounds
  
  # Extract segment
  segment <- extractWave(wav, from = start_sample, to = end_sample, xunit = "samples")
  
  # Filename includes score and original file ID
  outfile <- sprintf("%s_%.2f.wav", tools::file_path_sans_ext(row$file), row$score)
  writeWave(segment, file.path(class_dir, outfile))
}




# nbew
for (i in seq_len(nrow(preds))) {
  row <- preds[i, ]
  class_dir <- file.path(output_folder, row$label)
  dir_create(class_dir)
  
  # Load original file
  wav_path <- file.path(audio_folder, row$filename)
  if (!file.exists(wav_path)) next
  
  wav <- readWave(wav_path)
  
  # Calculate start and end in samples
  samp_rate <- wav@samp.rate
  start_sample <- as.integer(row$start * samp_rate)
  end_sample <- start_sample + segment_length * samp_rate - 1
  
  if (end_sample > length(wav@left)) next
  
  # Extract segment
  segment <- extractWave(wav, from = start_sample, to = end_sample, xunit = "samples")
  
  # --- 🔍 Get score dynamically ---
  labels <- trimws(unlist(strsplit(row$label, ",")))  # e.g., c("Geo", "Sil")
  
  # Check these label columns exist in preds
  valid_labels <- labels[labels %in% colnames(preds)]
  
  # Get the max score among predicted labels
  score <- max(as.numeric(row[, valid_labels]), na.rm = TRUE)
  
  # Create output filename
  outfile <- sprintf("%s_%.2f.wav", tools::file_path_sans_ext(row$filename), score)
  writeWave(segment, file.path(class_dir, outfile))
}
