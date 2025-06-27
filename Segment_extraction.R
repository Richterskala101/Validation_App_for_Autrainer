library(tuneR)
library(dplyr)
library(fs)

# === CONFIG ===
input_csv <- "B:/diverses/HearTheSpecies/Database/Insect_Acoustics/InsectSet_Ode_Baker/001_test/results.csv"  # Your model's output
audio_folder <- "B:/diverses/HearTheSpecies/Database/Insect_Acoustics/InsectSet_Ode_Baker"
output_folder <- "B:/diverses/HearTheSpecies/Database/Insect_Acoustics/InsectSet_Ode_Baker/001_test/exported_segments"
segment_length <- 4  # in seconds
n_per_class <- 30    # number of segments to export per class

# === READ PREDICTIONS ===
preds <- read.csv(input_csv)
preds <- preds %>%
  select(-output) |> 
  mutate(label = )
  
  


# Optional: clean filename if needed (e.g., remove folder prefix)
# submission$filename <- basename(submission$filename)
# === EXPORT SEGMENTS ===
dir_create(output_folder)

for (i in seq_len(nrow(submission))) {
  row <- submission[i, ]
  class_dir <- file.path(output_folder, row$label)
  dir_create(class_dir)
  
  # Load original file
  wav_path <- file.path(audio_folder, row$file)
  if (!file.exists(wav_path)) next
  
  wav <- readWave(wav_path)
  
  # Calculate start and end in samples
  samp_rate <- wav@samp.rate
  start_sample <- as.integer(row$start * samp_rate)
  end_sample <- start_sample + segment_length * samp_rate - 1
  
  if (end_sample > length(wav@left)) next  # skip if out of bounds
  
  # Extract segment
  segment <- extractWave(wav, from = start_sample, to = end_sample, xunit = "samples")
  
  # Filename includes score and original file ID
  outfile <- sprintf("%s_%.2f.wav", tools::file_path_sans_ext(row$file), row$score)
  writeWave(segment, file.path(class_dir, outfile))
}
