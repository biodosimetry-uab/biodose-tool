#' Fitting Counts Hottables Server Module
#'
#' @param input,output,session Internal parameters for {shiny}.
#' @param stringsAsFactors stringsAsFactors.
#' @param aberr_module Aberration module.
#'
#' @import shiny rhandsontable
#' @importFrom rlang .data
#' @noRd
mod_fitting_counts_hot_server <- function(input, output, session, stringsAsFactors, aberr_module) {

  # Reset table ----
  table_reset <- reactiveValues(value = 0)

  observeEvent(input$button_upd_table, {
    table_reset$value <- 1
  })

  # Initialize data frame ----
  previous <- reactive({

    # Create button dependency for updating dimensions
    input$button_upd_table

    isolate({
      load_count_data <- input$load_count_data_check
      use_aggr_count_data <- input$use_aggr_count_data_check
      count_data <- input$load_count_data
      num_doses <- as.numeric(input$num_doses)
      num_aberrs <- as.numeric(input$num_aberrs) + 1
    })

    if (!load_count_data) {
      if (!use_aggr_count_data) {
        # Doses data frame
        data_doses <- data.frame(
          D = rep(0.0, num_doses)
        )

        # Base data frame
        data_base <- data.frame(
          matrix(
            0,
            nrow = num_doses,
            ncol = num_aberrs
          )
        ) %>%
          `colnames<-`(paste0("C", seq(0, num_aberrs - 1, 1)))

        # Full data frame
        full_data <- cbind(data_doses, data_base) %>%
          dplyr::mutate(
            D = as.numeric(.data$D)
          )
      } else {
        full_data <- data.frame(
          D = rep(0.0, num_doses),
          N = rep(0, num_doses),
          X = rep(0, num_doses)
        ) %>%
          dplyr::mutate(
            D = as.numeric(.data$D),
            N = as.integer(.data$N),
            X = as.integer(.data$X)
          )
      }
    } else {
      if (!use_aggr_count_data) {
        full_data <- utils::read.csv(count_data$datapath, header = TRUE) %>%
          # Force column naming
          `colnames<-`(c("D", paste0("C", seq(0, ncol(.) - 2, 1)))) %>%
          dplyr::mutate_at(
            dplyr::vars(dplyr::starts_with("C")),
            as.integer
          ) %>%
          dplyr::mutate(
            D = as.numeric(.data$D)
          )
      } else {
        full_data <- utils::read.csv(count_data$datapath, header = TRUE) %>%
          # Force column naming
          `colnames<-`(c("D", "N", "X")) %>%
          dplyr::mutate_at(
            c("N", "X"),
            as.integer
          )
      }
    }

    return(full_data)
  })

  # Reactive data frame ----
  changed_data <- reactive({
    # Create button dependency for updating dimensions
    input$button_upd_table

    isolate({
      use_aggr_count_data <- input$use_aggr_count_data_check
    })

    # Create button dependency for updating N, X, DI, u values
    if (!use_aggr_count_data) {
      input$button_upd_params
    }

    isolate({
      if (is.null(input$count_data_hot) | isolate(table_reset$value == 1)) {
        table_reset$value <- 0
        mytable <- previous()

        # Initial renderization of the table
        if (!use_aggr_count_data) {
          # Calculated columns
          mytable <- mytable %>%
            dplyr::mutate(
              N = 0,
              X = 0,
              mean = 0,
              var = 0,
              DI = 0,
              u = 0
            ) %>%
            dplyr::select(.data$D, .data$N, .data$X, dplyr::everything()) %>%
            dplyr::mutate(
              D = as.numeric(.data$D)
            ) %>%
            dplyr::mutate_at(
              c("X", "N", grep("C", names(.), value = TRUE)),
              as.integer
            )
        }
        return(mytable)
      } else if (!identical(previous(), input$count_data_hot)) {
        mytable <- as.data.frame(hot_to_r(input$count_data_hot))

        if (!use_aggr_count_data) {
          # Expected u-value for assessment
          assessment_u <- 1.00

          if (aberr_module == "micronuclei") {
            assessment_u <- 1.17
          }


          # Calculated columns
          mytable <- mytable %>%
            dplyr::mutate(
              N = as.integer(rowSums(.[grep("C", names(.))])),
              X = calculate_aberr_power(mytable, power = 1),
              X2 = calculate_aberr_power(mytable, power = 2),
              mean = calculate_aberr_mean(.data$X, .data$N),
              var = calculate_aberr_var(.data$X, .data$X2, .data$N),
              DI = calculate_aberr_disp_index(.data$mean, .data$var),
              u = calculate_aberr_u_value(.data$X, .data$N, .data$mean, .data$var, assessment_u)
            ) %>%
            dplyr::mutate_at(
              c("X", "N", grep("C", names(.), value = TRUE)),
              as.integer
            ) %>%
            dplyr::select(-.data$X2) %>%
            dplyr::select(.data$D, .data$N, .data$X, dplyr::everything())
        } else {
          mytable <- mytable %>%
            dplyr::mutate(
              D = as.numeric(.data$D)
            )
        }

        return(mytable)
      }
    })
  })

  # Output ----
  output$count_data_hot <- renderRHandsontable({
    num_cols <- as.numeric(ncol(changed_data()))
    col_headers <- colnames(changed_data())
    col_headers[1] <- paste(col_headers[1], "(Gy)")

    hot <- changed_data() %>%
      rhandsontable(
        width = (70 + num_cols * 50),
        height = "100%",
        colHeaders = col_headers
      ) %>%
      hot_cols(colWidths = 50) %>%
      hot_col(c(1), format = "0.000", colWidths = 60) %>%
      hot_col(c(2), colWidths = 60) %>%
      hot_table(highlightCol = TRUE, highlightRow = TRUE)

    if (num_cols > 3) {
      hot <- hot %>%
        hot_col(c(2, 3, seq(num_cols - 3, num_cols, 1)), readOnly = TRUE) %>%
        hot_col(num_cols, renderer = "
           function (instance, td, row, col, prop, value, cellProperties) {
             Handsontable.renderers.NumericRenderer.apply(this, arguments);
             if (value > 1.96) {
              td.style.background = 'pink';
             }
           }")
    }

    hot$x$contextMenu <- list(items = c("remove_row", "---------", "undo", "redo"))
    return(hot)
  })
}

#' Fitting Results Server Module
#'
#' @param input,output,session Internal parameters for {shiny}.
#' @param stringsAsFactors stringsAsFactors.
#' @param aberr_module Aberration module.
#' @param genome_fraction Genomic fraction used in translocations.
#'
#' @import shiny rhandsontable
#' @importFrom rlang .data
#' @noRd
mod_fitting_results_server <- function(input, output, session, stringsAsFactors, aberr_module, genome_fraction = NULL) {

  # Calculations ----

  # Reactive environment
  data <- reactive({
    input$button_fit

    isolate({
      count_data <- hot_to_r(input$count_data_hot)

      model_formula <- input$formula_select
      model_family <- input$family_select
      # decision_thresh_cells <- input$decision_thresh_cells
    })

    if (aberr_module == "translocations") {
      frequency_select <- input$frequency_select
      chromosome_table <- hot_to_r(input$chromosome_table)
      genome_fraction <- genome_fraction$genome_fraction()

      # Modify N for translocations using full genome frequency
      if (frequency_select == "full_gen_freq") {
        input$button_fit

        isolate({
          count_data <- count_data %>%
            dplyr::mutate(
              N = .data$N * genome_fraction
            )
        })
      }
    }

    # Calculations process
    input$button_fit

    isolate({
      # Calculate dose-effect fitting curve
      message("\nPerforming dose-effect fitting...")
      fit_results_list <- get_fit_results(
        count_data,
        model_formula,
        model_family,
        fit_link = "identity",
        aberr_module
      )

      # Name of the aberration to use in the y-axis
      aberr_name <- to_title(aberr_module)
      if (aberr_module == "translocations") {
        if(nchar(input$trans_name) > 0) {
          aberr_name <- input$trans_name
        }
      }

      # Get dose estimation curve
      message("\nPlotting fitting results...")
      gg_curve <- get_fit_dose_curve(
        fit_results_list,
        aberr_name
      )

      message("\nDone!")

      # Make list of results to return
      results_list <- fit_results_list
      results_list[["fit_raw_data"]] <- hot_to_r(input$count_data_hot)
      results_list[["gg_curve"]] <- gg_curve

      # Additional results if using translocations
      if (aberr_module == "translocations") {
        results_list[["genome_fraction"]] <- genome_fraction
        results_list[["chromosome_table"]] <- chromosome_table
        results_list[["frequency_select"]] <- frequency_select
        results_list[["trans_sex"]] <- input$trans_sex
      }

      # # Calculate decision thresholds
      # decision_thresh <- data.frame(
      #   N = decision_thresh_cells %>%
      #     strsplit(" ") %>%
      #     unlist() %>%
      #     as.numeric()
      # )
      #
      # decision_thresh <- decision_thresh %>%
      #   dplyr::rowwise() %>%
      #   dplyr::mutate(
      #     X95 = get_decision_threshold(fit_results_list, cells = N, conf_int = 0.95, aberr_module, input)[1],
      #     D95 = get_decision_threshold(fit_results_list, cells = N, conf_int = 0.95, aberr_module, input)[2] * 1000,
      #     X83 = get_decision_threshold(fit_results_list, cells = N, conf_int = 0.83, aberr_module, input)[1],
      #     D83 = get_decision_threshold(fit_results_list, cells = N, conf_int = 0.83, aberr_module, input)[2] * 1000
      #   ) %>%
      #   dplyr::mutate_at(
      #     c("N", grep("X", names(.), value = TRUE)),
      #     as.integer
      #   )
      #
      # results_list[["decision_thresh"]] <- decision_thresh

      return(results_list)
    })
  })

  # Results outputs ----
  output$fit_formula_tex <- renderUI({
    # Fitting formula
    if (input$button_fit <= 0) {
      return(NULL)
    }
    withMathJax(paste0("$$", data()[["fit_formula_tex"]], "$$"))
  })

  output$fit_model_summary <- renderUI({
    # Fitting formula
    if (input$button_fit <= 0) {
      return(NULL)
    }
    data()[["fit_model_summary"]]
  })

  output$fit_model_statistics <- renderRHandsontable({
    # Model-level statistics
    if (input$button_fit <= 0) {
      return(NULL)
    }
    num_cols <- as.numeric(ncol(data()[["fit_model_statistics"]]))

    data()[["fit_model_statistics"]] %>%
      # Convert to hot and format table
      rhandsontable(
        width = (num_cols * 70),
        height = "100%"
      ) %>%
      hot_cols(colWidths = 70)
  })

  output$fit_coeffs <- renderRHandsontable({
    # Coefficients 'fit_coeffs'
    if (input$button_fit <= 0) {
      return(NULL)
    }
    num_cols <- as.numeric(ncol(data()[["fit_coeffs"]]))

    data()[["fit_coeffs"]] %>%
      formatC(format = "e", digits = 3) %>%
      fix_coeff_names(type = "rows", output = "rhot") %>%
      # Convert to hot and format table
      rhandsontable(
        width = (50 + num_cols * 100),
        height = "100%"
      ) %>%
      hot_cols(colWidths = 100) %>%
      hot_cols(halign = "htRight")
  })

  output$fit_var_cov_mat <- renderRHandsontable({
    # Variance-covariance matrix 'var_cov_mat'
    if (input$button_fit <= 0) {
      return(NULL)
    }
    num_cols <- as.numeric(ncol(data()[["fit_var_cov_mat"]]))

    data()[["fit_var_cov_mat"]] %>%
      formatC(format = "e", digits = 3) %>%
      fix_coeff_names(type = "rows", output = "rhot") %>%
      fix_coeff_names(type = "cols", output = "rhot") %>%
      # Convert to hot and format table
      rhandsontable(
        width = (50 + num_cols * 100),
        height = "100%"
      ) %>%
      hot_cols(colWidths = 100) %>%
      hot_cols(halign = "htRight")
  })

  output$fit_cor_mat <- renderRHandsontable({
    # Correlation matrix 'cor_mat'
    if (input$button_fit <= 0) {
      return(NULL)
    }
    num_cols <- as.numeric(ncol(data()[["fit_cor_mat"]]))

    data()[["fit_cor_mat"]] %>%
      fix_coeff_names(type = "rows", output = "rhot") %>%
      fix_coeff_names(type = "cols", output = "rhot") %>%
      # Convert to hot and format table
      rhandsontable(
        width = (50 + num_cols * 100),
        height = "100%"
      ) %>%
      hot_cols(colWidths = 100) %>%
      hot_cols(format = "0.000")
  })

  # output$fit_decision_thresh <- renderRHandsontable({
  #   # Decision thresholds
  #   if (input$button_fit <= 0) return(NULL)
  #
  #   decision_thresh <- data()[["decision_thresh"]]
  #
  #   num_cols <- 5
  #   col_headers <- c("N", "X95", "D (mGy)", "X83", "D (mGy)")
  #
  #   decision_thresh %>%
  #     # Convert to hot and format table
  #     rhandsontable(
  #       width = (100 + num_cols * 50),
  #       height = "100%",
  #       colHeaders = col_headers
  #     ) %>%
  #     hot_col(c(1), readOnly = TRUE) %>%
  #     hot_col(c(3,5), format = "0.00", colWidths = 75) %>%
  #     hot_cols(colWidths = 50)
  # })

  output$plot <- renderPlot(
    # Plot of the data and fitted curve
    res = 120,
    {
      if (input$button_fit <= 0) {
        return(NULL)
      }
      data()[["gg_curve"]]
    }
  )

  # Export count data ----
  output$save_count_data <- downloadHandler(
    filename = function() {
      paste("count-data-", Sys.Date(), input$save_count_data_format, sep = "")
    },
    content = function(file) {
      if (input$save_count_data_format == ".csv") {
        utils::write.csv(hot_to_r(input$count_data_hot), file, row.names = FALSE)
      } else if (input$save_count_data_format == ".tex") {
        print(xtable::xtable(hot_to_r(input$count_data_hot)), type = "latex", file)
      }
    }
  )

  # Export fit coefficients ----
  output$save_fit_data <- downloadHandler(
    filename = function() {
      paste(aberr_module, "-fitting-data-", Sys.Date(), input$save_fit_data_format, sep = "")
    },
    content = function(file) {
      if (input$save_fit_data_format == ".rds") {
        results_list <- data()
        results_list[["gg_curve"]] <- NULL
        saveRDS(results_list, file = file)
      }
    }
  )

  # Export plot ----
  output$save_plot <- downloadHandler(
    filename = function() {
      paste(aberr_module, "-fitting-curve-", Sys.Date(), input$save_plot_format, sep = "")
    },
    content = function(file) {
      ggplot2::ggsave(
        plot = data()[["gg_curve"]], filename = file,
        width = 6, height = 4.5, dpi = 96,
        device = gsub("\\.", "", input$save_plot_format)
      )
    }
  )

  # Export report ----
  output$save_report <- downloadHandler(
    # For PDF output, change this to "report.pdf"
    filename = function() {
      paste0(aberr_module, "-fitting-report-", Sys.Date(), input$save_report_format)
    },
    content = function(file) {
      # Copy the report file to a temporary directory before processing it, in
      # case we don't have write permissions to the current working dir (which
      # can happen when deployed).
      temp_report <- file.path(tempdir(), paste0(aberr_module, "-report.Rmd"))
      local_report <- load_rmd_report(
        paste0(
          aberr_module,
          "-fitting-report-",
          gsub("^\\.", "", input$save_report_format),
          ".Rmd"
        )
      )

      file.copy(local_report, temp_report, overwrite = TRUE)

      # Set up parameters to pass to Rmd document
      params <- list(
        fit_results_list = data()
      )

      # Knit the document, passing in the `params` list, and eval it in a
      # child of the global environment (this isolates the code in the document
      # from the code in this app).
      rmarkdown::render(
        input = temp_report,
        output_file = file,
        params = params,
        envir = new.env(parent = globalenv())
      )
    }
  )
}
