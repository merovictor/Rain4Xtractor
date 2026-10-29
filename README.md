# Rain4Xtractor

**Rain4Xtractor** is a simple R Shiny application designed to extract high-resolution rainfall data from the Climate Hazards Group InfraRed Precipitation with Station (CHIRPS) dataset and generate predictive rainfall profiles using Generalized Additive Models (GAM).

This tool is specifically useful for hydrologists, agricultural scientists, and climate researchers who need precise local rainfall data for analysis and modeling.

## 🚀 Features

-   **Interactive Map Selection:** Use an integrated Leaflet map to pinpoint any location for data extraction.
-   **CHIRPS Data Integration:** Fetch historical rainfall data directly from the CHC servers.
-   **Multiple Visualizations:** View extracted data as interactive tables, line charts, or bar charts.
-   **Rainfall Profile Generation:** Generate a smooth 365-day rainfall profile by day of year, with a cyclic GAM (default), the original GAM or a Fourier (umbrella-style) fit, adjustable complexity ($k$ or harmonics) and scaling factor.
-   **Multi-Year Averaging:** Fetch several years and average them by day of year before fitting.
-   **Year-End Check:** The app reports how much the profile jumps between 31 December and 1 January and warns when it is large.
-   **Carrying Capacity Export:** Turn the profile into a larval carrying-capacity file (White et al. 2011, method 3) in exact 365-day cycles that covers the whole simulation, ready for MGDrivE.
-   **Data Export:** Download raw extracted data, rainfall profiles and carrying-capacity files as CSV files for further analysis.

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
3.  **Profile Generation:** Navigate to the "Profile Generator" tab. Choose the fit method (cyclic GAM is recommended), whether to average years by day of year, and the spline complexity $(k)$ or harmonics and scaling factor, then click "Generate Profile". Check the year-end jump in the status box.
4.  **Carrying Capacity:** Navigate to the "Carrying Capacity" tab. Set tau (days of rainfall memory, default 4), the maximum K, the constant fraction and the simulation length in years, then click "Build K File".
5.  **Download:** Use the download buttons to save your results locally as `.csv` files.

## 🆕 What changed in v1.1

-   **Cyclic fit by default.** The v1.0 GAM was not cyclic, so the two ends of the year were fitted separately. At sites that are wet over New Year (for example Mwanza) the profile jumped by about 0.9 x the mean between 31 December and 1 January. The cyclic GAM joins the ends; the v1.0 fit is still available.
-   **365-day profile output.** The profile is now one value per day of year (`day_of_year`, `rainfall_profile`, `observed_mean`), whatever the date range, instead of one value per fetched date.
-   **Fourier option.** A sine/cosine fit of the same kind as the [umbrella](https://github.com/mrc-ide/umbrella) package. With 3 harmonics it matches umbrella's Mwanza 2012-2021 profile at r = 0.999.
-   **Carrying-capacity export.** Each cycle is exactly 365 days (the year is treated as a circle, so day 1 uses the rainfall at the end of the previous year), and the file covers the run plus one spare year. Starting the rainfall sum at day tau instead gives 362-day cycles: the season then drifts 3 days per model year and, once the file runs out, the simulation holds the last value.
<img width="1803" height="1189" alt="Screenshot 2025-12-31 at 1 07 11 PM" src="https://github.com/user-attachments/assets/41e12b70-df6a-405c-82f8-3a4b44478407" />
<img width="1804" height="1186" alt="Screenshot 2025-12-31 at 1 07 27 PM" src="https://github.com/user-attachments/assets/659055f8-77b2-43ac-83f5-edd1ba500c1f" />
<img width="1812" height="1190" alt="Screenshot 2025-12-31 at 1 07 40 PM" src="https://github.com/user-attachments/assets/da34a151-2159-441a-96dd-a1877dbdca03" />
<img width="1781" height="1174" alt="Screenshot 2025-12-31 at 1 09 40 PM" src="https://github.com/user-attachments/assets/068c40e4-80b8-471e-b4db-1ae92363d8dc" />

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

## ✍️ Author

-   **Victor Mero** - *Developer* - [merovictor](https://github.com/merovictor)

---
*Developed with ❤️ for the open-source community.*
