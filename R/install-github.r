#' Attempts to install a package directly from GitHub.
#'
#' This function is vectorised on \code{repo} so you can install multiple
#' packages in a single command.
#'
#' @param repo Repository address in the format
#'   \code{username/repo[/subdir][@@ref|#pull]}. Alternatively, you can
#'   specify \code{subdir} and/or \code{ref} using the respective parameters
#'   (see below); if both are specified, the values in \code{repo} take
#'   precedence.
#' @param username User name. Deprecated: please include username in the
#'   \code{repo}
#' @param ref Desired git reference. Could be a commit, tag, or branch
#'   name, or a call to \code{\link{github_pull}}. Defaults to \code{"master"}.
#' @param subdir subdirectory within repo that contains the R package.
#' @param auth_token To install from a private repo, generate a personal
#'   access token (PAT) in \url{https://github.com/settings/tokens} and
#'   supply to this argument. This is safer than using a password because
#'   you can easily delete a PAT without affecting any others. Defaults to
#'   the \code{GITHUB_PAT} environment variable.
#' @param host GitHub API host to use. Override with your GitHub enterprise
#'   hostname, for example, \code{"github.hostname.com/api/v3"}.
#' @param quiet if \code{TRUE} suppresses output from this function.
#' @param ... Other arguments passed on to \code{\link{install}}.
#' @details
#' Attempting to install from a source repository that uses submodules
#' raises a warning. Because the zipped sources provided by GitHub do not
#' include submodules, this may lead to unexpected behaviour or compilation
#' failure in source packages. In this case, cloning the repository manually
#' using \code{\link{install_git}} with \code{args="--recursive"} may yield
#' better results.
#' @export
#' @family package installation
#' @seealso \code{\link{github_pull}}
#' @examples
#' \dontrun{
#' install_github("klutometis/roxygen")
#' install_github("wch/ggplot2")
#' install_github(c("rstudio/httpuv", "rstudio/shiny"))
#' install_github(c("hadley/httr@@v0.4", "klutometis/roxygen#142",
#'   "mfrasca/r-logging/pkg"))
#'
#' # Update devtools to the latest version, on Linux and Mac
#' # On Windows, this won't work - see ?build_github_devtools
#' install_github("hadley/devtools")
#'
#' # To install from a private repo, use auth_token with a token
#' # from https://github.com/settings/tokens. You only need the
#' # repo scope. Best practice is to save your PAT in env var called
#' # GITHUB_PAT.
#' install_github("hadley/private", auth_token = "abc")
#'
#' }
install_github <- function(repo, username = NULL,
                           ref = "master", subdir = NULL,
                           auth_token = github_pat(quiet),
                           host = "https://api.github.com", quiet = FALSE,
                           ...) {

  remotes <- lapply(repo, github_remote, username = username, ref = ref,
    subdir = subdir, auth_token = auth_token, host = host)

  install_remotes(remotes, quiet = quiet, ...)
}

github_remote <- function(repo, username = NULL, ref = NULL, subdir = NULL,
                       auth_token = github_pat(), sha = NULL,
                       host = "https://api.github.com") {

  meta <- parse_git_repo(repo)
  meta <- github_resolve_ref(meta$ref %||% ref, meta)

  if (is.null(meta$username)) {
    meta$username <- username %||% getOption("github.user") %||%
      stop("Unknown username.")
    warning("Username parameter is deprecated. Please use ",
      username, "/", repo, call. = FALSE)
  }

  remote("github",
    host = host,
    repo = meta$repo,
    subdir = meta$subdir %||% subdir,
    username = meta$username,
    ref = meta$ref,
    sha = sha,
    auth_token = auth_token
  )
}

#' @export
remote_download.github_remote <- function(x, quiet = FALSE) {
  dest <- tempfile(fileext = paste0(".zip"))

  if (missing_protocol <- !grepl("^[^:]+?://", x$host)) {
    x$host <- paste0("https://", x$host)
  }

  src_root <- paste0(x$host, "/repos/", x$username, "/", x$repo)
  src <- paste0(src_root, "/zipball/", x$ref)

  if (!quiet) {
    message("Downloading GitHub repo ", x$username, "/", x$repo, "@", x$ref,
            "\nfrom URL ", src)
  }

  if (!is.null(x$auth_token)) {
    auth <- httr::authenticate(
      user = x$auth_token,
      password = "x-oauth-basic",
      type = "basic"
    )
  } else {
    auth <- NULL
  }

  if (github_has_remotes(x, auth))
    warning("GitHub repo contains submodules, may not function as expected!",
      call. = FALSE)

  download_github(dest, src, auth)
}

github_has_remotes <- function(x, auth = NULL) {
  src_root <- paste0(x$host, "/repos/", x$username, "/", x$repo)
  src_submodules <- paste0(src_root, "/contents/.gitmodules?ref=", x$ref)
  response <- httr::HEAD(src_submodules, , auth)
  identical(httr::status_code(response), 200L)
}

#' @export
remote_metadata.github_remote <- function(x, bundle = NULL, source = NULL) {
  # Determine sha as efficiently as possible
  if (!is.null(bundle)) {
    # Might be able to get from zip archive
    sha <- git_extract_sha1(bundle)
  } else {
    # Otherwise can lookup with remote_ls
    sha <- remote_sha(x)
  }

  list(
    RemoteType = "github",
    RemoteHost = x$host,
    RemoteRepo = x$repo,
    RemoteUsername = x$username,
    RemoteRef = x$ref,
    RemoteSha = sha,
    RemoteSubdir = x$subdir,
    # Backward compatibility for packrat etc.
    GithubRepo = x$repo,
    GithubUsername = x$username,
    GithubRef = x$ref,
    GithubSHA1 = sha,
    GithubSubdir = x$subdir
  )
}

#' GitHub references
#'
#' Use as \code{ref} parameter to \code{\link{install_github}}.
#' Allows installing a specific pull request or the latest release.
#'
#' @param pull The pull request to install
#' @seealso \code{\link{install_github}}
#' @rdname github_refs
#' @export
github_pull <- function(pull) structure(pull, class = "github_pull")

#' @rdname github_refs
#' @export
github_release <- function() structure(NA_integer_, class = "github_release")

github_resolve_ref <- function(x, params) UseMethod("github_resolve_ref")

#' @export
github_resolve_ref.default <- function(x, params) {
  params$ref <- x
  params
}

#' @export
github_resolve_ref.NULL <- function(x, params) {
  params$ref <- "master"
  params
}

#' @export
github_resolve_ref.github_pull <- function(x, params) {
  # GET /repos/:user/:repo/pulls/:number
  path <- file.path("repos", params$username, params$repo, "pulls", x)
  response <- github_GET(path)

  params$username <- response$head$user$login
  params$ref <- response$head$ref
  params
}

# Retrieve the ref for the latest release
#' @export
github_resolve_ref.github_release <- function(x, params) {
  # GET /repos/:user/:repo/releases
  path <- paste("repos", params$username, params$repo, "releases", sep = "/")
  response <- github_GET(path)
  if (length(response) == 0L)
    stop("No releases found for repo ", params$username, "/", params$repo, ".")

  params$ref <- response[[1L]]$tag_name
  params
}

# Parse concise git repo specification: [username/]repo[/subdir][#pull|@ref|@*release]
# (the *release suffix represents the latest release)
parse_git_repo <- function(path) {
  username_rx <- "(?:([^/]+)/)?"
  repo_rx <- "([^/@#]+)"
  subdir_rx <- "(?:/([^@#]*[^@#/]))?"
  ref_rx <- "(?:@([^*].*))"
  pull_rx <- "(?:#([0-9]+))"
  release_rx <- "(?:@([*]release))"
  ref_or_pull_or_release_rx <- sprintf("(?:%s|%s|%s)?", ref_rx, pull_rx, release_rx)
  github_rx <- sprintf("^(?:%s%s%s%s|(.*))$",
    username_rx, repo_rx, subdir_rx, ref_or_pull_or_release_rx)

  param_names <- c("username", "repo", "subdir", "ref", "pull", "release", "invalid")
  replace <- stats::setNames(sprintf("\\%d", seq_along(param_names)), param_names)
  params <- lapply(replace, function(r) gsub(github_rx, r, path, perl = TRUE))
  if (params$invalid != "")
    stop(sprintf("Invalid git repo: %s", path))
  params <- params[sapply(params, nchar) > 0]

  if (!is.null(params$pull)) {
    params$ref <- github_pull(params$pull)
    params$pull <- NULL
  }

  if (!is.null(params$release)) {
    params$ref <- github_release()
    params$release <- NULL
  }

  params
}

#' @export
remote_package_name.github_remote <- function(remote, url = "https://raw.githubusercontent.com", ...) {

  tmp <- tempfile()
  path <- paste(c(
      remote$username,
      remote$repo,
      remote$ref,
      remote$subdir,
      "DESCRIPTION"), collapse = "/")

  if (!is.null(remote$auth_token)) {
    auth <- httr::authenticate(
      user = remote$auth_token,
      password = "x-oauth-basic",
      type = "basic"
    )
  } else {
    auth <- NULL
  }

  req <- httr::GET(url, path = path, httr::write_disk(path = tmp), auth)

  if (httr::status_code(req) >= 400) {
    return(NA_character_)
  }

  read_dcf(tmp)$Package
}

#' @export
remote_sha.github_remote <- function(remote, url = "https://github.com", ...) {
  # If the remote ref is the same as the sha it is a pinned commit so just
  # return that.
  if (!is.null(remote$ref) && !is.null(remote$sha) &&
    grepl(paste0("^", remote$ref), remote$sha)) {
    return(remote$sha)
  }

  tryCatch({
    res <- git2r::remote_ls(
      paste0(url, "/", remote$username, "/", remote$repo, ".git"),
      ...)

    found <- grep(pattern = paste0("/", remote$ref), x = names(res))

    if (length(found) == 0) {
      return(NA_character_)
    }

    unname(res[found[1]])
  }, error = function(e) NA_character_)
}

#' @export
format.github_remote <- function(x, ...) {
  "GitHub"
}

download_github <- function(path, url, ...) {
  request <- httr::GET(url, ...)

  if (httr::status_code(request) >= 400) {
     stop(github_error(request))
  }

  writeBin(httr::content(request, "raw"), path)
  path
}
