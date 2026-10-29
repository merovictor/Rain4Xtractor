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
# Date: '2024-10-12' (v1.1: '2026-10-29')
# Version: '1.1'
# Project: 'Rainfall Data Extractor and Profile Generator using CHIRPS'
# Description: 'This Shiny app allows users to extract rainfall data using CHIRPS, generate a 365-day rainfall profile
#               (cyclic GAM, GAM or Fourier fit) and turn it into a carrying-capacity file for MGDrivE.'
#####################

# Fit a 365-day rainfall profile by day of year.
#   "cyclic"  : cyclic GAM, so 31 December joins smoothly onto 1 January (recommended)
#   "gam"     : the v1.0 fit, not cyclic, so the two ends of the year can jump
#   "fourier" : sum of sine/cosine harmonics, the same kind of fit as the umbrella package
fit_profile <- function(day_of_year, rainfall, method = "cyclic", k = 30, harmonics = 3) {
  fit_data <- data.frame(day_of_year = day_of_year, rainfall = rainfall)
  new_days <- data.frame(day_of_year = 1:365)
  if (method == "cyclic") {
    # knots at 0.5 and 365.5 make day 365 and day 1 neighbours (period of 365 days)
    gam_model <- gam(rainfall ~ s(day_of_year, bs = "cc", k = k), data = fit_data,
                     knots = list(day_of_year = c(0.5, 365.5)))
    profile <- predict(gam_model, newdata = new_days)
  } else if (method == "gam") {
    gam_model <- gam(rainfall ~ s(day_of_year, k = k), data = fit_data)
    profile <- predict(gam_model, newdata = new_days)
  } else {
    harmonic_terms <- function(t) {
      do.call(cbind, lapply(1:harmonics, function(h) cbind(sin(2 * pi * h * t / 365), cos(2 * pi * h * t / 365))))
    }
    fourier_model <- lm(fit_data$rainfall ~ harmonic_terms(fit_data$day_of_year))
    profile <- cbind(1, harmonic_terms(new_days$day_of_year)) %*% coef(fourier_model)
  }
  as.numeric(profile)
}

# Larval carrying capacity from a 365-day rainfall profile: White et al. (2011) method 3
# (exponentially weighted past rainfall). The year is treated as a circle, so day 1 uses the
# rainfall of the end of the previous year and every cycle is exactly 365 days. (Starting the
# sum at day tau instead gives 362-day cycles, which drift 3 days per model year.)
k_from_profile <- function(rain, tau = 4, L_eq = 120000, constant_frac = 0.05) {
  stopifnot(length(rain) == 365, all(is.finite(rain)))
  n <- length(rain)
  weights <- exp(-(0:(n - 1)) / tau) # weight for rainfall j days back
  k <- vapply(seq_len(n), function(d) {
    past_days <- ((d - 1 - 0:(n - 1)) %% n) + 1 # circular look-back
    sum(rain[past_days] * weights)
  }, numeric(1)) / sum(weights)
  k / max(k) * L_eq * (1 - constant_frac) + L_eq * constant_frac
}

# Repeat the 365-day cycle to cover a run of `years` plus one spare year, so the
# simulation never runs past the end of the file (stepfun would hold the last value).
tile_k <- function(k365, years) {
  tmax <- 365 * years
  K <- rep(k365, ceiling(tmax / 365) + 1)
  stopifnot(length(K) >= tmax + 1, length(K) %% 365 == 0)
  data.frame(Day = seq_along(K), K = K)
}

# Define UI for the Shiny app
ui <- fluidPage(
  # Include custom CSS
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1")
  ),

  # App Header
  div(
    class = "app-header",
    h1(class = "app-title", "Rain4Xtractor"),
    p(class = "app-subtitle", "CHIRPS Rainfall Data Extraction & GAM Profile Generation")
  ),

  # Tab Navigation
  tabsetPanel(
    id = "mainTabs",
    type = "tabs",

    # Documentation Tab
    tabPanel(
      "Documentation",
      div(
        class = "doc-panel",
        h2(class = "doc-title", "Overview"),
        p(
          class = "doc-intro",
          "Extract high-resolution CHIRPS rainfall data for any global location and generate
           smoothed temporal profiles using Generalized Additive Models (GAM)."
        ),
        div(
          class = "doc-section",
          h3(
            class = "doc-section-title",
            span(class = "badge", "1"),
            "Data Extraction"
          ),
          tags$ul(
            class = "doc-list",
            tags$li(tags$strong("Location:"), " Click the map to set coordinates"),
            tags$li(tags$strong("Date Range:"), " Define the temporal extent"),
            tags$li(tags$strong("Fetch:"), " Retrieve daily precipitation from CHIRPS servers"),
            tags$li(tags$strong("Export:"), " Download raw data as CSV")
          )
        ),
        div(
          class = "doc-section",
          h3(
            class = "doc-section-title",
            span(class = "badge", "2"),
            "Profile Generation"
          ),
          tags$ul(
            class = "doc-list",
            tags$li(tags$strong("Fit Method:"), " Cyclic GAM (recommended) joins 31 December to 1 January; GAM is the v1.0 fit and can jump at New Year; Fourier is a harmonic fit like the umbrella package"),
            tags$li(tags$strong("Average Years:"), " With several years fetched, rainfall is averaged by day of year before fitting"),
            tags$li(tags$strong("Spline Complexity (k):"), " Basis dimension controlling smoothness. Higher values capture finer temporal variation"),
            tags$li(tags$strong("Harmonics:"), " Number of sine/cosine pairs in the Fourier fit (umbrella uses 3)"),
            tags$li(tags$strong("Scaling Factor:"), " Multiplicative adjustment to predicted values"),
            tags$li(tags$strong("Output:"), " A 365-day profile by day of year, with the year-end jump reported as a check")
          )
        ),
        div(
          class = "doc-section",
          h3(
            class = "doc-section-title",
            span(class = "badge", "3"),
            "Carrying Capacity"
          ),
          tags$ul(
            class = "doc-list",
            tags$li(tags$strong("Method:"), " White et al. (2011) method 3, exponentially weighted past rainfall (tau days)"),
            tags$li(tags$strong("365-day cycles:"), " The year is treated as a circle, so every cycle is exactly 365 days and the season does not drift"),
            tags$li(tags$strong("Run Length:"), " The file covers the run plus one spare year, so the simulation never runs past its end"),
            tags$li(tags$strong("Export:"), " Day, K columns, ready for MGDrivE")
          )
        ),
        div(
          class = "app-footer",
          HTML(paste0("© ", format(Sys.Date(), "%Y"), " Victor Mero · Rain4Xtractor v1.1"))
        )
      )
    ),

    # Data Extraction Tab
    tabPanel(
      "Data Extraction",
      fluidRow(
        column(
          width = 3,
          wellPanel(
            div(class = "section-header", "Location & Period"),
            dateInput("startDate", "Start Date", value = "2021-01-01"),
            dateInput("endDate", "End Date", value = "2021-12-31"),
            actionButton("getData", "Fetch Data", class = "btn-block mt-md"),
            hr(),
            div(class = "section-header", "Visualization"),
            radioButtons("viewOption", NULL,
              choices = c("Table", "Line Chart", "Bar Chart"),
              selected = "Table"
            ),
            downloadButton("downloadData", "Download CSV"),
            verbatimTextOutput("statusOutput")
          )
        ),
        column(
          width = 9,
          leafletOutput("map", height = 420) %>% withSpinner(color = "#4a6785"),
          br(),
          conditionalPanel(
            condition = "input.viewOption == 'Table'",
            DTOutput("rainfallTable") %>% withSpinner(color = "#4a6785")
          ),
          conditionalPanel(
            condition = "input.viewOption == 'Line Chart'",
            plotOutput("rainfallPlotLine") %>% withSpinner(color = "#4a6785")
          ),
          conditionalPanel(
            condition = "input.viewOption == 'Bar Chart'",
            plotOutput("rainfallPlotBar") %>% withSpinner(color = "#4a6785")
          )
        )
      )
    ),

    # Profile Generator Tab
    tabPanel(
      "Profile Generator",
      fluidRow(
        column(
          width = 3,
          wellPanel(
            div(class = "section-header", "Model Parameters"),
            radioButtons("fitMethod", "Fit Method",
              choices = c(
                "Cyclic GAM (recommended)" = "cyclic",
                "GAM, not cyclic (v1.0)" = "gam",
                "Fourier (umbrella-style)" = "fourier"
              ),
              selected = "cyclic"
            ),
            checkboxInput("averageYears", "Average years by day of year before fitting", value = TRUE),
            conditionalPanel(
              condition = "input.fitMethod != 'fourier'",
              sliderInput("splineK", "Spline Complexity (k)",
                min = 5, max = 50, value = 30, step = 1
              ),
              p(class = "helper-text", "Basis dimension for the GAM smooth term. Higher k permits more complex seasonal patterns.")
            ),
            conditionalPanel(
              condition = "input.fitMethod == 'fourier'",
              sliderInput("harmonics", "Harmonics",
                min = 1, max = 6, value = 3, step = 1
              ),
              p(class = "helper-text", "Sine/cosine pairs in the Fourier fit. 3 matches the umbrella package.")
            ),
            sliderInput("scalingFactor", "Scaling Factor",
              min = 0.5, max = 2, value = 1, step = 0.1
            ),
            p(class = "helper-text", "Multiplier applied to predicted values for calibration."),
            hr(),
            actionButton("generateProfile", "Generate Profile", class = "btn-block"),
            div(class = "mt-md"),
            downloadButton("downloadProfile", "Download Profile CSV"),
            verbatimTextOutput("profileStatusOutput")
          )
        ),
        column(
          width = 9,
          plotOutput("rainfallProfilePlot") %>% withSpinner(color = "#4a6785"),
          br(),
          DTOutput("rainfallProfileTable") %>% withSpinner(color = "#4a6785")
        )
      )
    ),

    # Carrying Capacity Tab
    tabPanel(
      "Carrying Capacity",
      fluidRow(
        column(
          width = 3,
          wellPanel(
            div(class = "section-header", "K Parameters"),
            numericInput("kTau", "Rainfall memory, tau (days)", value = 4, min = 1, max = 60, step = 1),
            numericInput("kMax", "Maximum K, L_eq", value = 120000, min = 1, step = 1000),
            numericInput("kConstant", "Constant fraction of K", value = 0.05, min = 0, max = 1, step = 0.01),
            numericInput("kYears", "Simulation length (years)", value = 150, min = 1, max = 500, step = 1),
            p(class = "helper-text", "Uses the profile from the Profile Generator tab. The file covers the run plus one spare year."),
            hr(),
            actionButton("buildK", "Build K File", class = "btn-block"),
            div(class = "mt-md"),
            downloadButton("downloadK", "Download K CSV"),
            verbatimTextOutput("kStatusOutput")
          )
        ),
        column(
          width = 9,
          plotOutput("kPlot") %>% withSpinner(color = "#4a6785")
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
      geom_line(color = "#4a6785", linewidth = 0.8) +
      labs(title = "Rainfall Over Time", x = "Date", y = "Precipitation (mm)") +
      theme_minimal()
  })

  # Render bar plot of rainfall data
  output$rainfallPlotBar <- renderPlot({
    data <- rainfall_data()
    req(data)

    ggplot(data, aes(x = as.Date(date), y = rainfall)) +
      geom_bar(stat = "identity", fill = "#4a6785", alpha = 0.85) +
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

  # Generate a 365-day rainfall profile (one value per day of year)
  rainfall_profile <- eventReactive(input$generateProfile, {
    data <- rainfall_data()
    req(data)

    data <- data %>%
      mutate(day_of_year = yday(date)) %>%
      filter(day_of_year < 366) # Remove leap day if present

    # Observed mean rainfall by day of year (the climatology when several years are fetched)
    observed <- data %>%
      group_by(day_of_year) %>%
      summarise(observed_mean = mean(rainfall), .groups = "drop")
    n_years <- length(unique(year(data$date)))

    # Fit to the day-of-year means, or to every daily value
    fit_data <- if (input$averageYears) rename(observed, rainfall = observed_mean) else data
    profile <- fit_profile(fit_data$day_of_year, fit_data$rainfall,
      method = input$fitMethod, k = input$splineK, harmonics = input$harmonics
    )

    # Apply a global scaling factor to adjust the magnitude of the predicted profile
    profile_df <- data.frame(
      day_of_year = 1:365,
      rainfall_profile = pmax(profile * input$scalingFactor, 0) # Apply scaling and ensure non-negative values
    ) %>%
      left_join(observed, by = "day_of_year")

    # Check: a profile used for every model year must join up at New Year
    year_end_jump <- abs(profile_df$rainfall_profile[365] - profile_df$rainfall_profile[1]) /
      mean(profile_df$rainfall_profile)
    output$profileStatusOutput <- renderText(paste0(
      "Fitted ", input$fitMethod, " profile to ", n_years, " year(s).\n",
      "Year-end jump (31 Dec to 1 Jan): ", round(100 * year_end_jump), "% of the mean",
      if (year_end_jump > 0.1) "\nWarning: large jump at New Year. Use the cyclic GAM or Fourier fit." else ""
    ))

    return(list(profile = profile_df, n_years = n_years))
  })

  # Plot the rainfall profile against the observed day-of-year mean
  output$rainfallProfilePlot <- renderPlot({
    profile_data <- rainfall_profile()
    req(profile_data)

    ggplot(profile_data$profile, aes(x = day_of_year)) +
      geom_line(aes(y = observed_mean), color = "#4a6785", linewidth = 0.9, alpha = 0.8) +
      geom_line(aes(y = rainfall_profile), color = "#c44536", linewidth = 1, linetype = "dashed") +
      labs(
        title = "Observed Rainfall vs. Fitted 365-Day Profile",
        subtitle = paste0("Observed: mean by day of year over ", profile_data$n_years, " year(s)"),
        x = "Day of year",
        y = "Rainfall (mm)"
      ) +
      theme_minimal()
  })

  # Display rainfall profile in a table
  output$rainfallProfileTable <- renderDT({
    profile_data <- rainfall_profile()
    req(profile_data)
    datatable(profile_data$profile, options = list(pageLength = 10, autoWidth = TRUE))
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
        write.csv(profile_data$profile, file, row.names = FALSE)
      }
    }
  )

  # Build the carrying-capacity file from the profile
  carrying_capacity <- eventReactive(input$buildK, {
    profile_data <- rainfall_profile()
    req(profile_data)

    k365 <- k_from_profile(profile_data$profile$rainfall_profile,
      tau = input$kTau, L_eq = input$kMax, constant_frac = input$kConstant
    )
    k_df <- tile_k(k365, input$kYears)

    output$kStatusOutput <- renderText(paste0(
      nrow(k_df), " days = ", nrow(k_df) / 365, " cycles of 365 days\n",
      "Covers ", input$kYears, " years (", 365 * input$kYears, " days) plus one spare year"
    ))
    return(list(k365 = k365, k_df = k_df))
  })

  # Plot one 365-day cycle of K relative to its mean
  output$kPlot <- renderPlot({
    k_data <- carrying_capacity()
    req(k_data)

    ggplot(data.frame(day_of_year = 1:365, K = k_data$k365 / mean(k_data$k365)), aes(x = day_of_year, y = K)) +
      geom_line(color = "#4a6785", linewidth = 1) +
      labs(
        title = "Carrying Capacity Through the Year",
        subtitle = "One 365-day cycle, repeated for every model year",
        x = "Day of year",
        y = "K (x mean)"
      ) +
      theme_minimal()
  })

  # Allow users to download the carrying-capacity file as CSV
  output$downloadK <- downloadHandler(
    filename = function() {
      paste("carrying_capacity_", input$kYears, "y_365.csv", sep = "")
    },
    content = function(file) {
      k_data <- carrying_capacity()
      if (is.null(k_data)) {
        showModal(modalDialog("No carrying-capacity data available to download.", easyClose = TRUE))
      } else {
        write.csv(k_data$k_df, file, row.names = FALSE)
      }
    }
  )
}

# Run the app
shinyApp(ui = ui, server = server)
