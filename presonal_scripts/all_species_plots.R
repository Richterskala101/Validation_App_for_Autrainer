library(dplyr)
# load validation
validated_files1 = read.csv("C:/Users/darend/Downloads/Results_Validation_Segments_1.csv",
                           sep = ";")|> 
  select(file, score, class, outcome)

validated_files2 = read.csv("C:/Users/darend/Downloads/validation_segments_2.csv",
                            sep = ";") |> 
  mutate(class = species,
          outcome = as.numeric(Validation)) |> 
  select(file, score, class, outcome)

validated_files = rbind(validated_files1, validated_files2)


library(dplyr)
library(ggplot2)
library(purrr)
library(broom)
library(tidyr)

# Assuming your data frame is called df
# df <- read.csv("yourfile.csv")

models <- validated_files %>%
  group_by(class) %>%
  nest() %>%
  mutate(
    model = map(data, ~ glm(outcome ~ score, data = ., family = binomial)),
    augmented = map2(model, data, ~ augment(.x, newdata = data.frame(score = seq(0, 1, 0.01))))
  )

precision_thresholds <- validated_files %>%
  group_by(class) %>%
  summarise(
    threshold_07 = {
      # Find minimum score where precision >= 0.7
      sapply(0:100/100, function(thr) {
        sel <- score >= thr
        if(sum(sel) > 0) mean(outcome[sel]) else NA
      }) -> prec
      score_grid <- 0:100/100
      score_grid[which(prec >= 0.7)[1]]
    },
    threshold_09 = {
      sapply(0:100/100, function(thr) {
        sel <- score >= thr
        if(sum(sel) > 0) mean(outcome[sel]) else NA
      }) -> prec
      score_grid <- 0:100/100
      score_grid[which(prec >= 0.9)[1]]
    }
  )


# make plots
plot_data <- models %>%
  unnest(augmented) %>%
  rename(prob = .fitted)

plot_thresholds <- precision_thresholds %>%
  pivot_longer(cols = starts_with("threshold"), names_to = "level", values_to = "score_thr")

plot_data <- validated_files %>%
  group_by(class) %>%
  group_modify(~ {
    m <- glm(outcome ~ score, data = ., family = binomial)
    newdata <- tibble(score = seq(min(.$score), max(.$score), length.out = 100))
    newdata$prob <- predict(m, newdata, type = "response") # <-- important
    newdata
  })


ggplot(plot_data, aes(x = score, y = prob)) +
  geom_line(color = "blue") +
  geom_point(data = validated_files, aes(x = score, y = outcome), alpha = 0.2) +
  geom_vline(data = plot_thresholds, aes(xintercept = score_thr, color = level),
             linetype = "dashed") +
  facet_wrap(~class) +
  labs(y = "Predicted probability", title = "Logistic regression per class") +
  theme_minimal()



# make table
