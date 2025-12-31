library(shiny)
library(leaflet)
library(chirps)
library(dplyr)
library(ggplot2)
library(shinycssloaders)
library(DT)
library(mgcv)
library(lubridate)
####################
# Author: 'Victor Mero'
# Date: '2024-10-12'
# Version: '1.0'
# Project: 'Rainfall Data Extractor and Profile Generator using CHIRPS'
# Description: 'This Shiny app allows users to extract rainfall data using CHIRPS and generate a rainfall profile using a GAM model.'
#####################
# Define UI for the Shiny app
ui <- fluidPage(
  titlePanel("Rainfall Data Extractor and Profile Generator using CHIRPS"),
  tabsetPanel(
    tabPanel(
      "How to Use",
      column(
        width = 10, offset = 1,
        br(),
        h2("Welcome to Rain4Xtractor"),
        p("This application allows you to extract high-resolution CHIRPS rainfall data and generate predictive profiles using GAM modeling."),
        hr(),
        h3("1. Rainfall Data Extraction"),
        tags$ul(
          tags$li(strong("Select Location:"), " Click anywhere on the map in the 'Rainfall Data Extraction' tab to set the coordinates."),
          tags$li(strong("Set Date Range:"), " Select your desired Start and End dates in the sidebar."),
          tags$li(strong("Get Data:"), " Click the 'Get Rainfall Data' button. The app will fetch data from CHIRPS servers."),
          tags$li(strong("View & Download:"), " Switch between Table, Line Chart, and Bar Chart. Use 'Download CSV' to save the raw data.")
        ),
        h3("2. Rainfall Profile Generator"),
        tags$ul(
          tags$li(strong("Prerequisite:"), " You must fetch extraction data first."),
          tags$li(strong("Adjust Spline (k):"), " Control the smoothness of the profile. Higher 'k' captures more local variation."),
          tags$li(strong("Scaling Factor:"), " Adjust the magnitude of the predicted rainfall profile."),
          tags$li(strong("Generate Profile:"), " Click 'Generate Rainfall Profile' to fit the GAM model and see predicted values (red dashed line)."),
          tags$li(strong("Download Profile:"), " Export the predicted values as a CSV for external use.")
        ),
        br(),
        hr(),
        p(em("Developed by Victor Mero. Version 1.0"))
      )
    ),
    tabPanel(
      "Rainfall Data Extraction",
      fluidRow(
        column(
          width = 3,
          wellPanel(
            dateInput("startDate", "Start Date", value = "2021-01-01"),
            dateInput("endDate", "End Date", value = "2021-12-31"),
            actionButton("getData", "Get Rainfall Data"),
            br(),
            radioButtons("viewOption", "View Data as:", choices = c("Table", "Line Chart", "Bar Chart"), selected = "Table"),
            downloadButton("downloadData", "Download CSV"),
            br(),
            verbatimTextOutput("statusOutput") # For status and debugging
          )
        ),
        column(
          width = 9,
          leafletOutput("map", height = 400) %>% withSpinner(color = "#0dc5c1"),
          br(),
          conditionalPanel(
            condition = "input.viewOption == 'Table'",
            DTOutput("rainfallTable") %>% withSpinner(color = "#0dc5c1")
          ),
          conditionalPanel(
            condition = "input.viewOption == 'Line Chart'",
            plotOutput("rainfallPlotLine") %>% withSpinner(color = "#0dc5c1")
          ),
          conditionalPanel(
            condition = "input.viewOption == 'Bar Chart'",
            plotOutput("rainfallPlotBar") %>% withSpinner(color = "#0dc5c1")
          )
        )
      )
    ),
    tabPanel(
      "Rainfall Profile Generator",
      fluidRow(
        column(
          width = 3,
          wellPanel(
            sliderInput("splineK", "Spline Complexity (k):", min = 5, max = 50, value = 30, step = 1),
            sliderInput("scalingFactor", "Scaling Factor Adjustment:", min = 0.5, max = 2, value = 1, step = 0.1),
            actionButton("generateProfile", "Generate Rainfall Profile"),
            downloadButton("downloadProfile", "Download Profile CSV"),
            br(),
            verbatimTextOutput("profileStatusOutput")
          )
        ),
        column(
          width = 9,
          plotOutput("rainfallProfilePlot") %>% withSpinner(color = "#0dc5c1"),
          DTOutput("rainfallProfileTable") %>% withSpinner(color = "#0dc5c1")
        )
      )
    )
  )
)

# Define server logic
server <- function(input, output, session) {
  # Reactive value to store the selected coordinates
  coords <- reactiveVal()

  # Create a leaflet map to select a location
  output$map <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      setView(lng = 32.9, lat = -2.5, zoom = 6) # Centering on Mwanza, Tanzania
  })

  # Observe map click and save the coordinates
  observeEvent(input$map_click, {
    click <- input$map_click
    coords(c(lng = click$lng, lat = click$lat))

    # Add a marker to show the selected location
    leafletProxy("map") %>%
      clearMarkers() %>%
      addMarkers(lng = click$lng, lat = click$lat)
  })

  # Reactive value for rainfall data
  rainfall_data <- eventReactive(input$getData, {
    req(coords())
    lng <- coords()[1]
    lat <- coords()[2]
    lonlat <- data.frame(lon = lng, lat = lat)

    # Inform the user about the status of data fetching
    output$statusOutput <- renderText("Fetching data... Please wait.")

    # Get CHIRPS data for the selected location and date range
    tryCatch(
      {
        rainfall <- get_chirps(
          object = lonlat,
          dates = c(
            as.character(input$startDate),
            as.character(input$endDate)
          ),
          server = "CHC"
        )

        if (is.null(rainfall) || nrow(rainfall) == 0) {
          output$statusOutput <- renderText("No data available for the selected date range.")
          return(NULL)
        }

        # Convert the data into a usable format
        rainfall_df <- as.data.frame(rainfall)
        rainfall_df$date <- as.Date(rainfall_df$date)

        # Rename 'chirps' column to 'rainfall' and clean data
        rainfall_df <- rainfall_df %>%
          rename(rainfall = chirps) %>%
          filter(!is.na(rainfall)) %>%
          mutate(id = row_number()) # Add serial number ID starting from 1

        # Reorder columns for better display
        rainfall_df <- rainfall_df %>%
          select(id, lon, lat, date, rainfall)

        output$statusOutput <- renderText("Data successfully fetched.")
        return(rainfall_df)
      },
      error = function(e) {
        output$statusOutput <- renderText(paste("Error fetching data:", e$message))
        return(NULL)
      }
    )
  })

  # Display rainfall data in an interactive table with pagination
  output$rainfallTable <- renderDT({
    data <- rainfall_data()
    req(data)
    datatable(data, options = list(pageLength = 10, autoWidth = TRUE))
  })

  # Render line plot of rainfall data
  output$rainfallPlotLine <- renderPlot({
    data <- rainfall_data()
    req(data)

    ggplot(data, aes(x = as.Date(date), y = rainfall)) +
      geom_line(color = "#0dc5c1") +
      labs(title = "Rainfall Over Time", x = "Date", y = "Precipitation (mm)") +
      theme_minimal()
  })

  # Render bar plot of rainfall data
  output$rainfallPlotBar <- renderPlot({
    data <- rainfall_data()
    req(data)

    ggplot(data, aes(x = as.Date(date), y = rainfall)) +
      geom_bar(stat = "identity", fill = "#0dc5c1") +
      labs(title = "Rainfall Over Time", x = "Date", y = "Precipitation (mm)") +
      theme_minimal()
  })

  # Allow users to download the data as CSV
  output$downloadData <- downloadHandler(
    filename = function() {
      paste("rainfall_data_", Sys.Date(), ".csv", sep = "")
    },
    content = function(file) {
      data <- rainfall_data()
      if (is.null(data)) {
        showModal(modalDialog("No data available to download.", easyClose = TRUE))
      } else {
        write.csv(data, file, row.names = FALSE)
      }
    }
  )

  # Generate rainfall profile using GAM model
  rainfall_profile <- eventReactive(input$generateProfile, {
    data <- rainfall_data()
    req(data)

    data <- data %>%
      mutate(
        day_of_year = yday(date),
        t = day_of_year / 365
      ) %>%
      filter(day_of_year < 366) # Remove leap day if present

    # Fit the GAM model with user-adjustable parameters
    gam_model <- gam(rainfall ~ s(day_of_year, k = input$splineK), data = data)

    # Predict using the GAM model
    data$gam_profile <- predict(gam_model, newdata = data)

    # Apply a global scaling factor to adjust the magnitude of the predicted profile
    scaling_factor <- input$scalingFactor
    data$gam_profile_scaled <- pmax(data$gam_profile * scaling_factor, 0) # Apply scaling and ensure non-negative values

    return(data)
  })

  # Plot the rainfall profile
  output$rainfallProfilePlot <- renderPlot({
    profile_data <- rainfall_profile()
    req(profile_data)

    ggplot(profile_data, aes(x = date)) +
      geom_line(aes(y = rainfall), color = "blue", size = 1, alpha = 0.7) +
      geom_line(aes(y = gam_profile_scaled), color = "red", size = 1, linetype = "dashed") +
      labs(
        title = "Observed Rainfall vs. Scaled GAM-Predicted Profile",
        x = "Date",
        y = "Rainfall (mm)"
      ) +
      theme_minimal()
  })

  # Display rainfall profile in a table
  output$rainfallProfileTable <- renderDT({
    profile_data <- rainfall_profile()
    req(profile_data)
    datatable(profile_data %>% select(date, rainfall, gam_profile_scaled), options = list(pageLength = 10, autoWidth = TRUE))
  })

  # Allow users to download the rainfall profile data as CSV
  output$downloadProfile <- downloadHandler(
    filename = function() {
      paste("rainfall_profile_", Sys.Date(), ".csv", sep = "")
    },
    content = function(file) {
      profile_data <- rainfall_profile()
      if (is.null(profile_data)) {
        showModal(modalDialog("No profile data available to download.", easyClose = TRUE))
      } else {
        write.csv(profile_data %>% select(date, rainfall, gam_profile_scaled), file, row.names = FALSE)
      }
    }
  )
}

# Run the app
shinyApp(ui = ui, server = server)
