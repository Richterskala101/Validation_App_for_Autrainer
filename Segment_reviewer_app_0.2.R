library(shiny)
library(shinyFiles)
library(tuneR)
library(seewave)
library(dplyr)
library(ggplot2)
library(pROC)
library(fs)

# ==== UI ====
ui <- fluidPage(
  titlePanel("Segment Reviewer for Audio Classification"),
  
  sidebarLayout(
    sidebarPanel(
      shinyDirButton("segment_dir_btn", "Choose Segment Directory", "Select segment folder"),
      verbatimTextOutput("segment_dir_display"),
      textInput("validation_file", "Validation File Name", value = "validation_results.csv"),
      numericInput("segment_duration", "Segment Duration (seconds)", value = 5, min = 1),
      actionButton("load_data", "Load Segment Classes"),
      uiOutput("class_ui"),
      actionButton("correct", "Correct", class = "btn-success"),
      actionButton("incorrect", "Incorrect", class = "btn-danger"),
      actionButton("skip", "Skip"),
      actionButton("prev", "Previous"),
      br(), br(),
      verbatimTextOutput("clip_info"),
      tags$audio(id = "audio", src = "", type = "audio/wav", controls = NA),
      br(), br(),
      helpText("This app allows you to manually validate predicted segments from an audio classification model.",
               "After enough annotations, a logistic regression is fitted to calibrate model scores into probabilities.",
               "Thresholds are calculated for precision levels 0.7, 0.8, and 0.9."),
      plotOutput("logisticPlot"),
      tableOutput("thresholds"),
      plotOutput("prPlot")
    ),
    
    mainPanel(
      plotOutput("spectrogram")
    )
  )
)

# ==== SERVER ====
server <- function(input, output, session) {
  # File system access
  volumes <- c(Home = fs::path_home(), "B:" = "B:/", "C:" = "C:/", "D:" = "D:/")
  shinyDirChoose(input, "segment_dir_btn", roots = volumes, session = session)
  segment_dir <- reactiveVal(NULL)
  
  observeEvent(input$segment_dir_btn, {
    dir_path <- parseDirPath(volumes, input$segment_dir_btn)
    if (length(dir_path) > 0 && dir.exists(dir_path)) {
      segment_dir(normalizePath(dir_path))
    }
  })
  
  output$segment_dir_display <- renderPrint({
    segment_dir()
  })
  
  # App state
  state <- reactiveValues(
    files = NULL,
    index = 1,
    data = data.frame(file = character(), score = numeric(), class = character(), outcome = integer()),
    classes = character()
  )
  
  # Load classes
  observeEvent(input$load_data, {
    req(segment_dir())
    classes <- list.dirs(segment_dir(), full.names = FALSE, recursive = FALSE)
    state$classes <- classes
    updateSelectInput(session, "class", choices = classes)
  })
  
  # Class selector
  output$class_ui <- renderUI({
    req(state$classes)
    selectInput("class", "Choose Class:", choices = state$classes)
  })
  
  # When class changes, list files
  observeEvent(input$class, {
    req(segment_dir())
    class_path <- file.path(segment_dir(), input$class)
    state$files <- list.files(class_path, pattern = "\\.wav$", full.names = TRUE)
    state$index <- 1
  })
  
  current_file <- reactive({
    req(state$files)
    state$files[state$index]
  })
  
  # Controls
  observeEvent(input$correct, { save_outcome(1)() })
  observeEvent(input$incorrect, { save_outcome(0)() })
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
    data.frame(`Target Probability` = p_vals, `Score Threshold` = round(thresholds, 3))
  })
  
  output$prPlot <- renderPlot({
    val <- state$data
    if (nrow(val) < 10) return(NULL)
    pr <- roc(val$outcome, val$score, quiet = TRUE)
    pr_data <- data.frame(thresholds = pr$thresholds,
                          sensitivities = pr$sensitivities,
                          specificities = pr$specificities)
    ggplot(pr_data, aes(x = 1 - specificities, y = sensitivities)) +
      geom_line(color = "darkred") +
      labs(title = "ROC Curve", x = "False Positive Rate", y = "True Positive Rate") +
      theme_minimal()
  })
  
  # Save on exit
  onStop(function() {
    if (!is.null(input$validation_file)) {
      write.csv(state$data, input$validation_file, row.names = FALSE)
    }
  })
}

# ==== LAUNCH ====
shinyApp(ui, server)
