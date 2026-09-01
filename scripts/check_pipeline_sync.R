# CI guard: verifies two invariants the README and Makefile both claim
# but nothing previously checked automatically --
#   1. every script in R/ is listed in the Makefile's PIPELINE variable
#      (so `make all` can't silently skip a script the way a manual
#      check might miss -- this exact drift was checked by hand, not by
#      tooling, right before this script was written)
#   2. every script in R/ has a matching tests/test-*.R file (the
#      convention README.md's Repo Layout section already documents)
# Exits non-zero with a specific message on either violation, so CI
# fails loudly instead of the repo quietly drifting out of sync.

scripts <- sort(basename(list.files("R", pattern = "\\.R$")))

makefile <- readLines("Makefile")
pipeline_lines <- makefile[grepl("R/[0-9]+_[A-Za-z0-9_]+\\.R", makefile)]
referenced <- regmatches(pipeline_lines, regexpr("R/[0-9]+_[A-Za-z0-9_]+\\.R", pipeline_lines))
referenced <- sort(unique(sub("^R/", "", referenced)))

missing_from_makefile <- setdiff(scripts, referenced)
extra_in_makefile <- setdiff(referenced, scripts)

# R/NN_some_script.R -> tests/test-some-script.R (numeric prefix
# dropped, underscores become hyphens -- the convention every existing
# test file already follows).
expected_test_file <- function(script) {
  base <- sub("\\.R$", "", script)
  name <- sub("^[0-9]+_", "", base)
  name <- gsub("_", "-", name)
  file.path("tests", paste0("test-", name, ".R"))
}
missing_tests <- Filter(function(s) !file.exists(expected_test_file(s)), scripts)

ok <- TRUE

if (length(missing_from_makefile) > 0) {
  ok <- FALSE
  cat("In R/ but missing from Makefile's PIPELINE:\n")
  cat(paste0(" - ", missing_from_makefile, collapse = "\n"), "\n", sep = "")
}
if (length(extra_in_makefile) > 0) {
  ok <- FALSE
  cat("In Makefile's PIPELINE but not present in R/:\n")
  cat(paste0(" - ", extra_in_makefile, collapse = "\n"), "\n", sep = "")
}
if (length(missing_tests) > 0) {
  ok <- FALSE
  cat("R/ scripts with no matching tests/test-*.R file:\n")
  for (s in missing_tests) {
    cat(" - ", s, " (expected ", expected_test_file(s), ")\n", sep = "")
  }
}

if (!ok) {
  quit(status = 1)
}

cat("Pipeline sync OK:", length(scripts), "scripts in R/, all listed in",
    "Makefile's PIPELINE, all with a matching test file.\n")
