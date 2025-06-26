# Validation Aplication for model predictions created with Autrainer models
## R Scripts and Shiny App for manual validation of predictions from autrainer models

This is work in progress. If you encounter any problems or can think of improvements, feel free to email me: dominik.arend@bio.uni-freiburg.de

## Theoretical Background
Machine learning classifiers, including sound recognition models like BirdNET, InsectNet or custom Bio/Geo/Anthropophony classifiers, typically produce confidence scores between 0 and 1. While these resemble probabilities, they are actually unitless values resulting from a transformation (often a sigmoid) of the model's internal logits. These scores are not directly interpretable as probabilities because their calibration depends on the data distribution, the model's architecture, and the class it predicts. For instance, a score of 0.8 might indicate high confidence for one species but a much lower actual correctness probability for another.

To address this, Wood & Kahl (2024) recommend post hoc calibration using logistic regression, where validated predictions (labeled correct/incorrect by humans) are modeled against their original confidence scores. This approach transforms abstract model outputs into real-world probabilities of correctness, allowing thresholds to be set for desired precision levels (e.g., 0.9). This process makes model outputs actionable for ecological monitoring, where knowing the reliability of detections is more important than just their frequency. These principles are broadly applicable to other audio classifiers beyond BirdNET.

### Logistic regression
Logistic Regression Equation

Let:

    p = probability prediction is correct

    score = BirdNET or other model score (e.g., [0–1])

    outcome = 1 if prediction was correct, 0 if incorrect

Then:

    model <- glm(outcome ~ score, family = "binomial", data = validation_data)
    threshold_for_0.9 <- (log(0.9 / (1 - 0.9)) - coef(model)[1]) / coef(model)[2]

## App Workflow
1. Export audio segments and their scores.
2. Let users manually validate them.
3. Use logistic regression to calibrate prediction scores into real-world probabilities.
4. Precision thresholds (e.g., for 0.7, 0.8, 0.9 probability) are displayed for the user to choose.

## Help: How this app works

**Purpose**  
This tool helps validate segments predicted by a machine learning model.

- Each audio clip was predicted to belong to a class (e.g., a species or sound type).
- The reviewer listens and marks each prediction as Correct or Incorrect.

**Under the hood**  
- A **logistic regression** is fit using the validated clips to convert scores into probabilities.

- A **calibration curve** (score vs. probability) is plotted.

- You also get thresholds for 0.7, 0.8, and 0.9 probability of correctness.

- The **Precision-Recall (ROC) Curve** helps evaluate model performance across thresholds.


## Literature
Wood, C.M., Kahl, S. Guidelines for appropriate use of BirdNET scores and other detector outputs. J Ornithol 165, 777–782 (2024). https://doi.org/10.1007/s10336-024-02144-5