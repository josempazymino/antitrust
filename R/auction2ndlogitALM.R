setClass(
         Class   = "Auction2ndLogitALM",
         contains="Auction2ndLogit",
         representation=representation(
          parmsStart="numeric"
         ),
         prototype=prototype(
         normIndex         =  NA,
         control.slopes = list( 
           factr = 1e7 
         )
         ),

         validity=function(object){



             nMargins  <- length(object@margins[!is.na(object@margins)])

             if(nMargins<2){stop("At least 2 elements of 'margins' must not be NA in order to calibrate demand parameters")}

             if(object@shareInside!=1){
                 stop(" sum of 'shares' must equal 1")
             }

              if(length(object@parmsStart)!=2){
                 stop("'parmsStart' must a vector of length 2")
                 }
         }
         )

setMethod(
          f= "calcSlopes",
          signature= "Auction2ndLogitALM",
          definition=function(object){

              ## Uncover Demand Coefficents

              ownerPre     <-  object@ownerPre
              shares       <-  object@shares
              margins      <-  object@margins
             

              nprods <- length(object@shares)

              
              minD <- function(theta){

                  alpha <- theta[1]
                  sOut  <- theta[2]

                  probs <- shares * (1 - sOut)
                  
                  firmShares <- drop(ownerPre %*% probs)
                  
                  
                  measure <- 1 - (log((1-firmShares))/( alpha * firmShares))/margins
                  
                  measure <- sum((measure)^2,na.rm=TRUE)

                  return(measure)
              }

               ## Constrain optimizer to look  alpha <0,  0 < sOut < 1
              lowerB <- c(-Inf,0)
              upperB <- c(-1e-10,.9999999999)

              minTheta <- optim(object@parmsStart,minD,
                                method="L-BFGS-B",
                                lower= lowerB,upper=upperB,
                                control=object@control.slopes)$par

              if(isTRUE(all.equal(minTheta[2],0,check.names=FALSE))){stop("ERROR: Estimated outside share is close to 0. Use `auction2nd.logit' function instead")}
              
              
              meanval <- log(shares * (1 - minTheta[2])) - log(minTheta[2]) 

              names(meanval)   <- object@labels


              object@slopes      <- list(alpha=minTheta[1],meanval=meanval)
              object@shareInside <- 1-minTheta[2]

              return(object)

          }

          )



auction2nd.logit.alm <- function(prices,shares,margins,
                             ownerPre,ownerPost,
                             mcDelta=rep(0,length(prices)),
                             subset=rep(TRUE,length(prices)),
                             mcDeltaOutside=0,
                             parmsStart,
                             control.slopes,
                             control.equ,
                             labels=paste("Prod",1:length(prices),sep="")
){
  
  
  if(missing(parmsStart)){
    parmsStart <- rep(.1,2)
    nm <- which(!is.na(margins))[1] 
    parmsStart[1] <- 1/(margins[nm]*log(1-shares[nm])) #ballpark alpha for starting values
  }
  
  
  if(missing(prices)){prices <- rep(NA_integer_, length(shares))}
  ## Create Auction2ndLogitALM  container to store relevant data
  result <- new("Auction2ndLogitALM",prices=prices, shares=shares,
                margins=margins,
                ownerPre=ownerPre,
                ownerPost=ownerPost,
                mcDelta=mcDelta,
                subset=subset,
                priceOutside=mcDeltaOutside,
                shareInside=ifelse(isTRUE(all.equal(sum(shares),1,check.names=FALSE)),1,sum(shares)),
                priceStart=rep(0,length(shares)),
                parmsStart = parmsStart,
                labels=labels,
                cls = "Auction2ndLogit")
  
  if(!missing(control.slopes)){
    result@control.slopes <- control.slopes
  }
  if(!missing(control.equ)){
    result@control.equ <- control.equ
  }
  ## Convert ownership vectors to ownership matrices
  result@ownerPre  <- ownerToMatrix(result,TRUE)
  result@ownerPost <- ownerToMatrix(result,FALSE)
  
  ## Calculate Demand Slope Coefficients
  result <- calcSlopes(result)
  
  ## Calculate marginal cost
  result@mcPre <-  calcMC(result,TRUE)
  result@mcPost <- calcMC(result,FALSE)
  
  ## Solve Non-Linear System for Price Changes
  result@pricePre  <- calcPrices(result,preMerger=TRUE)
  result@pricePost <- calcPrices(result,preMerger=FALSE,subset=subset)
  
  return(result)
  
}
