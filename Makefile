.PHONY: all pipeline test report figures clean

# Full pipeline, in order. Needs IPUMS_API_KEY in .env for R/03; see
# .env.example and README.md.
PIPELINE := R/01_treatment_classification.R \
            R/02_fetch_fred_data.R \
            R/03_fetch_cps_org.R \
            R/04_exposure_measure.R \
            R/05_exposure_validation.R \
            R/06_slr_mlr.R \
            R/07_model_a_c.R \
            R/08_event_study.R \
            R/09_covid_sensitivity.R \
            R/10_placebo_test.R \
            R/11_cluster_bootstrap.R \
            R/12_model_diagnostics.R \
            R/13_two_sample_ttest.R \
            R/14_regional_anova.R \
            R/15_permutation_test.R \
            R/16_power_analysis.R \
            R/17_exposure_bandwidth_sensitivity.R \
            R/18_marginal_effects.R \
            R/19_treatment_intensity.R \
            R/20_leave_one_out.R \
            R/21_coefficient_forest_plot.R \
            R/22_multiple_testing_correction.R

all: pipeline test figures report

pipeline:
	@for script in $(PIPELINE); do \
		echo "== $$script =="; \
		Rscript $$script || exit 1; \
	done

test:
	Rscript -e 'testthat::test_dir("tests")'

figures:
	Rscript scripts/generate_readme_figures.R

report:
	Rscript -e 'rmarkdown::render("reports/final_report.Rmd")'

clean:
	rm -f data/processed/*.csv reports/final_report.html
