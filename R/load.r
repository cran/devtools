#' Load complete package.
#'
#' \code{load_all} loads a package. It roughly simulates what happens
#' when a package is installed and loaded with \code{\link{library}}.
#'
#' Currently \code{load_all}:
#'
#' \itemize{
#'   \item Loads all data files in \code{data/}.  See \code{\link{load_data}}
#'     for more details.
#'
#'   \item Sources all R files in the R directory, storing results in
#'     environment that behaves like a regular package namespace. See
#'     below and \code{\link{load_code}} for more details.
#'
#'   \item Compiles any C, C++, or Fortran code in the \code{src/} directory
#'     and connects the generated DLL into R. See \code{\link{compile_dll}}
#'     for more details.
#'
#'   \item If you use \pkg{testthat}, will load all test helpers so you
#'     can access them interactively.
#'
#'   \item Runs \code{.onAttach()}, \code{.onLoad()} and \code{.onUnload()}
#'     functions at the correct times.
#' }
#'
#' @section Namespaces:
#' The namespace environment \code{<namespace:pkgname>}, is a child of
#' the imports environment, which has the name attribute
#' \code{imports:pkgname}. It is in turn is a child of
#' \code{<namespace:base>}, which is a child of the global environment.
#' (There is also a copy of the base namespace that is a child of the empty
#' environment.)
#'
#' The package environment \code{<package:pkgname>} is an ancestor of the
#' global environment. Normally when loading a package, the objects
#' listed as exports in the NAMESPACE file are copied from the namespace
#' to the package environment. However, \code{load_all} by default will
#' copy all objects (not just the ones listed as exports) to the package
#' environment. This is useful during development because it makes all
#' objects easy to access.
#'
#' To export only the objects listed as exports, use
#' \code{export_all=FALSE}. This more closely simulates behavior when
#' loading an installed package with \code{\link{library}}, and can be
#' useful for checking for missing exports.
#'
#' @section Shim files:
#' \code{load_all} also inserts shim functions into the imports environment
#' of the laded package. It presently adds a replacement version of
#' \code{system.file} which returns different paths from
#' \code{base::system.file}. This is needed because installed and uninstalled
#' package sources have different directory structures. Note that this is not
#' a perfect replacement for \code{base::system.file}.
#'
#' @param pkg package description, can be path or package name.  See
#'   \code{\link{as.package}} for more information.
#' @param reset clear package environment and reset file cache before loading
#'   any pieces of the package. This is equivalent to running
#'   \code{\link{unload}} and is the default. Use \code{reset = FALSE} may be
#'   faster for large code bases, but is a significantly less accurate
#'   approximation.
#' @param recompile force a recompile of DLL from source code, if present.
#'   This is equivalent to running \code{\link{clean_dll}} before
#'   \code{load_all}
#' @param export_all If \code{TRUE} (the default), export all objects.
#'   If \code{FALSE}, export only the objects that are listed as exports
#'   in the NAMESPACE file.
#' @param quiet if \code{TRUE} suppresses output from this function.
#' @inheritParams as.package
#' @keywords programming
#' @examples
#' \dontrun{
#' # Load the package in the current directory
#' load_all("./")
#'
#' # Running again loads changed files
#' load_all("./")
#'
#' # With reset=TRUE, unload and reload the package for a clean start
#' load_all("./", TRUE)
#'
#' # With export_all=FALSE, only objects listed as exports in NAMESPACE
#' # are exported
#' load_all("./", export_all = FALSE)
#' }
#' @export
load_all <- function(pkg = ".", reset = TRUE, recompile = FALSE,
  export_all = TRUE, quiet = FALSE, create = NA) {
  pkg <- as.package(pkg, create = create)
  check_suggested("roxygen2")

  if (!quiet) message("Loading ", pkg$package)

  roxygen2::update_collate(pkg$path)
  # Refresh the pkg structure with any updates to the Collate entry
  # in the DESCRIPTION file
  pkg$collate <- as.package(pkg$path)$collate

  # Forcing all of the promises for the loaded namespace now will avoid lazy-load
  # errors when the new package is loaded overtop the old one.
  #
  # Reloading devtools is a special case. Normally, objects in the
  # namespace become inaccessible if the namespace is unloaded before the
  # object has been accessed. Instead we force the object so they will still be
  # accessible.
  if (is_loaded(pkg)) {
    eapply(ns_env(pkg), force, all.names = TRUE)
  }

  # Check description file is ok
  check <- ("tools" %:::% ".check_package_description")(
    file.path(pkg$path, "DESCRIPTION"))
  if (length(check) > 0) {
    msg <- utils::capture.output(("tools" %:::% "print.check_package_description")(check))
    message("Invalid DESCRIPTION:\n", paste(msg, collapse = "\n"))
  }

  # If installed version of package loaded, unload it
  if (is_loaded(pkg) && is.null(dev_meta(pkg$package))) {
    unload(pkg)
  }

  # Unload dlls
  unload_dll(pkg)

  if (reset) {
    clear_cache()
    if (is_loaded(pkg)) unload(pkg)
  }

  if (recompile) clean_dll(pkg)

  # Compile dll if it exists
  compile_dll(pkg, quiet = quiet)


  # Set up the namespace environment ----------------------------------
  # This mimics the procedure in loadNamespace

  if (!is_loaded(pkg)) create_ns_env(pkg)

  out <- list(env = ns_env(pkg))

  # Load dependencies
  load_depends(pkg)
  load_imports(pkg)
  # Add shim objects to imports environment
  insert_imports_shims(pkg)

  out$data <- load_data(pkg)

  out$code <- load_code(pkg)
  register_s3(pkg)
  out$dll <- load_dll(pkg)

  # Run namespace load hooks
  run_pkg_hook(pkg, "load")
  run_ns_load_actions(pkg)
  run_user_hook(pkg, "load")

  # Set up the exports in the namespace metadata (this must happen after
  # the objects are loaded)
  setup_ns_exports(pkg, export_all)

  # Set up the package environment ------------------------------------
  # Create the package environment if needed
  if (!is_attached(pkg)) attach_ns(pkg)

  # Copy over objects from the namespace environment
  export_ns(pkg)

  # Source test helpers into package environment
  if (uses_testthat(pkg)) {
    testthat::source_test_helpers(find_test_dir(pkg$path), env = pkg_env(pkg))
  }

  # Run hooks
  run_pkg_hook(pkg, "attach")
  run_user_hook(pkg, "attach")

  # Replace help and ? in utils package environment
  insert_global_shims()

  invisible(out)
}


#' Create a default DESCRIPTION file for a package.
#'
#' @details
#' To set the default author and licenses, set \code{options}
#' \code{devtools.desc.author} and \code{devtools.desc.license}.  I use
#' \code{options(devtools.desc.author = '"Hadley Wickham <h.wickham@@gmail.com> [aut,cre]"',
#'   devtools.desc.license = "GPL-3")}.
#' @param path path to package root directory
#' @param extra a named list of extra options to add to \file{DESCRIPTION}.
#'   Arguments that take a list
#' @param quiet if \code{TRUE}, suppresses output from this function.
#' @export
create_description <- function(path = ".", extra = getOption("devtools.desc"),
                               quiet = FALSE) {
  # Don't call check_dir(path) here (#803)
  desc_path <- file.path(path, "DESCRIPTION")

  if (file.exists(desc_path)) return(FALSE)

  subdir <- file.path(path, c("R", "src", "data"))
  if (!any(file.exists(subdir))) {
    stop("'", path, "' does not look like a package: no R/, src/ or data directories",
      call. = FALSE)
  }

  desc <- build_description(extract_package_name(path), extra)

  if (!quiet) {
    message("No DESCRIPTION found. Creating with values:\n\n")
    write_dcf("", desc)
  }

  write_dcf(desc_path, desc)

  TRUE
}

build_description <- function(name, extra = list()) {
  check_package_name(name)

  defaults <- compact(list(
    Package = name,
    Title = "What the Package Does (one line, title case)",
    Version = "0.0.0.9000",
    "Authors@R" = getOption("devtools.desc.author"),
    Description = "What the package does (one paragraph).",
    Depends = paste0("R (>= ", as.character(getRversion()) ,")"),
    License = getOption("devtools.desc.license"),
    Suggests = getOption("devtools.desc.suggests"),
    Encoding = "UTF-8",
    LazyData = "true"
  ))

  # Override defaults with user supplied options
  desc <- modifyList(defaults, extra)
  # Collapse all vector arguments to single strings
  desc <- lapply(desc, function(x) paste(x, collapse = ", "))

  desc
}
