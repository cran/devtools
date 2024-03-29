% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/lint.R
\name{lint}
\alias{lint}
\title{Lint all source files in a package}
\usage{
lint(pkg = ".", cache = TRUE, ...)
}
\arguments{
\item{pkg}{The package to use, can be a file path to the package or a
package object.  See \code{\link[=as.package]{as.package()}} for more information.}

\item{cache}{Store the lint results so repeated lints of the same content use
the previous results. Consult the lintr package to learn more about its
caching behaviour.}

\item{...}{Additional arguments passed to \code{\link[lintr:lint]{lintr::lint_package()}}.}
}
\description{
The default linters correspond to the style guide at
\url{https://style.tidyverse.org/}, however it is possible to override any or all
of them using the \code{linters} parameter.
}
\seealso{
\code{\link[lintr:lint]{lintr::lint_package()}}, \code{\link[lintr:lint]{lintr::lint()}}
}
