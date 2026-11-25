model_data <- function(clean) {
  d <- clean[clean$region_name == "Western Atlantic", ]
  d$reef <- factor(d$reef_id)
  d$coral_between <- ave(d$hard_coral, d$reef, FUN = mean) / 10
  d$coral_within <- d$hard_coral / 10 - d$coral_between
  d$depth10 <- d$depth / 10
  d
}

# Gauss-Hermite quadrature for a standard normal random intercept.
normal_quadrature <- function(n = 40L) {
  jacobi <- matrix(0, n, n)
  jacobi[cbind(1:(n - 1L), 2:n)] <- sqrt(seq_len(n - 1L))
  e <- eigen(jacobi + t(jacobi), symmetric = TRUE)
  list(nodes = e$values, weights = e$vectors[1, ]^2)
}

fit_encounters <- function(d, coral, nodes = 20L, hessian = FALSE) {
  form <- if (coral) {
    caribbean ~ coral_within + coral_between + depth10 + substrate_relief_mean
  } else {
    caribbean ~ depth10 + substrate_relief_mean
  }
  x <- model.matrix(form, d)
  y <- d$caribbean
  reefs <- match(d$reef_id, unique(d$reef_id))
  k <- ncol(x)
  quad <- normal_quadrature(nodes)
  nll <- function(par) {
    base_eta <- drop(x %*% par[seq_len(k)])
    variance <- exp(2 * par[k + 1L])
    # Center and scale each reef's quadrature at its conditional mode.
    mode <- numeric(max(reefs))
    for (iteration in seq_len(60L)) {
      prob <- plogis(base_eta + mode[reefs])
      gradient <- drop(rowsum(y - prob, reefs, reorder = FALSE)) - mode / variance
      curvature <- drop(rowsum(prob * (1 - prob), reefs, reorder = FALSE)) + 1 / variance
      step <- pmax(-1, pmin(1, gradient / curvature))
      mode <- mode + step
      if (max(abs(step)) < 1e-9) break
    }
    if (max(abs(step)) >= 1e-6) return(1e20)
    scale <- 1 / sqrt(curvature)
    offset <- mode + outer(scale, quad$nodes)
    eta <- base_eta + offset[reefs, , drop = FALSE]
    ll <- plogis(-eta, log.p = TRUE)
    ll[y == 1L, ] <- plogis(eta[y == 1L, , drop = FALSE], log.p = TRUE)
    correction <- -offset^2 / (2 * variance) + log(scale) - .5 * log(variance)
    group_ll <- rowsum(ll, reefs, reorder = FALSE) + correction
    group_ll <- sweep(group_ll, 2L, log(quad$weights) + quad$nodes^2 / 2, "+")
    max_ll <- apply(group_ll, 1L, max)
    -sum(max_ll + log(rowSums(exp(group_ll - max_ll))))
  }
  start <- c(unname(coef(glm(form, data = d, family = binomial()))), log(.8))
  fit <- optim(start, nll, method = "BFGS", hessian = hessian,
               control = list(reltol = 1e-10, maxit = 500L))
  stopifnot(fit$convergence == 0L, all(is.finite(fit$par)))
  list(form = form, beta = setNames(fit$par[seq_len(k)], colnames(x)),
       reef_sd = exp(fit$par[k + 1L]), log_likelihood = -fit$value,
       hessian = fit$hessian, quad = quad)
}

predict_new_reef <- function(model, d) {
  quad <- normal_quadrature(60L)
  eta <- drop(model.matrix(delete.response(terms(model$form)), d) %*% model$beta)
  drop(plogis(outer(eta, model$reef_sd * quad$nodes, "+")) %*%
         quad$weights)
}

prediction_scores <- function(y, p) {
  p <- pmin(pmax(p, 1e-12), 1 - 1e-12)
  c(brier = mean((y - p)^2), log_loss = -mean(y * log(p) + (1 - y) * log1p(-p)))
}

validate_models <- function(d, folds = 5L) {
  set.seed(202311L)
  reefs <- sample(sort(unique(d$reef_id)))
  assignment <- setNames(rep(seq_len(folds), length.out = length(reefs)), reefs)
  fold <- unname(assignment[as.character(d$reef_id)])
  blocks <- c(lapply(seq_len(folds), function(i) which(fold == i)),
              list(which(d$location_name == "Belize")))
  labels <- c(paste("Reef fold", seq_len(folds)), "Belize holdout")
  out <- lapply(seq_along(blocks), function(i) {
    test <- d[blocks[[i]], ]
    train <- droplevels(d[-blocks[[i]], ])
    stopifnot(nrow(test) > 0L, length(intersect(train$reef_id, test$reef_id)) == 0L)
    coral <- predict_new_reef(fit_encounters(train, TRUE), test)
    baseline <- predict_new_reef(fit_encounters(train, FALSE), test)
    data.frame(block = labels[i], reef_id = test$reef_id, set_id = test$set_id,
               encounter = test$caribbean, baseline, coral)
  })
  predictions <- do.call(rbind, out)
  stats <- function(x, label) {
    b <- prediction_scores(x$encounter, x$baseline)
    c <- prediction_scores(x$encounter, x$coral)
    data.frame(block = label, deployments = nrow(x), reefs = length(unique(x$reef_id)),
               detections = sum(x$encounter), brier_baseline = b[1], brier_coral = c[1],
               log_loss_baseline = b[2], log_loss_coral = c[2],
               brier_change = c[1] - b[1], log_loss_change = c[2] - b[2],
               row.names = NULL)
  }
  combined <- predictions[predictions$block != "Belize holdout", ]
  stopifnot(nrow(combined) == nrow(d), !anyDuplicated(combined$set_id))
  by_block <- lapply(seq_along(labels), function(i) stats(out[[i]], labels[i]))
  metrics <- rbind(stats(combined, "Pooled reef folds"), do.call(rbind, by_block))
  by_reef <- do.call(rbind, lapply(split(combined, combined$reef_id), function(x) {
    stats(x, as.character(x$reef_id[1]))
  }))
  list(predictions = predictions, metrics = metrics, by_reef = by_reef)
}

coefficient_table <- function(model) {
  beta <- model$beta
  se <- sqrt(diag(chol2inv(chol(model$hessian))))[seq_along(beta)]
  data.frame(term = names(beta), log_odds = beta, se = se,
             p_value = 2 * pnorm(-abs(beta / se)), odds_ratio = exp(beta),
             lower = exp(beta - qnorm(.975) * se),
             upper = exp(beta + qnorm(.975) * se), row.names = NULL)
}


