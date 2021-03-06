# ProcessNewRamp.R - is ONLY FOR DEVELOPERS to generate data required for Ramp internal functions(findCluster(), fisherTest()) to perform calculations.

#' Find table of analyte has pathway from given pathway IDs
#' Aggregate ramp Id to ramp pathway Id
#' GC is C or G
#' @param pathwayRampId a vector of ramp Pathway ID
#' @param GC the analytes type that is either "C" for compound or "G" for gene
#' @param n minimum analytes of which pathway to considered computing overlap
#' @param username a string that specifies name of MySQL database
#' @param dbname a string that specifies database name of MySQL database
#' @param conpass a string that specifies password for database connection
#' @param host a string that specifes host for database connection
#' @return A list with pathway rampID as name, a vector of analytes from this pathway as content.

findAnalyteHasPathway <- function(pathwayRampId,GC = "C",n = 10,
                                  username ='root',
                                  dbname = 'ramp',
                                  conpass,
                                  host = 'localhost'){
  con <- DBI::dbConnect(RMySQL::MySQL(),
                        user = username,
                        dbname=dbname,
                        password = conpass,
                        host = host)
  on.exit(DBI::dbDisconnect(con))
  p_id <- unique(pathwayRampId)
  p_id <- sapply(p_id,shQuote)
  p_id <- paste(p_id,collapse = ",")
  query <-paste0("select * from analytehaspathway where pathwayRampId in (",
                 p_id,
                 ");")
  df <- DBI::dbGetQuery(con,
                        query)
  if(GC == 'both'){
    df2 <- stats::aggregate(df$rampId,list(df$pathwayRampId),FUN = function(x){
      if(length(x) >= n){
        paste(x,collapse = ',')
      } else{
        x <- 0
      }
    })
  }
  else if (GC %in% c('G','C')){
    df2 <- stats::aggregate(df$rampId,list(df$pathwayRampId),FUN = function(x){
      x <- x[grepl(paste0("RAMP_",GC,"_"),x)]
      if(length(x) >= n ){
        paste(x,collapse = ",")
      } else {
        x <- 0
      }
    })
  }
  fdf <- df2[df2$x!=0,]
  fdf2 <- data.frame(fdf[,-1],row.names = fdf[,1],stringsAsFactors = F)
  df.list <- stats::setNames(split(fdf2, seq(nrow(fdf2))), rownames(fdf2))
  df.list <- lapply(df.list,FUN = function(x){
    text <- x[[1]]
    text <- strsplit(text,split = ",")
  })
  df.list <- lapply(df.list,unlist)
}
#'Compute overlaping matrix based on given list return by findAnalyteHasPathway()
#'
#'@param pathwayid a vector that has all ramp pathway id in the pathwaysWithAnalytes
#'@param pathwaysWithAnalytes a list that has pathways ramp Id as name, analytes (ramp compound id only
#' or gene id only or both) as content. Return by findAnalyteHasPathway
#' @param overlapmethod must be in c('balanced','weighted') to determine which way to calculate this matrix
#' @return the overlap matrix that has the overlap
compute_overlap_matrix <- function(pathwayid,
                                   pathwaysWithAnalytes,
                                   overlapmethod){
  if(!(overlapmethod %in% c('balanced','weighted')))
    stop('Wrong option for the input')
  analyte_result <- matrix(NA,nrow = length(pathwayid),ncol = length(pathwayid))
  colnames(analyte_result) <- pathwayid
  rownames(analyte_result) <- pathwayid
  # First method compute intersection over the union
  if(overlapmethod == 'balanced'){
    for(i in 1:length(pathwayid)){
      id <- pathwayid[i]
      cid <- pathwaysWithAnalytes[[i]]
      for (j in 1:length(pathwayid)) {
        if(is.na(analyte_result[i,j])){
          if(i==j){
            analyte_result[i,j] <- 1
          }else{
            cid2 <- pathwaysWithAnalytes[[j]]
            shared_metabolite <- unique(intersect(cid,cid2))
            total <- unique(union(cid,cid2))
            analyte_result[i,j] <- length(shared_metabolite)/length(total)
            print(analyte_result[i,j])
            if(is.na(analyte_result[j,i])){
              analyte_result[j,i] <- analyte_result[i,j]
            }
          }
        }
        print(paste("Compute for ",i,",",j))
      }
    }
  }else if (overlapmethod == 'weighted'){
    # second method
    for(i in 1:length(pathwayid)){
      id <- pathwayid[i]
      cid <- pathwaysWithAnalytes[[i]]
      for (j in 1:length(pathwayid)) {
        if(is.na(analyte_result[i,j])){
          if(i==j){
            analyte_result[i,j] <- 1
          }else{
            cid2 <- pathwaysWithAnalytes[[j]]
            shared_metabolite <- unique(intersect(cid,cid2))
            total <- unique(union(cid,cid2))
            analyte_result[i,j] <- length(shared_metabolite)/length(unique(cid2))
            print(analyte_result[i,j])
            if(is.na(analyte_result[j,i])){
              analyte_result[j,i] <- length(shared_metabolite)/length(unique(cid))
            }
          }
        }
        print(paste("Compute for ",i,",",j))
      }
    }
  }

  return(analyte_result)
}
#' Update the overlap matrix for store in the shiny app directory
#'
#' @param min_analyte a int that specifies the minimum of analytes the
#' pathway should have to be considered compute for overlap matrix
#' @param overlapmethod a string that specifies the way to compute overlap matrix,
#' must be 'balanced' or 'weighted'
#' @param together a boolean value to compute overlap matrix for
#' gene/metabolites separatly or together
#' @param username a string that specifies name of MySQL database
#' @param dbname a string that specifies database name of MySQL database
#' @param conpass a string that specifies password for database connection
#' @param host a string that specifes host for database connection
updateOverlapMatrix <- function(min_analyte,overlapmethod,together,conpass,
                                host = 'localhost',dbname = 'ramp',
                                username = 'root'){
  if(!together){
    con <- DBI::dbConnect(RMySQL::MySQL(),
                          user = username,
                          dbname= dbname,
                          password = conpass,
                          host = host)
    on.exit(DBI::dbDisconnect(con))
    pathways<- DBI::dbGetQuery(con,'select * from pathway;')
    source <- DBI::dbGetQuery(con,'select * from source;')


    # dbname <- unique(pathways$type)

    # pathwayInHmdb <- pathways[pathways$type == 'hmdb',]
    pathwayInKegg <- pathways[pathways$type == 'kegg',]
    pathwayInWiki <- pathways[pathways$type == 'wiki',]
    pathwayInReac <- pathways[pathways$type == 'reactome',]

    # define the minimum metabolites/genes


    # Store Compound Ids in List
    # listOfHmdbC <- findAnalyteHasPathway(pathwayInHmdb$pathwayRampId)
    listOfKeggC <- findAnalyteHasPathway(pathwayInKegg$pathwayRampId,n = min_analyte,host = host,
                                         conpass = conpass, dbname = dbname)

    listOfWikiC <- findAnalyteHasPathway(pathwayInWiki$pathwayRampId,n = min_analyte,host = host,
                                         conpass = conpass, dbname = dbname)
    listOfReacC <- findAnalyteHasPathway(pathwayInReac$pathwayRampId,n = min_analyte,
                                         conpass = conpass, dbname = dbname,host = host)
    # Store Gene Ids in List
    # listOfHmdbG <- findAnalyteHasPathway(pathwayInHmdb$pathwayRampId,GC="G")
    listOfKeggG <- findAnalyteHasPathway(pathwayInKegg$pathwayRampId,GC="G",n = min_analyte,
                                         conpass = conpass, dbname = dbname,host = host)
    listOfWikiG <- findAnalyteHasPathway(pathwayInWiki$pathwayRampId,GC="G",n = min_analyte,
                                         conpass = conpass, dbname = dbname,host = host)
    listOfReacG <- findAnalyteHasPathway(pathwayInReac$pathwayRampId,GC="G",n = min_analyte,
                                         conpass = conpass, dbname = dbname,host = host)
    # Setup minimum number of analytes that will be considered

    # May need to filter out that pathway that has less than 5 metabolites
    # Output to a matrix
    # In order of HMDB Kegg Wiki Reac

    pathwayid <- c(#names(listOfHmdbC),
      names(listOfKeggC),
      names(listOfWikiC),
      names(listOfReacC))

    pathToanalC <- do.call(c,list(#listOfHmdbC,
      listOfKeggC,
      listOfWikiC,
      listOfReacC))

    if(overlapmethod == 'balanced' ){
      metabolite_result <- compute_overlap_matrix(pathwayid = pathwayid,
                                                  pathwaysWithAnalytes =  pathToanalC,
                                                  overlapmethod = 'balanced')
    }else if(overlapmethod == 'weighted'){
      metabolite_result <- compute_overlap_matrix(pathwayid = pathwayid,
                                                  pathwaysWithAnalytes = pathToanalC,
                                                  overlapmethod = 'weighted')
    }

    # Output to a matrix
    ### Part for genes ...
    pathwayidG <- c(#names(listOfHmdbG),
      names(listOfKeggG),
      names(listOfWikiG),
      names(listOfReacG))



    pathToanalG <- do.call(c,list(#listOfHmdbG,
      listOfKeggG,
      listOfWikiG,
      listOfReacG))
    # compute for matrix
    if(overlapmethod == 'balanced' ){
      gene_result <- compute_overlap_matrix(pathwayid = pathwayidG,pathToanalG,overlapmethod = 'balanced')
    } else if(overlapmethod == 'weighted' ){
      gene_result <- compute_overlap_matrix(pathwayid = pathwayidG,pathToanalG,overlapmethod = 'weighted')
    }
    return(list(
      metabolite = metabolite_result,
      gene = gene_result
    ))
  } else if(together){
    con <- DBI::dbConnect(RMySQL::MySQL(),
                          user = username,
                          dbname=dbname,
                          password = conpass,
                          host = host)

    pathways<- DBI::dbGetQuery(con,'select * from pathway;')



    # dbname <- unique(pathways$type)

    # pathwayInHmdb <- pathways[pathways$type == 'hmdb',]
    pathwayInKegg <- pathways[pathways$type == 'kegg',]
    pathwayInWiki <- pathways[pathways$type == 'wiki',]
    pathwayInReac <- pathways[pathways$type == 'reactome',]

    # double minimum number of analytes in the pathway
    min_analyte <- min_analyte * 2

    # Store Compound Ids in List
    # listOfHmdbC <- findAnalyteHasPathway(pathwayInHmdb$pathwayRampId)
    # use both to save metabolites/genes in the list

    listOfKegg <- findAnalyteHasPathway(pathwayInKegg$pathwayRampId,GC = 'both',n = min_analyte,
                                        host = host,
                                        conpass = conpass, dbname = dbname)
    listOfWiki <- findAnalyteHasPathway(pathwayInWiki$pathwayRampId,GC = 'both',n = min_analyte,
                                        host = host,
                                        conpass = conpass, dbname = dbname)
    listOfReac <- findAnalyteHasPathway(pathwayInReac$pathwayRampId,GC = 'both',n = min_analyte,
                                        host = host,
                                        conpass = conpass, dbname = dbname)
    # Append all pathways id together

    pathwayid <- c(#names(listOfHmdbC),
      names(listOfKegg),
      names(listOfWiki),
      names(listOfReac))

    pathToanal <- do.call(c,list(#listOfHmdbC,
      listOfKegg,
      listOfWiki,
      listOfReac))
    if(overlapmethod == 'balanced'){
      analyte_result <- compute_overlap_matrix(pathwayid = pathwayid,
                                               pathwaysWithAnalytes =  pathToanal,
                                               overlapmethod = 'balanced')
    } else if(overlapmethod == 'weighted'){
      analyte_result <- compute_overlap_matrix(pathwayid = pathwayid,
                                               pathwaysWithAnalytes =  pathToanal,
                                               overlapmethod = 'weighted')
    }
    return(analyte_result)
  }
}

#' Update and save the overlap matrices based on current version of RaMP
#'
#' @param method a string that specifies algorithm to compute overlap matrix
#' should be 'balanced' or 'weighted'
#' @param all a string that specifies which matrices to compute, should be in
#' 'all','analyte'
#' @param conpass password for database access (string)
#' @param dbname name of the mysql database (default is "ramp")
#' @param username username for database access (default is "root")
#' @param host host name for database access (default is "localhost")
#' @export
updateOverlapMatrices <- function(method,all,
                                  conpass,
                                  host = 'localhost',dbname = 'ramp',
                                  username = 'root'){
  if(!(method %in% c('balanced','weighted'))){
    stop('Wrong input for argument method')
  }
  if(!(all %in%c('all','metabolite','gene','analyte'))){
    stop('Wrong input for argument all')
  }

  if(all == 'all'){
    result <- updateOverlapMatrix(min_analyte = 5,overlapmethod = 'balanced',together = T)
    save(result[[1]],system.file(package = "RaMP",... = "extdata/metabolites_overlap_matrix.RData"))
    save(result[[2]],system.file(package = "RaMP",... = "extdata/genes_overlap_matrix.RData"))
  } else if(all == 'analyte'){
    result <- updateOverlapMatrix(min_analyte = 5,overlapmethod = 'balanced',together = F)
    save(result,system.file(package = "RaMP",... = "extdata/analytes_overlap_matrix.RData"))

  }
}

#' processData function generates pathway RampId frequency (gene or metabolite) based on pathway source (hmdb,kegg,reactome,wiki)
#'@param username a string that specifies name of MySQL database
#'@param dbname a string that specifies database name of MySQL database
#'@param conpass a string that specifies password for database connection
#'@param host a string that specifes host for database connection
#'@return R object (FT_data.Rdata) with dataframes (hmdb_metab,hmdb_gene,kegg_gene,kegg_metab,reactome_gene,reactome_metab,wiki_gene,wiki_metab)
processData <- function(conpass,
                        dbname='ramp',username='root',
                        host = 'localhost') {

  if(is.null(conpass)) {
    stop("Please define the password for the mysql connection")
  }

  # get all rows form analytehaspathway
  query <- "select * from analytehaspathway"
  con <- DBI::dbConnect(RMySQL::MySQL(), user = username,
                        password = conpass,
                        dbname = dbname,
                        host = host)

  allRampIds <- DBI::dbGetQuery(con,query)


  if(is.null(allRampIds)) {

    stop("Data doesn't exist")

  } else {


    # length(unique(allRampIds$pathwayRampId))
    # total unique pathwayRampIDs - 51,526

    # data frames for metabolites with pathawayRampID, Freq based  on Source(kegg, reactome, wiki, hmdb)

    allRampId_C <- allRampIds[grep("RAMP_C", allRampIds$rampId), ]
    unique_allRampId_C <- unique(allRampId_C[,c("rampId", "pathwayRampId")])
    unique_pathwayRampId_source <- unique(allRampId_C[,c("pathwayRampId", "pathwaySource")])

    # length(unique_pathwayRampId_source$pathwayRampId) - 36,039

    freq_unique_allRampId_C <- as.data.frame(table(unique_allRampId_C[,"pathwayRampId"]))

    # length of total RAMP_C pathwayRampIDs - 36,039

    names(freq_unique_allRampId_C)[1] = 'pathwayRampId'
    merge_Pathwayfreq_source <- merge(freq_unique_allRampId_C, unique_pathwayRampId_source, by="pathwayRampId")

    # subset data based on source -  kegg, reactome, wiki, hmdb

    kegg_metab <- subset(merge_Pathwayfreq_source, merge_Pathwayfreq_source$pathwaySource == "kegg")
    #length(kegg_metab$pathwayRampId) - 264
    reactome_metab <- subset(merge_Pathwayfreq_source, merge_Pathwayfreq_source$pathwaySource == "reactome")
    #length(reactome_metab$pathwayRampId) - 1866
    wiki_metab <- subset(merge_Pathwayfreq_source, merge_Pathwayfreq_source$pathwaySource == "wiki")
    #length(wiki_metab$pathwayRampId) - 213
    hmdb_metab <- subset(merge_Pathwayfreq_source, merge_Pathwayfreq_source$pathwaySource == "hmdb")
    #length(hmdb_metab$pathwayRampId) - 33,696



    # data frames for Genes with pathawayRampID, Freq based  on Source(kegg, reactome, wiki, hmdb)

    allRampId_G <- allRampIds[grep("RAMP_G", allRampIds$rampId), ]
    unique_allRampId_G <- unique(allRampId_G[,c("rampId", "pathwayRampId")])
    unique_pathwayG_source <- unique(allRampId_G[,c("pathwayRampId", "pathwaySource")])

    # length(unique(unique_pathwayG_source$pathwayRampId)) - 51,461

    freq_unique_allRampId_G <- as.data.frame(table(unique_allRampId_G[,"pathwayRampId"]))

    # length of total RAMP_G pathwayRampIDs - 51,461

    names(freq_unique_allRampId_G)[1] = 'pathwayRampId'
    merge_PathwayG_source <- merge(freq_unique_allRampId_G, unique_pathwayG_source, by="pathwayRampId")

    # subset data based on source -  kegg, reactome, wiki, hmdb

    kegg_gene <- subset(merge_PathwayG_source, merge_PathwayG_source$pathwaySource == "kegg")
    #length(kegg_gene$pathwayRampId) - 323
    reactome_gene <- subset(merge_PathwayG_source, merge_PathwayG_source$pathwaySource == "reactome")
    #length(reactome_gene$pathwayRampId) - 2155
    wiki_gene <- subset(merge_PathwayG_source, merge_PathwayG_source$pathwaySource == "wiki")
    #length(wiki_gene$pathwayRampId) - 408
    hmdb_gene <- subset(merge_PathwayG_source, merge_PathwayG_source$pathwaySource == "hmdb")
    #length(hmdb_gene$pathwayRampId) - 48575

    save(kegg_metab,
         reactome_metab,
         wiki_metab,
         hmdb_metab,
         kegg_gene,
         reactome_gene,
         wiki_gene,
         hmdb_gene,
         file = paste0(system.file(package = "RaMP"),"/extdata/FT_data.Rdata"))
  }
}

#' sysdataObject() generates sysdata.rda object from exdata dir (genes_overlap_matrix.RData,metabolites_overlap_matrix.RData,analytes_overlap_matrix.RData,FT_data.Rdata)
#' the output is availble only for RaMP internal functions (runFisherTest() & findCluster())
#' @return sysdata.rda object in R directory with 3 Overlap Matrices (genes_result, metabolites_result, analyte_result) & dataframes generated from processData function.

sysdataObject <- function() {

  load(system.file(package = "RaMP",... = "extdata/genes_overlap_matrix.RData"))
  load(system.file(package = "RaMP",... = "extdata/metabolites_overlap_matrix.RData"))
  load(system.file(package = "RaMP",... = "extdata/analytes_overlap_matrix.RData"))
  load(system.file(package = "RaMP",... = "extdata/FT_data.Rdata"))
  stopifnot(is.matrix(genes_result),
            is.matrix(metabolites_result),
            is.matrix(analyte_result),
            is.data.frame(hmdb_gene),
            is.data.frame(hmdb_metab),
            is.data.frame(kegg_gene),
            is.data.frame(kegg_metab),
            is.data.frame(reactome_gene),
            is.data.frame(reactome_metab),
            is.data.frame(wiki_gene),
            is.data.frame(wiki_metab))

  # uncomment devtools::use_data function to create sysdata.Rda object
  # devtools::use_data(genes_result,
  #                    metabolites_result,
  #                    analyte_result,
  #                    hmdb_gene,
  #                    hmdb_metab,
  #                    kegg_gene,
  #                    kegg_metab,
  #                    reactome_gene,
  #                    reactome_metab,
  #                    wiki_gene,
  #                    wiki_metab,
  #                    overwrite = TRUE,
  #                    internal = TRUE)

}

# Steps to test dev package
# step1: remove RaMP package in R Libraray:
# In R console - find package path:
# >system.file(package="RaMP",mustWork=TRUE)
# In terminal:
# $cd [packagePath]
# $rm -r RaMP
# step2: go to RaMP-DB dir
# step3: open R console at RaMP-DB dir to build RaMP package
# In R console:
# >library(devtools)
# >devtools::install()
# >library(RaMP)
# step5: Access RaMP library sysdata.rda object data
# In R console:
# >library(RaMP)
# >RaMP:::
