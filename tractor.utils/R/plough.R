ploughExperiment <- function (scriptName, configFiles, variables, tractorFlags, tractorOptions, useGridEngine, crossApply, queueName, qsubOptions, parallelisationFactor, debug)
{
    crossApply <- isTRUE(crossApply == 1)
    useGridEngine <- isTRUE(useGridEngine == 1)
    setOutputLevel(ifelse(isTRUE(debug==1), OL$Debug, OL$Info))
    
    config <- readYaml(configFiles)
    variableLengths <- sapply(config, length)
    
    variables <- splitAndConvertString(variables, ",", fixed=TRUE)
    variables <- variables[variables != ""]
    if (length(variables) == 0)
        variables <- names(config)[variableLengths > 1]
    else if (!all(variables %in% names(config)))
        report(OL$Error, "Specified variable(s) #{implode(variables[!(variables %in% names(config))],sep=', ',finalSep=' and ')} are not mentioned in the config files")
    
    report(OL$Info, "Looping over variable(s) #{implode(variables,sep=', ',finalSep=' and ')}")
    
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
    
    for (name in setdiff(names(config), c(variables,"")))
        data[[name]] <- config[[name]]
    
    report(OL$Info, "Scheduling #{n} jobs")
    
    tractorPath <- file.path(Sys.getenv("TRACTOR_HOME"), "bin", "tractor")
    
    buildArgs <- function (i)
    {
        currentFlags <- ore.subst("(?<!\\\\)\\%([A-Za-z]+)", function(match) data[i,groups(match)], tractorFlags, all=TRUE)
        currentFlags <- ore.subst("(?<!\\\\)\\%\\%", as.character(i), currentFlags, all=TRUE)
        currentOptions <- ore.subst("(?<!\\\\)\\%([A-Za-z]+)", function(match) data[i,groups(match)], tractorOptions, all=TRUE)
        currentOptions <- ore.subst("(?<!\\\\)\\%\\%", as.character(i), currentOptions, all=TRUE)
        return (es("#{currentFlags} #{scriptName} #{currentOptions}"))
    }
    
    if (useGridEngine)
    {
        tempDir <- expandFileName("getmp")
        if (file.exists(tempDir))
            unlink(tempDir, recursive=TRUE)
        dir.create(file.path(tempDir,"log"), recursive=TRUE)
        
        args <- sapply(seq_len(n), buildArgs)
        argsFile <- file.path(tempDir, "args")
        writeLines(args, argsFile)
        
        configPrefix <- file.path(tempDir, "config")
        for (i in seq_len(n))
            writeYaml(as.list(data[i,,drop=FALSE]), es("#{configPrefix}.#{i}.yaml"))
        
        qsubScriptFile <- file.path(tempDir, "script")
        qsubScript <- c("#!/bin/sh",
                        "#$ -S /bin/bash",
                        es("TRACTOR_PLOUGH_ID=${SGE_TASK_ID}"),
                        es("TRACTOR_ARGS=`sed \"${SGE_TASK_ID}q;d\" #{argsFile}`"),
                        es("#{tractorPath} -c #{configPrefix}.${SGE_TASK_ID}.yaml ${TRACTOR_ARGS}"))
        writeLines(qsubScript, qsubScriptFile)
        execute("chmod", es("+x #{qsubScriptFile}"))
        
        queueOption <- ifelse(queueName=="", "", es("-q #{queueName}"))
        qsubArgs <- es("-terse -V -wd #{path.expand(getwd())} #{queueOption} -N #{scriptName} -o #{file.path(tempDir,'log')} -e /dev/null -t 1-#{n} #{qsubOptions} #{qsubScriptFile}")
        result <- execute("qsub", qsubArgs, stdout=TRUE)
        jobNumber <- as.numeric(ore.search("^(\\d+)\\.?.*$", result)[,1])
        jobNumber <- jobNumber[!is.na(jobNumber)]
        report(OL$Info, "Job number is #{jobNumber}")
    }
    else
    {
        parallelApply(seq_len(n), function(i) {
            currentFile <- threadSafeTempFile()
            writeYaml(as.list(data[i,,drop=FALSE]), currentFile)
            
            execute(tractorPath, es("-c #{currentFile} #{buildArgs(i)}"), env=es("TRACTOR_PLOUGH_ID=#{i}"))
            
            unlink(currentFile)
        })
    }
    
    invisible(NULL)
}
