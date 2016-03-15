ploughExperiment <- function (scriptName, configFiles, variables, tractorFlags, tractorOptions, useGridEngine, crossApply, queueName, qsubOptions, parallelisationFactor, debug)
{
    crossApply <- isTRUE(crossApply == 1)
    useGridEngine <- isTRUE(useGridEngine == 1)
    debug <- isTRUE(debug == 1)
    setOutputLevel(ifelse(debug, OL$Debug, OL$Info))
    
    config <- readYaml(configFiles)
    variableLengths <- sapply(config, length)
    
    variables <- splitAndConvertString(variables, ",", fixed=TRUE)
    if (length(variables) == 0 || all(variables == ""))
        variables <- names(config)[variableLengths > 1]
    else if (!all(variables %in% names(config)))
        report(OL$Error, "Specified variable(s) #{implode(variables[!(variables %in% names(config))],sep=', ',finalSep=' and ')} are not mentioned in the config files")
    
    usingParallel <- FALSE
    if (isValidAs(parallelisationFactor,"integer") && as.integer(parallelisationFactor) > 1)
    {
        if (useGridEngine)
            report(OL$Warning, "Parallelisation factor will be ignored when using the grid engine")
        else if (system.file(package="parallel") != "")
        {
            library(parallel)
            options(mc.cores=as.integer(parallelisationFactor))
            usingParallel <- TRUE
        }
        else
            report(OL$Warning, "The \"parallel\" package is not installed - code will not be parallelised")
    }
    
    if (crossApply)
    {
        n <- prod(variableLengths[variables])
        data <- as.data.frame(expand.grid(config[variables], stringsAsFactors=FALSE), stringsAsFactors=FALSE)
    }
    else
    {
        n <- max(variableLengths[variables])
        data <- as.data.frame(lapply(config[variables], rep, length.out=n), stringsAsFactors=FALSE)
    }
    
    report(OL$Info, "Scheduling #{n} jobs")
    
    tractorPath <- file.path(Sys.getenv("TRACTOR_HOME"), "bin", "tractor")
    debugFlag <- ifelse(debug, "-d", "")
    
    buildArgs <- function (i)
    {
        currentFlags <- ore.subst("(?<!\\\\)\\%(\\w+)", function(match) data[i,groups(match)], tractorFlags, all=TRUE)
        currentFlags <- ore.subst("(?<!\\\\)\\%\\%", as.character(i), currentFlags, all=TRUE)
        currentOptions <- ore.subst("(?<!\\\\)\\%(\\w+)", function(match) data[i,groups(match)], tractorOptions, all=TRUE)
        currentOptions <- ore.subst("(?<!\\\\)\\%\\%", as.character(i), currentOptions, all=TRUE)
        return (es("#{debugFlag} #{currentFlags} #{scriptName} #{currentOptions}"))
    }
    
    if (useGridEngine)
    {
        for (i in seq_len(n))
        {
            tempDir <- expandFileName("sgetmp")
            if (file.exists(tempDir))
                unlink(tempDir, recursive=TRUE)
            dir.create(file.path(tempDir,"log"), recursive=TRUE)
            
            qsubScriptFile <- file.path(tempDir, "script")
            qsubScript <- c("#!/bin/sh",
                            "#$ -S /bin/bash",
                            es("#{tractorPath} -c #{currentFile} #{buildArgs(i)}"))
            writeLines(qsubScript, qsubScriptFile)
            execute("chmod", es("+x #{qsubScriptFile}"))
            
            currentFile <- file.path(tempDir, es("config.#{i}.yaml"))
            writeYaml(as.list(data[i,,drop=FALSE]), currentFile, capitaliseLabels=FALSE)
            
            queueOption <- ifelse(queueName=="", "", es("-q #{queueName}"))
            qsubArgs <- es("-terse -V -wd #{path.expand(getwd())} #{queueOption} -N #{scriptName} -o #{file.path(tempDir,'log')} -e /dev/null -t 1-#{n} #{qsubOptions} #{qsubScriptFile}")
            result <- execute("qsub", qsubArgs, intern=TRUE)
            jobNumber <- as.numeric(ore.match("^(\\d+)\\.?.*$", result)[,1])
            jobNumber <- jobNumber[!is.na(jobNumber)]
            report(OL$Verbose, "Job number for index #{i} is #{jobNumber}")
        }
    }
    else
    {
        parallelApply(seq_len(n), function(i) {
            currentFile <- threadSafeTempFile()
            writeYaml(as.list(data[i,,drop=FALSE]), currentFile, capitaliseLabels=FALSE)
            
            execute(tractorPath, es("-c #{currentFile} #{buildArgs(i)}"))
            
            unlink(currentFile)
        })
    }
    
    invisible(NULL)
}