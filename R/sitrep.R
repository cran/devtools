# Supress R CMD check note
#' @importFrom memoise memoise
NULL

check_for_rstudio_updates <- function(os = tolower(Sys.info()[["sysname"]]), version = rstudioapi::getVersion(), in_rstudio = rstudioapi::isAvailable()) {

  if (!in_rstudio) {
    return()
  }

  url <- sprintf("https://www.rstudio.org/links/check_for_update?version=%s&os=%s&format=kvp", version, os, "kvp")

  tmp <- tempfile()
  on.exit(unlink(tmp))
  utils::download.file(url, tmp, quiet = TRUE)
  result <- readLines(tmp, warn = FALSE)

  result <- strsplit(result, "&")[[1]]

  result <- strsplit(result, "=")

  # If no values then we are current
  if (length(result[[1]]) == 1) {
    return()
  }

  nms <- vcapply(result, `[[`, 1)
  values <- vcapply(result, function(x) utils::URLdecode(x[[2]]))

  result <- stats::setNames(values, nms)

  if (!nzchar(result[["update-version"]])) {
    return()
  }

  return(
    sprintf("%s.\nDownload at: %s",
      result[["update-message"]],
      ui_field(result[["update-url"]])
    )
  )
}

.r_release <- function() {
  R_system_version(rversions::r_release()$version)
}

r_release <- memoise::memoise(.r_release)

#' Report package development situation
#'
#' @template devtools
#' @inheritParams pkgbuild::has_build_tools
#' @description `dev_sitrep()` reports
#'   * If R is up to date
#'   * If RStudio is up to date
#'   * If compiler build tools are installed and available for use
#'   * If devtools and its dependencies are up to date
#'   * If the package's dependencies are up to date
#'
#' @description Call this function if things seem weird and you're not sure
#'   what's wrong or how to fix it. If this function returns no output
#'   everything should be ready for package development.
#'
#' @return A named list, with S3 class `dev_sitrep` (for printing purposes).
#' @importFrom usethis ui_code ui_field ui_todo ui_value ui_done ui_path
#' @export
#' @examples
#' \dontrun{
#' dev_sitrep()
#' }
dev_sitrep <- function(pkg = ".", debug = FALSE) {
  pkg <- tryCatch(as.package(pkg), error = function(e) NULL)

  has_build_tools <- !is_windows || pkgbuild::has_build_tools(debug = debug)

  structure(
    list(
      pkg = pkg,
      r_version = getRversion(),
      r_path = normalizePath(R.home()),
      r_release_version = r_release(),
      has_build_tools = has_build_tools,
      rtools_path = if (has_build_tools) pkgbuild::rtools_path(),
      devtools_version = packageVersion("devtools"),
      devtools_deps = remotes::package_deps("devtools", dependencies = NA),
      pkg_deps = if (!is.null(pkg)) { remotes::dev_package_deps(pkg$path, dependencies = TRUE) },
      rstudio_version = if (rstudioapi::isAvailable()) rstudioapi::getVersion(),
      rstudio_msg = check_for_rstudio_updates()
    ),
    class = "dev_sitrep"
  )
}

#' @export
print.dev_sitrep <- function(x, ...) {

  all_ok <- TRUE

  hd_line("R")
  kv_line("version", x$r_version)
  kv_line("path", x$r_path, path = TRUE)
  if (x$r_version < x$r_release_version) {
    ui_todo('
      {ui_field("R")} is out of date ({ui_value(x$r_version)} vs {ui_value(x$r_release_version)})
      ')
      all_ok <- FALSE
  }

  if (is_windows) {
    hd_line("Rtools")
    if (x$has_build_tools) {
      kv_line("path", x$rtools_path, path = TRUE)
    } else {
      ui_todo('
        {ui_field("RTools")} is not installed:
        Download and install it from: {ui_field("https://cloud.r-project.org/bin/windows/Rtools/")}
        ')
    }
    all_ok <- FALSE
  }

  if (!is.null(x$rstudio_version)) {
    hd_line("RStudio")
    kv_line("version", x$rstudio_version)

    if (!is.null(x$rstudio_msg)) {
      ui_todo(x$rstudio_msg)
      all_ok <- FALSE
    }
  }


  hd_line("devtools")
  kv_line("version", x$devtools_version)

  devtools_deps_old <- x$devtools_deps$diff < 0
  if (any(devtools_deps_old)) {
    ui_todo('
      {ui_field("devtools")} or its dependencies out of date:
      {paste(ui_value(x$devtools_deps$package[devtools_deps_old]), collapse = ", ")}
      Update them with {ui_code("devtools::update_packages(\\"devtools\\")")}
      ')
      all_ok <- FALSE
  }

  hd_line("dev package")
  kv_line("package", x$pkg$package)
  kv_line("path", x$pkg$path, path = TRUE)

  pkg_deps_old <- x$pkg_deps$diff < 0
  if (any(pkg_deps_old)) {
    ui_todo('
      {ui_field(x$pkg$package)} dependencies out of date:
      {paste(ui_value(x$pkg_deps$package[pkg_deps_old]), collapse = ", ")}
      Update them with {ui_code("devtools::install_dev_deps()")}
      ')
      all_ok <- FALSE
  }

  if (all_ok) {
    ui_done("
      All checks passed
      ")
  }

  invisible(x)
}
