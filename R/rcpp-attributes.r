
# Call the Rcpp::compileAttributes function for a package (only do so if the
# package links to Rcpp and a recent enough version of Rcpp in installed).
compile_rcpp_attributes <- function(pkg) {

  # Only scan for attributes in packages explicitly linking to Rcpp
  if (links_to_rcpp(pkg)) {
    check_suggested("Rcpp")
    Rcpp::compileAttributes(pkg$path)
  }
}

# Does this package have a compilation dependency on Rcpp?
links_to_rcpp <- function(pkg) {
  "Rcpp" %in% pkg_linking_to(pkg)
}

# Get the LinkingTo field of a package as a character vector
pkg_linking_to <- function(pkg) {
  parse_deps(pkg$linkingto)$name
}
