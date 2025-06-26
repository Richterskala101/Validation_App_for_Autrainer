library(shiny)
library(tuneR)
library(seewave)
library(dplyr)

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
      tags$audio(id = "audio", src = "", type = "audio/wav", controls = NA)
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
  
  observe({
    updateAudio(session, "audio", current_file())
  })
  
  onStop(function() {
    write.csv(state$data, validation_file, row.names = FALSE)
  })
}

shinyApp(ui, server)
