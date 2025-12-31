# Rain4Xtractor

**Rain4Xtractor** is a simple R Shiny application designed to extract high-resolution rainfall data from the Climate Hazards Group InfraRed Precipitation with Station (CHIRPS) dataset and generate predictive rainfall profiles using Generalized Additive Models (GAM).

This tool is specifically useful for hydrologists, agricultural scientists, and climate researchers who need precise local rainfall data for analysis and modeling.

## 🚀 Features

-   **Interactive Map Selection:** Use an integrated Leaflet map to pinpoint any location for data extraction.
-   **CHIRPS Data Integration:** Fetch historical rainfall data directly from the CHC servers.
-   **Multiple Visualizations:** View extracted data as interactive tables, line charts, or bar charts.
-   **Rainfall Profile Generation:** Generate smooth rainfall profiles using GAM splines with adjustable complexity ($k$) and scaling factors.
-   **Data Export:** Download both raw extracted data and generated rainfall profiles as CSV files for further analysis.

## 🛠️ Prerequisites

To run this application locally, you will need **R** and the following R packages:

```r
install.packages(c("shiny", "leaflet", "chirps", "dplyr", "ggplot2", 
                   "shinycssloaders", "DT", "mgcv", "lubridate"))
```

## 📦 Installation & Usage

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/merovictor/Rain4Xtractor.git
    cd Rain4Xtractor
    ```

2.  **Open the project in RStudio:**
    Open the `Rain4Xtractor.Rproj` file.

3.  **Run the application:**
    Open `Rain4Xtractor.R` and click the **"Run App"** button in RStudio, or run:
    ```r
    shiny::runApp()
    ```

## 📖 How to Use

1.  **Extraction:** Navigate to the "Rainfall Data Extraction" tab, select a location on the map, set your date range, and click "Get Rainfall Data".
2.  **Visualization:** Switch between Table, Line Chart, and Bar Chart formats to inspect your data.
3.  **Profile Generation:** Navigate to the "Rainfall Profile Generator" tab. Adjust the spline complexity $(k)$ and scaling factor to fit your needs, then click "Generate Rainfall Profile".
4.  **Download:** Use the download buttons to save your results locally as `.csv` files.

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

## ✍️ Author

-   **Victor Mero** - *Developer* - [merovictor](https://github.com/merovictor)

---
*Developed with ❤️ for the open-source community.*
