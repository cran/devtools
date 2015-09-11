#' Check a package from CRAN.
#'
#' Internal function used to power \code{\link{revdep_check}()}.
#'
#' This function does not clean up after itself, but does work in a
#' session-specific temporary directory, so all files will be removed
#' when your current R session ends.
#'
#' @param pkgs Vector of package names - note that unlike other \pkg{devtools}
#'   functions this is the name of a CRAN package, not a path.
#' @param libpath Path to library to store dependencies packages - if you
#'   you're doing this a lot it's a good idea to pick a directory and stick
#'   with it so you don't have to download all the packages every time.
#' @param srcpath Path to directory to store source versions of dependent
#'   packages - again, this saves a lot of time because you don't need to
#'   redownload the packages every time you run the package.
#' @param bioconductor Include bioconductor packages in checking?
#' @param type binary Package type to test (source, mac.binary etc). Defaults
#'   to the same type as \code{\link{install.packages}()}.
#' @param threads Number of concurrent threads to use for checking.
#'   It defaults to the option \code{"Ncpus"} or \code{1} if unset.
#' @param check_dir Directory to store results.
#' @param revdep_pkg Optional name of a package for which this check is
#'   checking the reverse dependencies of. This is normally passed in from
#'   \code{\link{revdep_check}}, and is used only for logging.
#' @return Returns (invisibly) the directory where check results are stored.
#' @keywords internal
#' @export
check_cran <- function(pkgs, libpath = file.path(tempdir(), "R-lib"),
                       srcpath = libpath, bioconductor = FALSE,
                       type = getOption("pkgType"),
                       threads = getOption("Ncpus", 1),
                       check_dir = tempfile("check_cran"),
                       revdep_pkg = NULL) {

  stopifnot(is.character(pkgs))
  if (length(pkgs) == 0) return()

  rule("Checking ", length(pkgs), " CRAN packages", pad = "=")
  if (!file.exists(check_dir)) dir.create(check_dir)
  message("Results saved in ", check_dir)

  old <- options(warn = 1)
  on.exit(options(old), add = TRUE)

  # Create and use temporary library
  if (!file.exists(libpath)) dir.create(libpath)
  libpath <- normalizePath(libpath)

  # Add the temoporary library and remove on exit
  libpaths_orig <- set_libpaths(libpath)
  on.exit(.libPaths(libpaths_orig), add = TRUE)

  rule("Installing dependencies") # --------------------------------------------
  repos <- c(CRAN = "http://cran.rstudio.com/")
  if (bioconductor) {
    repos <- c(repos, BiocInstaller::biocinstallRepos())
  }
  available_src <- available_packages(repos, "source")

  message("Determining available packages") # ----------------------------------
  deps <- package_deps(pkgs, repos = repos, type = type, dependencies = TRUE)
  update(deps, Ncpus = threads)

  message("Downloading source packages for checking") #-------------------------
  urls <- lapply(pkgs, package_url, repos = repos, available = available_src)
  ok <- vapply(urls, function(x) !is.na(x$name), logical(1))
  if (any(!ok)) {
    message("Couldn't find source for: ", paste(pkgs[!ok], collapse = ", "))
    urls <- urls[ok]
    pkgs <- pkgs[ok]
  }

  local_urls <- file.path(srcpath, vapply(urls, `[[`, "name", FUN.VALUE = character(1)))
  remote_urls <- vapply(urls, `[[`, "url", FUN.VALUE = character(1))

  needs_download <- !file.exists(local_urls)
  if (any(needs_download)) {
    message("Downloading ", sum(needs_download), " packages")
    Map(utils::download.file, remote_urls[needs_download],
      local_urls[needs_download], quiet = TRUE)
  }

  rule("Checking packages") # --------------------------------------------------
  check_pkg <- function(i) {
    message("Checking ", pkgs[i])

    start_time <- Sys.time()
    check_out <- tryCatch({
      check_r_cmd(pkgs[i], local_urls[i],
        args = "--no-multiarch --no-manual --no-codoc",
        check_dir = check_dir,
        quiet = TRUE
      )
    }, error = function(e) {
      message("Check failed: ", e$message)
      NULL
    })
    end_time <- Sys.time()

    elapsed_time <- as.numeric(end_time - start_time, units = "secs")
    writeLines(
      sprintf("%d  %s  %.1f", i, pkgs[i], elapsed_time),
      file.path(check_dir, paste0(pkgs[i], ".Rcheck"), "check-time.txt")
    )

    NULL
  }

  if (identical(as.integer(threads), 1L)) {
    lapply(seq_along(pkgs), check_pkg)
  } else {
    parallel::mclapply(seq_along(pkgs), check_pkg, mc.preschedule = FALSE,
      mc.cores = threads)
  }

  invisible(check_dir)
}
