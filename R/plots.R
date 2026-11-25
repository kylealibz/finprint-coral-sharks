save_chart <- function(path, draw) {
  png(path, width = 1350, height = 770, res = 145)
  on.exit(dev.off())
  draw()
}

plot_screen <- function(screen) {
  old <- par(mar = c(5, 10, 4, 2))
  on.exit(par(old))
  s <- screen[order(screen$positive_deployments), ]
  locations <- barplot(s$positive_deployments, horiz = TRUE, names.arg = s$species,
    las = 1, col = ifelse(s$scientific_name == "Carcharhinus perezi", "#C66330", "#16808C"),
    border = NA, xlim = c(0, max(s$positive_deployments) * 1.16),
    main = "Focal shark encounters in eligible BRUV deployments",
    xlab = "Deployments with a detection")
  text(s$positive_deployments, locations, s$positive_deployments, pos = 4, cex = .85)
  abline(v = 100, lty = 2, col = "gray45")
}

plot_effect <- function(coefs) {
  old <- par(mar = c(5, 9, 4, 2))
  on.exit(par(old))
  d <- coefs[match(c("coral_within", "coral_between"), coefs$term), ]
  plot(d$odds_ratio, c(2, 1), pch = 19, col = "#16808C", cex = 1.5,
       log = "x", xlim = exp(extendrange(log(range(d$lower, d$upper, 1)), f = .12)),
       ylim = c(.5, 2.5), yaxt = "n", ylab = "", bty = "l",
       xlab = "Encounter odds ratio per 10 percentage points of hard-coral cover",
       main = "Caribbean reef shark and hard-coral cover")
  axis(2, at = c(1, 2), labels = c("Between reefs", "Within reefs"), las = 1)
  abline(v = 1, lty = 2, col = "gray50")
  segments(d$lower, c(2, 1), d$upper, c(2, 1), col = "#16808C", lwd = 2)
  points(d$odds_ratio, c(2, 1), pch = 19, col = "#16808C", cex = 1.5)
  mtext("Mixed logistic model with depth, substrate relief, and reef random intercept",
        line = .4, cex = .75)
}

plot_validation <- function(metrics) {
  old <- par(mar = c(5, 10, 4, 2))
  on.exit(par(old))
  d <- metrics[nrow(metrics):1, ]
  x <- 1000 * d$log_loss_change
  plot(x, seq_along(x), pch = 19, yaxt = "n", ylab = "", bty = "l",
       xlim = extendrange(range(x, 0), f = .15), ylim = c(.5, length(x) + .5),
       col = ifelse(d$block %in% c("Pooled reef folds", "Belize holdout"), "#C66330", "#16808C"),
       xlab = "Change in log loss after adding coral (x 1,000)",
       main = "Prediction on reefs withheld from fitting")
  abline(v = 0, lty = 2, col = "gray50")
  axis(2, at = seq_along(x), labels = d$block, las = 1)
  mtext("Negative values favor the model with hard-coral cover", line = .4, cex = .8)
}

