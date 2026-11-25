source("R/plots.R")
plot_screen(read.csv("results/species-screen.csv"))
plot_effect(read.csv("results/coefficients.csv"))
plot_validation(read.csv("results/validation-metrics.csv"))
