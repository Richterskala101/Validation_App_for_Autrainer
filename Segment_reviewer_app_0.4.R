library(shiny)
library(shinyFiles)
library(tuneR)
library(seewave)
library(dplyr)
library(ggplot2)

# ==== UI ====
ui <- fluidPage(
  titlePanel("Segment Reviewer for Audio Classification"),
  
  tabsetPanel(
    id = "main_tabs",
    
    tabPanel("1. Setup",
             sidebarLayout(
               sidebarPanel(
                 shinyDirButton("segment_dir_btn", "Choose Segment Directory", "Select segment folder"),
                 verbatimTextOutput("segment_dir_display"),
                 
                 shinyDirButton("save_dir_btn", "Choose Save Directory", "Select where to save results"),
                 verbatimTextOutput("save_dir_display"),
                 
                 textInput("validation_file", "Validation File Name", value = "validation_results.csv"),
                 verbatimTextOutput("final_save_path"),
                 br(),
                 actionButton("proceed", "Go to Review Page", class = "btn-primary")
               ),
               mainPanel(
                 helpText("Step 1: Choose the folder containing the audio segments.",
                          "Then choose where the results should be saved and set a filename.")
               )
             )
    ),
    
    tabPanel("2. Review",
             sidebarLayout(
               sidebarPanel(
                 actionButton("load_data", "Load Segment Classes"),
                 uiOutput("class_ui"),
                 numericInput("segment_duration", "Segment Duration (seconds)", value = 5, min = 1),
                 actionButton("correct", "Correct", class = "btn-success"),
                 actionButton("incorrect", "Incorrect", class = "btn-danger"),
                 actionButton("skip", "Skip"),
                 actionButton("prev", "Previous"),
                 br(), br(),
                 verbatimTextOutput("clip_info"),
                 uiOutput("audio_ui"),
                 br(), br(),
                 
                 # === Spectrogram settings ===
                 hr(),
                 h4("Spectrogram Settings"),
                 numericInput("spec_fmin", "Min Frequency (kHz)", value = 0),
                 numericInput("spec_fmax", "Max Frequency (kHz)", value = 10),
                 numericInput("spec_wl", "Window Length (samples)", value = 512),
                 checkboxInput("spec_dB_toggle", "Apply dB scale (max0)?", value = TRUE),
                 selectInput("spec_palette", "Color Palette",
                             choices = c("gray.colors", "heat.colors", "topo.colors", "cm.colors", "terrain.colors"),
                             selected = "gray.colors"),
                 
                 helpText("This app allows you to manually validate predicted segments from an audio classification model.",
                          "After enough annotations, a logistic regression is fitted to calibrate model scores into probabilities.",
                          "Thresholds are calculated for precision levels 0.7, 0.8, and 0.9."),
                 
                 plotOutput("logisticPlot"),
                 tableOutput("thresholds")
               ),
               
               mainPanel(
                 plotOutput("spectrogram")
               )
             )
    )
  )
)

# ==== SERVER ====
server <- function(input, output, session) {
  volumes <- c(Home = fs::path_home(), "B:" = "B:/", "C:" = "C:/", "D:" = "D:/")
  shinyDirChoose(input, "segment_dir_btn", roots = volumes, session = session)
  shinyDirChoose(input, "save_dir_btn", roots = volumes, session = session)
  
  segment_dir <- reactiveVal(NULL)
  save_dir <- reactiveVal(NULL)
  
  observeEvent(input$segment_dir_btn, {
    dir_path <- parseDirPath(volumes, input$segment_dir_btn)
    if (length(dir_path) > 0 && dir.exists(dir_path)) {
      segment_dir(normalizePath(dir_path))
    }
  })
  
  observeEvent(input$save_dir_btn, {
    dir_path <- parseDirPath(volumes, input$save_dir_btn)
    if (length(dir_path) > 0 && dir.exists(dir_path)) {
      save_dir(normalizePath(dir_path))
    }
  })
  
  output$segment_dir_display <- renderPrint({ segment_dir() })
  output$save_dir_display <- renderPrint({ save_dir() })
  
  save_path <- reactive({
    req(save_dir(), input$validation_file)
    file_name <- input$validation_file
    if (!grepl("\\.csv$", file_name, ignore.case = TRUE)) {
      file_name <- paste0(file_name, ".csv")
    }
    file.path(save_dir(), file_name)
  })
  
  output$final_save_path <- renderText({
    req(save_path())
    paste("Results will be saved to:", save_path())
  })
  
  observeEvent(input$proceed, {
    updateTabsetPanel(session, "main_tabs", selected = "2. Review")
  })
  
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
  
  observeEvent(input$class, {
    req(segment_dir())
    
    class_name <- input$class
    class_path <- file.path(segment_dir(), class_name)
    www_class_path <- file.path("www", "segments", class_name)
    
    if (!dir.exists(www_class_path)) {
      dir.create(www_class_path, recursive = TRUE)
    }
    
    files <- list.files(class_path, pattern = "\\.wav$", full.names = TRUE)
    
    for (f in files) {
      dest <- file.path(www_class_path, basename(f))
      if (!file.exists(dest)) {
        file.copy(f, dest)
      }
    }
    
    state$files <- file.path("www", "segments", class_name, basename(files))
    state$index <- 1
  })
  
  current_file <- reactive({
    req(state$files)
    state$files[state$index]
  })
  
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
      
      if (!is.null(save_path())) {
        write.csv(state$data, save_path(), row.names = FALSE)
      }
      
      advance()
    }
  }
  
  advance <- function() {
    if (state$index < length(state$files)) {
      state$index <- state$index + 1
    } else {
      showNotification("You have reached the last clip.", type = "message")
    }
  }
  
  output$clip_info <- renderPrint({
    paste("Clip:", basename(current_file()),
          "[", state$index, "/", length(state$files), "]")
  })
  
  output$audio_ui <- renderUI({
    req(current_file())
    rel_path <- sub("^www/", "", current_file())
    tags$audio(id = "audio", src = rel_path, type = "audio/wav", controls = NA)
  })
  
  output$spectrogram <- renderPlot({
    req(current_file())
    wav <- readWave(current_file())
    
    flim <- c(input$spec_fmin, input$spec_fmax)
    wl <- input$spec_wl
    dB_opt <- if (input$spec_dB_toggle) "max0" else NULL
    pal_fun <- match.fun(input$spec_palette)
    
    spectro(wav,
            flim = flim,
            wl = wl,
            dB = dB_opt,
            palette = pal_fun,
            main = basename(current_file()))
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
  
  onStop(function() {
    if (!is.null(save_path())) {
      write.csv(state$data, save_path(), row.names = FALSE)
    }
  })
}

# ==== LAUNCH ====
shinyApp(ui, server)
