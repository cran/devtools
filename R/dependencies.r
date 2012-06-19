#' Reverese dependency tools.
#'
#' Tools to check and notify maintainers of all all CRAN and bioconductor
#' packages that depend on the specified package.
#'
#' @param pkg package name
#' @inheritParams tools::dependsOnPkgs
#' @importFrom tools dependsOnPkgs
#' @export
#' @examples
#' revdep("ggplot2")
revdep <- function(pkg, dependencies = c("Depends", "Imports"), recursive = FALSE) {
  sort(dependsOnPkgs(pkg, dependencies, recursive, installed = packages()))
}

#' @rdname revdep
#' @export
revdep_maintainers <- function(pkg) {
  as.person(unique(packages()[revdep(pkg), "Maintainer"]))
}

#' @rdname revdep
#' @param ... Other parameters passed on to \code{\link{check_cran}}
#' @export
revdep_check <- function(pkg, ...) {
  pkgs <- revdep(pkg)
  check_cran(pkgs, ...)
}


#' @importFrom memoise memoise
cran_packages <- memoise(function() {
  local <- file.path(tempdir(), "packages.rds")
  download.file("http://cran.R-project.org/web/packages/packages.rds", local,
    mode = "wb", quiet = TRUE)
  on.exit(unlink(local))
  cp <- readRDS(local)
  rownames(cp) <- unname(cp[, 1])
  cp
})

#' @importFrom memoise memoise
bioc_packages <- memoise(function() {
  on.exit(closeAllConnections())
  bioc <- read.dcf(url("http://bioconductor.org/packages/release/bioc/VIEWS"))
  rownames(bioc) <- bioc[, 1]
  bioc
})

packages <- function() {
  cran <- cran_packages()
  bioc <- bioc_packages()
  cols <- intersect(colnames(cran), colnames(bioc))
  rbind(cran[, cols], bioc[, cols])
}

