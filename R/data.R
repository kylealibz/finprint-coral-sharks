focal_species <- c("Carcharhinus perezi" = "Caribbean reef shark",
                   "Ginglymostoma cirratum" = "Nurse shark",
                   "Carcharhinus amblyrhynchos" = "Grey reef shark",
                   "Carcharhinus melanopterus" = "Blacktip reef shark",
                   "Triaenodon obesus" = "Whitetip reef shark")
species_columns <- c("caribbean", "nurse", "grey", "blacktip", "whitetip")

prepare_deployments <- function(path) {
  keep <- c("set_id", "reef_id", "region_name", "location_name", "hard_coral",
            "depth", "substrate_relief_mean", "latin_name", "maxn")
  raw <- read.csv(path, na.strings = c("", "NA"), encoding = "latin1",
                  stringsAsFactors = FALSE)[keep]
  stopifnot(!anyNA(raw$set_id), !anyNA(raw$reef_id), !anyNA(raw$maxn),
            all(raw$maxn >= 0))
  groups <- split(seq_len(nrow(raw)), raw$set_id)
  meta <- keep[3:7]
  rows <- lapply(groups, function(index) {
    d <- raw[index, ]
    values <- lapply(d[meta], function(x) unique(x[!is.na(x)]))
    conflicts <- any(lengths(values) > 1L) || length(unique(d$reef_id)) != 1L
    values <- lapply(values, function(x) x[1L])
    detect <- setNames(as.list(as.integer(names(focal_species) %in%
                            d$latin_name[d$maxn > 0])), species_columns)
    c(list(set_id = d$set_id[1L], reef_id = d$reef_id[1L]),
      values, list(conflicting_metadata = conflicts), detect)
  })
  result <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  rownames(result) <- NULL
  result
}

screen_species <- function(d) {
  complete <- with(d, !conflicting_metadata & is.finite(hard_coral) &
                   hard_coral >= 0 & hard_coral <= 100 & is.finite(depth) &
                   depth >= 0 & depth <= 40 & is.finite(substrate_relief_mean) &
                   substrate_relief_mean >= 0 & substrate_relief_mean <= 5 &
                   !is.na(region_name) & !is.na(location_name))
  atlas <- d[complete, ]
  summary <- do.call(rbind, lapply(seq_along(species_columns), function(i) {
    a <- atlas[(atlas$region_name == "Western Atlantic") == (i <= 2L), ]
    y <- a[[species_columns[i]]]
    mixed <- sum(vapply(split(y, a$reef_id), function(x) length(unique(x)) == 2L,
                        logical(1)))
    data.frame(species = unname(focal_species[i]), scientific_name = names(focal_species)[i],
               domain = if (i <= 2L) "Western Atlantic" else "Indo-Pacific",
               deployments = nrow(a), reefs = length(unique(a$reef_id)),
               positive_deployments = sum(y), positive_reefs = length(unique(a$reef_id[y == 1])),
               mixed_reefs = mixed, eligible = sum(y) >= 100L && mixed >= 10L)
  }))
  list(clean = atlas, summary = summary, audit = data.frame(
    all_deployments = nrow(d), conflicting_deployments = sum(d$conflicting_metadata),
    measured_coral = sum(is.finite(d$hard_coral) & !d$conflicting_metadata),
    complete_deployments = sum(complete)))
}
