available_packages <- memoise::memoise(function(repos, type) {
  suppressWarnings(available.packages(contrib.url(repos, type), type = type))
})

package_url <- function(package, repos,
                        available = available_packages(repos, "source")) {
  ok <- (available[, "Package"] == package)
  ok <- ok & !is.na(ok)

  if (!any(ok)) {
    return(list(name = NA_character_, url = NA_character_))
  }

  vers <- package_version(available[ok, "Version"])
  keep <- vers == max(vers)
  keep[duplicated(keep)] <- FALSE
  ok[ok][!keep] <- FALSE

  name <- paste(package, "_", available[ok, "Version"], ".tar.gz", sep = "")
  url <- file.path(available[ok, "Repository"], name)

  list(name = name, url = url)
}


# Return the version of a package on CRAN (or other repository)
# @param package The name of the package.
# @param available A matrix of information about packages.
cran_pkg_version <- function(package, available = available.packages()) {

  idx <- available[, "Package"] == package
  if(any(idx)) {
    as.package_version(available[package, "Version"])
  } else {
    NULL
  }
}
