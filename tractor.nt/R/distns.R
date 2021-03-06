evaluateDistribution <- function (x, params, log = FALSE)
{
    if (is(params, "betaDistribution"))
        return (evaluateBetaDistribution(x, params, log))
    else if (is(params, "gaussianDistribution"))
        return (evaluateGaussianDistribution(x, params, log))
    else if (is(params, "multinomialDistribution"))
        return (evaluateMultinomialDistribution(x, params, log))
}

fitBetaDistribution <- function (data, alpha = NULL, beta = 1, weights = NULL)
{
    if (!is.vector(data))
        report(OL$Error, "Beta distribution fit requires a vector of data")
        
    if (is.null(weights))
        weights <- rep(1, length(data))
    else if (length(weights) != length(data))
        report(OL$Error, "Data and weight vectors must have the same length")
    
    data <- data[!is.na(weights)]
    weights <- weights[!is.na(weights)]
    
    if (is.null(alpha) && (beta == 1))
        alpha <- (-sum(weights)) / sum(weights*log(data))
    
    result <- list(alpha=alpha, beta=beta)
    class(result) <- "betaDistribution"
    return (result)
}

evaluateBetaDistribution <- function (x, params, log = FALSE)
{
    if (!is(params, "betaDistribution"))
        report(OL$Error, "The specified object does not describe a beta distribution")
    return (dbeta(x, params$alpha, params$beta, ncp=0, log=log))
}

fitRegularisedBetaDistribution <- function (data, alpha = NULL, beta = 1, lambda = 1, alphaOffset = 0, weights = NULL)
{
    if (is.null(weights))
        weightSum <- 1
    else
        weightSum <- sum(weights, na.rm=TRUE)
    
    result <- fitBetaDistribution(data, alpha, beta, weights)
    
    # NB: The expression used to calculate alpha here is not self-normalising,
    # so the relative scales of "weights" and "lambda" matter
    # This is required to allow for multiple data points from a single subject,
    # but care must be taken if using this function for other purposes
    if (!is.null(lambda) && is.null(alpha) && (beta == 1))
        result$alpha <- (result$alpha*weightSum) / (result$alpha*lambda + weightSum) + alphaOffset
    
    return (result)
}

fitGaussianDistribution <- function (data, mu = NULL, sigma = NULL)
{
    if (!is.vector(data))
        report(OL$Error, "Gaussian distribution fit requires a vector of data")
    if (length(data) == 0)
        report(OL$Error, "Data vector is empty!")
    
    if (is.null(mu))
        mu <- mean(data)
    if (is.null(sigma))
        sigma <- sqrt(sum((data - mu)^2) / length(data))
	
    result <- list(mu=mu, sigma=sigma)
    class(result) <- "gaussianDistribution"
    return (result)
}

evaluateGaussianDistribution <- function (x, params, log = FALSE)
{
    if (!is(params, "gaussianDistribution"))
        report(OL$Error, "The specified object does not describe a Gaussian distribution")
    return (dnorm(x, mean=params$mu, sd=params$sigma, log=log))
}

fitMultinomialDistribution <- function (data, const = 0, values = NULL, weights = NULL)
{
    if (!is.vector(data))
        report(OL$Error, "Multinomial distribution fit requires a vector of data")
    
    if (is.null(weights))
        weights <- rep(1, length(data))
    else if (length(weights) != length(data))
        report(OL$Error, "Data and weight vectors must have the same length")
    
    data <- data[!is.na(weights)]
    weights <- weights[!is.na(weights)]
    
    hist <- tapply(weights, factor(data), "sum")
    dataValues <- as.numeric(names(hist))
    
    if (is.null(values))
    {
        values <- dataValues
        counts <- as.vector(hist) + const
    }
    else
    {
        counts <- rep(0, length(values))
        locs <- match(dataValues, values)
        if (sum(is.na(locs)) != 0)
            report(OL$Error, "Some multinomial fit data are not amongst the specified allowable values")
        counts[locs] <- as.vector(hist)
        counts <- counts + const
    }
    
    probs <- counts / sum(counts)
    result <- list(probs=probs, values=values)
    class(result) <- "multinomialDistribution"
    return (result)
}

evaluateMultinomialDistribution <- function (x, params, log = FALSE)
{
    if (!is(params, "multinomialDistribution"))
        report(OL$Error, "The specified object does not describe a multinomial distribution")
    
    if (is.na(x))
        return (NA)
    if (!is.numeric(x))
        report(OL$Error, "Multinomial data must be numeric")
    
    if (length(x) == length(params$probs))
        return (dmultinom(x, prob=params$probs, log=log))
    else if (length(x) == 1)
    {
        y <- rep(0, length(params$probs))
        loc <- which(params$values == x)
        if (length(loc) != 1)
        {
            loc <- which.min(abs(params$values - x))
            report(OL$Warning, "The specified value (", x, ") is not valid for this distribution; treating as ", params$values[loc])
        }
        
        y[loc] <- 1
        return (dmultinom(y, size=1, prob=params$probs, log=log))
    }
    else
        report(OL$Error, "Multinomial data must be specified as a single number or full vector of frequencies")
}
