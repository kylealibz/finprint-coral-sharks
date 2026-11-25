source("R/data.R")
source("R/model.R")
source("R/plots.R")
d <- read.csv("data/deployments.csv")
stopifnot(!anyDuplicated(d$set_id))
screen <- screen_species(d)
stopifnot(screen$summary$eligible[1])
analysis <- model_data(screen$clean)
fit <- fit_encounters(analysis, TRUE, hessian = TRUE)
coefficients <- coefficient_table(fit)
validation <- validate_models(analysis)
dir.create("results", showWarnings = FALSE)
outputs <- list("data-audit" = screen$audit, "species-screen" = screen$summary,
                coefficients = coefficients, "validation-metrics" = validation$metrics,
                "held-out-predictions" = validation$predictions,
                "validation-by-reef" = validation$by_reef)
for (name in names(outputs)) {
  write.csv(outputs[[name]], file.path("results", paste0(name, ".csv")), row.names = FALSE)
}
writeLines(capture.output(print(fit[c("beta", "reef_sd", "log_likelihood")]), sessionInfo()), "results/model-and-session.txt")
save_chart("results/species-screen.png", function() plot_screen(screen$summary))
save_chart("results/coral-effects.png", function() plot_effect(coefficients))
save_chart("results/reef-validation.png", function() plot_validation(validation$metrics))
print(screen$summary, row.names = FALSE)
print(coefficients, row.names = FALSE)
print(validation$metrics, row.names = FALSE)

