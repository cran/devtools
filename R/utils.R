# Given the name or vector of names, returns a named vector reporting
# whether each exists and is a directory.
dir.exists <- function(x) {
  res <- file.exists(x) & file.info(x)$isdir
  stats::setNames(res, x)
}

compact <- function(x) {
  is_empty <- vapply(x, function(x) length(x) == 0, logical(1))
  x[!is_empty]
}

"%||%" <- function(a, b) if (!is.null(a)) a else b

"%:::%" <- function(p, f) {
  get(f, envir = asNamespace(p))
}

# check whether the specified file ends with newline
ends_with_newline <- function(path) {
  conn <- file(path, open = "rb", raw = TRUE)
  on.exit(close(conn))
  seek(conn, where = -1, origin = "end")
  lastByte <- readBin(conn, "raw", n = 1)
  lastByte == 0x0a
}

is_installed <- function(pkg, version = 0) {
  installed_version <- tryCatch(utils::packageVersion(pkg), error = function(e) NA)
  !is.na(installed_version) && installed_version >= version
}

read_dcf <- function(path) {
  fields <- colnames(read.dcf(path))
  as.list(read.dcf(path, keep.white = fields)[1, ])
}

write_dcf <- function(path, desc) {
  desc <- unlist(desc)
  # Add back in continuation characters
  desc <- gsub("\n[ \t]*\n", "\n .\n ", desc, perl = TRUE, useBytes = TRUE)
  desc <- gsub("\n \\.([^\n])", "\n  .\\1", desc, perl = TRUE, useBytes = TRUE)

  starts_with_whitespace <- grepl("^\\s", desc, perl = TRUE, useBytes = TRUE)
  delimiters <- ifelse(starts_with_whitespace, ":", ": ")
  text <- paste0(names(desc), delimiters, desc, collapse = "\n")

  # If the description file has a declared encoding, set it so nchar() works
  # properly.
  if ("Encoding" %in% names(desc)) {
    Encoding(text) <- desc[["Encoding"]]
  }

  if (substr(text, nchar(text), 1) != "\n") {
    text <- paste0(text, "\n")
  }

  cat(text, file = path)
}

dots <- function(...) {
  eval(substitute(alist(...)))
}

first_upper <- function(x) {
  substr(x, 1, 1) <- toupper(substr(x, 1, 1))
  x
}

download <- function(path, url, ...) {
  request <- httr::GET(url, ...)
  httr::stop_for_status(request)
  writeBin(httr::content(request, "raw"), path)
  path
}

download_text <- function(url, ...) {
  request <- httr::GET(url, ...)
  httr::stop_for_status(request)
  httr::content(request, "text")
}

last <- function(x) x[length(x)]

# Modified version of utils::file_ext. Instead of always returning the text
# after the last '.', as in "foo.tar.gz" => ".gz", if the text that directly
# precedes the last '.' is ".tar", it will include also, so
# "foo.tar.gz" => ".tar.gz"
file_ext <- function(x) {
  pos <- regexpr("\\.((tar\\.)?[[:alnum:]]+)$", x)
  ifelse(pos > -1L, substring(x, pos + 1L), "")
}

trim_ws <- function(x) {
  gsub("^[[:space:]]+|[[:space:]]+$", "", x)
}

is_dir <- function(x) file.info(x)$isdir

indent <- function(x, spaces = 4) {
  ind <- paste(rep(" ", spaces), collapse = "")
  paste0(ind, gsub("\n", paste0("\n", ind), x, fixed = TRUE))
}

is_windows <- isTRUE(.Platform$OS.type == "windows")

all_named <- function(x) {
  if (length(x) == 0) return(TRUE)
  !is.null(names(x)) && all(names(x) != "")
}

sort_ci <- function(x) {
  withr::with_collate("C", x[order(tolower(x), x)])
}

comma <- function(x, at_most = 20) {
  if (length(x) > at_most) {
    x <- c(x[seq_len(at_most)], "...")
  }
  paste(x, collapse = ", ")
}

is_loaded <- function(pkg = ".") {
  pkg <- as.package(pkg)
  pkg$package %in% loadedNamespaces()
}

is_attached <- function(pkg = ".") {
  pkg <- as.package(pkg)

  !is.null(pkgload::pkg_env(pkg$package))
}

# This is base::trimws from 3.2 on
trim_ws <- function(x, which = c("both", "left", "right")) {
  which <- match.arg(which)
  mysub <- function(re, x) sub(re, "", x, perl = TRUE)
  if (which == "left") {
    return(mysub("^[ \t\r\n]+", x))
  }
  if (which == "right") {
    return(mysub("[ \t\r\n]+$", x))
  }
  mysub("[ \t\r\n]+$", mysub("^[ \t\r\n]+", x))
}

# throws a warning if the argument is not the current directory.
warn_unless_current_dir <- function(pkg, envir = parent.frame()) {
  if (pkg != ".") {
    warning("`pkg` is not `.`, which is now unsupported.\n  Please use `usethis::proj_set()` to set the project directory.", immediate. = TRUE)
    usethis::local_project(pkg, quiet = TRUE, .local_envir = envir)
  }
}

menu <- function(...) {
  utils::menu(...)
}

file.info <- function(...) {
  base::file.info(...)
}

escape_special_regex <- function(x) {
  chars <- c("*", ".", "?", "^", "+", "$", "|", "(", ")", "[", "]", "{", "}", "\\")
  gsub(paste0("([\\", paste0(collapse = "\\", chars), "])"), "\\\\\\1", x, perl = TRUE)
}

has_dev_remotes <- function(pkg) {
  !is.null(pkg[["remotes"]])
}

vcapply <- function(x, FUN, ...) {
  vapply(x, FUN, FUN.VALUE = character(1), ...)
}

hd_line <- function(name) {
  cat_rule(cli::style_bold(name))
}

kv_line <- function (key, value, path = FALSE) {
  if (is.null(value)) {
    value <- cli::col_silver("<unset>")
  }
  else {
    if (path) {
      value <- ui_path(value, base = NA)
    } else {
      value <- ui_value(value)
    }
  }
  cat_line("* ", key, ": ", value)
}

cat_line <- function (..., quiet = getOption("usethis.quiet", default = FALSE)) {
  if (quiet) {
    return(invisible())
  }
  lines <- paste0(..., "\n")
  cat(lines, sep = "")
}

release_bullets <- function() {
  c(
    '`usethis::use_latest_dependencies(TRUE, "CRAN")`',
    NULL
  )
}
