setClass(
         Class   = "LogitALM",
         contains="Logit",
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

             if(nMargins<2 && is.na(object@mktElast)){stop("At least 2 elements of 'margins' must not be NA in order to calibrate demand parameters")}

             if(object@shareInside != 1){
               stop(" sum of 'shares' must equal 1")
             }
             
             
              if(length(object@parmsStart)!=2){
                 stop("'parmsStart' must a vector of length 2")
                 }
         }
         )

setMethod(
          f= "calcSlopes",
          signature= "LogitALM",
          definition=function(object){

              ## Uncover Demand Coefficents

              ownerPre     <-  object@ownerPre
              shares       <-  object@shares
              margins      <-  object@margins
              prices       <-  object@prices
              mktElast     <-  object@mktElast 
              priceOutside <- object@priceOutside
              
              avgPrice <- sum(shares*prices)

              nprods <- length(object@shares)

              ##identify which products have enough margin information
              ##  to impute Bertrand margins
              #isMargin    <- matrix(margins,nrow=nprods,ncol=nprods,byrow=TRUE)
              #isMargin[ownerPre==0]=0
              #isMargin    <- !is.na(rowSums(isMargin))

              minD <- function(theta){

                  alpha <- theta[1]
                  sOut  <- theta[2]

                  probs <- shares * (1 - sOut)
                  elast <- -alpha *  matrix(prices * probs,ncol=nprods,nrow=nprods)
                  diag(elast) <- alpha*prices + diag(elast)

                  revenues <- probs * prices
                  marginsCand <- -1 * as.vector(MASS::ginv(elast * ownerPre) %*% (revenues * diag(ownerPre))) / revenues
                  
                  m1 <- margins - marginsCand
                  m2 <- mktElast/(avgPrice * alpha ) - sOut   
                  measure <- sum(c(m1,m2)^2,na.rm=TRUE)

                  #elast      <-   elast[isMargin,isMargin]
                  #revenues   <-   revenues[isMargin]
                  #ownerPre   <-   ownerPre[isMargin,isMargin]
                  #margins    <-   margins[isMargin]

                  #marginsCand <- -1 * as.vector(MASS::ginv(elasticity * ownerPre) %*% (revenues * diag(ownerPre))) / revenues
                  #measure <- sum((margins - marginsCand)^2,na.rm=TRUE)

                  #measure <- revenues * diag(ownerPre) + as.vector((elast * ownerPre) %*% (margins * revenues))
                  #measure <- sum(measure^2,na.rm=TRUE)

                  return(measure)
              }

               ## Constrain optimizer to look  alpha <0,  0 < sOut < 1
              lowerB <- c(-Inf,0)
              upperB <- c(-1e-10,.99999)

              
              if(!is.na(mktElast)){
                upperB[1] <- mktElast/avgPrice
              }
              
              minTheta <- optim(object@parmsStart,minD,
                                method="L-BFGS-B",
                                lower= lowerB,upper=upperB,
                                control=object@control.slopes)$par

              if(isTRUE(all.equal(minTheta[2],lowerB[2],check.names=FALSE))){
                
                warning("Estimated outside share is close to 0. Normalizing relative to largest good.")

              idx <- which.max(shares)
              shares[idx]
              priceOutside <- prices[idx]
              minTheta[2] <- 0
              object@normIndex <- idx
              
              meanval <- log(shares)  - log(shares[idx]) - minTheta[1] * (prices - priceOutside)
              
              }
              else{meanval <- log(shares * (1 - minTheta[2])) - log(minTheta[2]) - minTheta[1] * (prices - priceOutside)}
              
              if(isTRUE(all.equal(minTheta[2],upperB[2],check.names=FALSE))){stop("Estimated outside share is close to 1.")}
              
              

              names(meanval)   <- object@labels


              object@slopes      <- list(alpha=minTheta[1],meanval=meanval)
              object@shareInside <- 1-minTheta[2]
              object@priceOutside <- priceOutside
              object@mktSize <-  object@insideSize/object@shareInside

              return(object)

          }

          )


logit.alm <- function(prices,shares,margins,
                      ownerPre,ownerPost,
                      mktElast = NA_real_,
                      insideSize = NA_real_,
                      mcDelta=rep(0,length(prices)),
                      subset=rep(TRUE,length(prices)),
                      priceOutside=0,
                      priceStart = prices,
                      isMax=FALSE,
                      parmsStart,
                      control.slopes,
                      control.equ,
                      labels=paste("Prod",1:length(prices),sep=""),
                      ...
                      ){


    if(missing(parmsStart)){
        parmsStart <- rep(.1,2)
        nm <- which(!is.na(margins))[1] 
        parmsStart[1] <- -1/(margins[nm]*prices[nm]*(1-shares[nm])) #ballpark alpha for starting values
    }

   
  
    ## Create Logit  container to store relevant data
    result <- new("LogitALM",prices=prices, shares=shares,
                  margins=margins,
                  ownerPre=ownerPre,
                  ownerPost=ownerPost,
                  mktElast = mktElast,
                  insideSize = insideSize,
                  mcDelta=mcDelta,
                  subset=subset,
                  priceOutside=priceOutside,
                  priceStart=priceStart,
                  shareInside=ifelse(isTRUE(all.equal(sum(shares),1,check.names=FALSE,tolerance=1e-3)),1,sum(shares)),
                  parmsStart=parmsStart,
                  labels=labels)

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
    result@pricePre  <- calcPrices(result,preMerger=TRUE,isMax=isMax,...)
    result@pricePost <- calcPrices(result,preMerger=FALSE,isMax=isMax,subset=subset,...)

    return(result)

}


