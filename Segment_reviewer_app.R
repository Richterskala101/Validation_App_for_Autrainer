library(shiny)
library(tuneR)
library(seewave)
library(dplyr)
library(ggplot2)
library(pROC)

# ==== Configuration ====
segment_dir <- "exported_segments"  # Root folder containing class subfolders
validation_file <- "validation_results.csv"  # Where to save the results
segment_duration <- 3  # seconds

# ==== Helper Functions ====
list_classes <- function() {
  list.dirs(segment_dir, full.names = FALSE, recursive = FALSE)
}

list_files_in_class <- function(class) {
  list.files(file.path(segment_dir, class), pattern = "\\.wav$", full.names = TRUE)
}

# ==== UI ====
ui <- fluidPage(
  titlePanel("Segment Reviewer for Audio Classification"),
  sidebarLayout(
    sidebarPanel(
      selectInput("class", "Choose Class:", choices = list_classes()),
      actionButton("correct", "Correct", class = "btn-success"),
      actionButton("incorrect", "Incorrect", class = "btn-danger"),
      actionButton("skip", "Skip"),
      actionButton("prev", "Previous"),
      br(), br(),
      verbatimTextOutput("clip_info"),
      tags$audio(id = "audio", src = "", type = "audio/wav", controls = NA),
      br(), br(),
      helpText("This app allows you to manually validate predicted segments from an audio classification model."
               ,"After enough annotations, a logistic regression is fitted to calibrate model scores into probabilities."
               ,"Thresholds are calculated for precision levels 0.7, 0.8, and 0.9. A precision-recall curve shows performance over score thresholds."),
      plotOutput("logisticPlot"),
      tableOutput("thresholds"),
      plotOutput("prPlot")
    ),
    mainPanel(
      plotOutput("spectrogram")
    )
  )
)

# ==== Server ====
server <- function(input, output, session) {
  state <- reactiveValues(
    files = NULL,
    index = 1,
    data = data.frame(file = character(), score = numeric(), class = character(), outcome = integer())
  )
  
  observeEvent(input$class, {
    state$files <- list_files_in_class(input$class)
    state$index <- 1
  })
  
  current_file <- reactive({
    req(state$files)
    state$files[state$index]
  })
  
  observeEvent(input$correct, save_outcome(1))
  observeEvent(input$incorrect, save_outcome(0))
  observeEvent(input$skip, advance())
  observeEvent(input$prev, {
    state$index <- max(1, state$index - 1)
  })
  
  save_outcome <- function(outcome_val) {
    function(...) {
      file <- basename(current_file())
      parts <- strsplit(file, "_")[[1]]
      score <- as.numeric(gsub(".wav", "", parts[length(parts)]))
      new_entry <- data.frame(
        file = file,
        score = score,
        class = input$class,
        outcome = outcome_val
      )
      state$data <- bind_rows(state$data, new_entry)
      advance()
    }
  }
  
  advance <- function() {
    state$index <- min(state$index + 1, length(state$files))
  }
  
  output$clip_info <- renderPrint({
    paste("Clip:", basename(current_file()),
          "[", state$index, "/", length(state$files), "]")
  })
  
  output$spectrogram <- renderPlot({
    wav <- readWave(current_file())
    spectro(wav, main = basename(current_file()), flim = c(0, 10))
  })
  
  output$audio_ui <- renderUI({
    req(current_file())
    tags$audio(src = current_file(), type = "audio/wav", controls = NA)
  })
  
  
  output$logisticPlot <- renderPlot({
    val <- state$data
    if (sum(!is.na(val$outcome)) < 10) return(NULL)
    model <- glm(outcome ~ score, family = "binomial", data = val, na.action = na.omit)
    scores <- seq(0, 1, length.out = 100)
    probs <- predict(model, newdata = data.frame(score = scores), type = "response")
    ggplot(data.frame(score = scores, prob = probs), aes(x = score, y = prob)) +
      geom_line(color = "blue") +
      labs(title = "Logistic Regression Calibration", x = "Score", y = "Probability Correct") +
      geom_hline(yintercept = c(0.7, 0.8, 0.9), linetype = "dashed", color = "grey")
  })
  
  output$thresholds <- renderTable({
    val <- state$data
    if (sum(!is.na(val$outcome)) < 10) return(NULL)
    model <- glm(outcome ~ score, family = "binomial", data = val, na.action = na.omit)
    p_vals <- c(0.7, 0.8, 0.9)
    thresholds <- sapply(p_vals, function(p) {
      (log(p / (1 - p)) - coef(model)[1]) / coef(model)[2]
    })
    data.frame(Precision = p_vals, Threshold = round(thresholds, 3))
  })
  
  output$prPlot <- renderPlot({
    val <- state$data
    if (nrow(val) < 10) return(NULL)
    pr <- roc(val$outcome, val$score, quiet = TRUE)
    pr_data <- data.frame(thresholds = pr$thresholds, sensitivities = pr$sensitivities, specificities = pr$specificities)
    ggplot(pr_data, aes(x = 1 - specificities, y = sensitivities)) +
      geom_line(color = "darkred") +
      labs(title = "Precision-Recall (ROC) Curve", x = "False Positive Rate", y = "True Positive Rate") +
      theme_minimal()
  })
  
  onStop(function() {
    write.csv(state$data, validation_file, row.names = FALSE)
  })
}

shinyApp(ui, server)
