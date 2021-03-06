#' Help modal trigger button
#'
#' @param inputId id of the button.
#' @param id_modal id of the modal dialogue.
#' @param container Outer container of the modal, either box or tabbox.
#'
#' @noRd
help_modal_button <- function(inputId, id_modal, container = "box") {
  shiny::actionButton(
    inputId,
    label = "",
    class = paste0("modal-help-button ", container, "-modal-help-button"),
    icon = icon("question")
  ) %>%
    bsplus::bs_attach_modal(id_modal)
}

#' Create an inner column within a UI definition
#'
#' @param width The grid width of the column (must be between 1 and 12).
#' @param ... Elements to include within the column.
#' @param offset The number of columns to offset this column from the end of the previous column.
#'
#' @noRd
inner_column <- function(width, ..., offset = 0) {
  if (!is.numeric(width)) { #|| (width < 1) || (width > 12)) {
    stop("column width must be between 1 and 12")
  }
  colClass <- paste0("col-inner-", width)
  if (offset > 0) {
    colClass <- paste0(colClass, " col-sm-offset-", offset)
  }
  div(class = colClass, ...)
}

#' Create a widget label.
#'
#' @param label Input label.
#' @param margin_bottom Bottom margin.
#' @param font_size Font size of label.
#'
#' @import shiny
#'
#' @noRd
widget_label <- function(label, margin_bottom = 0, font_size = 14) {
  div(
    style = paste0("margin-bottom: ", margin_bottom, "px; ", "font-size: ", font_size, "px;"),
    p(strong(label))
  )
}
