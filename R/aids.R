setClass(
         Class = "AIDS",
         contains="Linear",
         representation=representation(
         priceStart  = "numeric",
         priceDelta       = "numeric",
         mktElast         = "numeric",
         parmStart="numeric",
         insideSize          = "numeric"
         ),
        prototype=prototype(
        insideSize       =  NA_real_,
        priceDelta       =  numeric(),
        mktElast         =  numeric(),
        parmStart        =  numeric(),
        control.slopes = list( 
        )
       ),
       

         validity=function(object){

          
             if(!length(object@parmStart) %in% c(0,2) || any(object@parmStart > 0,na.rm=TRUE)){stop("'parmStart' must be a length-2 non-positive numeric vector")}

             nprods <- length(object@shares)

             if(!isTRUE(all.equal(rowSums(object@diversion,na.rm=TRUE),rep(0,nprods),check.names=FALSE,tolerance=1e-3))){ stop("'diversions' rows must sum to 0")}

             if(!isTRUE(all.equal(sum(object@shares),1,check.names=FALSE,tolerance=1e-3))){
                 stop("The sum of 'shares' values must equal 1")}

             nMargins <- length(object@margins[!is.na(object@margins)])
             
             
             
             if(nMargins<2 && isTRUE(is.na(object@mktElast))){stop("At least 2 elements of 'margins' must not be NA in order to calibrate demand parameters")}
             if(nMargins<1 && !isTRUE(is.na(object@mktElast))){stop("At least 1 element of 'margins' must not be NA in order to calibrate demand parameters")}
             


             return(NULL)

         }

             )








setMethod(
 f= "calcSlopes",
 signature= "AIDS",
 definition=function(object){


     ## Uncover linear demand slopes
     shares     <- object@shares
     prices     <- object@prices
     margins    <- object@margins
     diversion  <- object@diversion
     labels     <- object@labels
     ownerPre   <- object@ownerPre
     parmStart  <- object@parmStart
     mktElast   <- ifelse(length(object@mktElast) == 0, NA, object@mktElast)
     nprod=length(shares)

     cancalibrate <- apply(diversion,1,function(x){!any(x==0)})
     idx <- which.max(ifelse(cancalibrate,shares, -1))
     

     if(any(is.na(parmStart))){
     parmStart[2] <-  -1.2
     parmStart[1] <-  (1 - shares[idx] + parmStart[2] * (1 - shares[idx])) * shares[idx] - .1
     if(parmStart[1] >= 0){parmStart[1] <- -.5}
     }
     minD <- function(s){

       #enforce symmetry
       thismktElast = s[2]
       betas  =   s[1]

       betas <- -diversion[idx,]/diversion[,idx] * betas

       B = t(diversion * betas)
       #diag(B)=  betas - rowSums(B) #enforce homogeneity of degree zero

       elast <- t(B/shares) + shares * (thismktElast + 1) #Caution: returns TRANSPOSED elasticity matrix
       diag(elast) <- diag(elast) - 1

       marginsCand <- -1 * as.vector(solve(elast * ownerPre) %*% (shares * diag(ownerPre))) / shares
       
       
       m1 <- margins - marginsCand
       m2 <- diversion/t(diversion) - tcrossprod(1/betas,betas) 
       m2 <-  m2[upper.tri(m2)]
       m2 <- m2[is.finite(m2) & m2 != 0]
       m3 <- thismktElast - mktElast
       #m2 <- as.vector(diversion +  t(B)/diag(B)) #measure distance between observed and predicted diversion


       measure=c(m1,m2,m3)

      
       return(sum(measure^2,na.rm=TRUE))
     }

    

     ui = -diag(2)
     ui[2,1] = -1/shares[idx]
     ui[2,2] =  1 - shares[idx]
     ui <- rbind(ui,c(0,-1))
     ci = rep(0,3)
     ci[2] = -(1 - shares[idx]) 
     
     bestParms=constrOptim(parmStart,f=minD, ui=ui,ci=ci, grad=NULL,
                   control=object@control.slopes)
     
     
     betas <- -diversion[idx,]/diversion[,idx]*bestParms$par[1]
     
     B = t(diversion * betas)

     dimnames(B) <- list(object@labels,object@labels)

     object@slopes <- B

     if(abs(bestParms$par[2])>5){warning("'mktElast' estimate is large: ",bestParms$par[2])}
     if(isTRUE(all.equal(bestParms$par[2] , object@parmStart[2]))){warning("'mktElast' estimate is not identified" )}
     object@mktElast <- bestParms$par[2]
     object@intercepts <- as.vector(shares - B%*%log(prices))
     names(object@intercepts) <- object@labels


     return(object)

 }

      )



setMethod(
 f= "calcPriceDelta",
 signature= "AIDS",
 definition=function(object,isMax=FALSE,levels=FALSE,subset,market=FALSE,...){

   if(market) return(sum(object@priceDelta * calcShares(object, preMerger = FALSE),na.rm=TRUE))
   
     ownerPost <- object@ownerPost

      nprods <- length(object@shares)
     if(missing(subset)){subset <- rep(TRUE,nprods)}

     if(!is.logical(subset) || length(subset) != nprods ){stop("'subset' must be a logical vector the same length as 'shares'")}


     ##Define system of FOC as a function of priceDelta
     FOC <- function(priceDelta){

         object@priceDelta <- exp(priceDelta)-1

         sharePost <-  calcShares(object,FALSE)
         elastPost <-  t(elast(object,FALSE))
         marginPost <- calcMargins(object,FALSE)


         thisFOC <- sharePost*diag(ownerPost) + as.vector((elastPost*ownerPost) %*% (sharePost*marginPost))
         thisFOC[!subset] <- sharePost[!subset]
         return(thisFOC)

     }




     ## Find price changes that set FOCs equal to 0
     minResult <- BBsolve(object@priceStart,FOC,quiet=TRUE,control=object@control.equ)


     if(minResult$convergence != 0){warning("'calcPrices' nonlinear solver may not have successfully converged. 'BBsolve' reports: '",minResult$message,"'")}

     if(isMax){

         hess <- genD(FOC,minResult$par) #compute the numerical approximation of the FOC hessian at optimium
         hess <- hess$D[,1:hess$p]


         if(any(eigen(hess)$values>0)){warning("Hessian of first-order conditions is not positive definite. Price vector may not maximize profits. Consider rerunning 'calcPrices' using different starting values")}
     }

     deltaPrice <- exp(minResult$par)-1
     names(deltaPrice) <- object@labels

     if(levels){deltaPrice <- calcPrices(object,FALSE) - calcPrices(object,TRUE)}
     
     if(market){
       sharePost <-  calcShares(object,FALSE,...)
       sharePost <- sharePost/sum(sharePost, na.rm=TRUE)
       
      deltaPrice <- sum(deltaPrice*sharePost,na.rm=TRUE)  
       
     }
     
     
     
     return(deltaPrice)
 }
          )


setMethod(
 f= "calcPrices",
 signature= "AIDS",
 definition=function(object,preMerger=TRUE,...){


     ##if(any(is.na(object@prices)){warning("'prices' contains missing values. AIDS can only predict price changes, not price levels")}

     if(preMerger){prices <- object@prices}
     else{ prices <- object@prices * (1 + object@priceDelta)}

     names(prices) <- object@labels
     return(prices)
     }
          )




## compute product revenues
setMethod(
  f= "calcRevenues",
  signature= "AIDS",
  definition=function(object,preMerger=TRUE, market =FALSE){
    
    shares <- calcShares(object, preMerger = preMerger, revenue=TRUE)
    
    insideSize <- object@insideSize
    
    
    if(!preMerger){
      
      # source: epstein and rubinfeld Assumption C (appendix)
      insideSizeDelta <- sum( shares * object@priceDelta) * (object@mktElast + 1) 
      
      insideSize <- insideSize*( 1 + insideSizeDelta)
      
    }
    
    if(market){return(insideSize)}
    
    res <- shares * insideSize
      
    return(res)
    
  })

setMethod(
  f= "calcQuantities",
  signature= "AIDS",
  definition=function(object,preMerger=TRUE, market=FALSE){
    
    if(preMerger){ prices <- object@pricePre}
    else{          prices <- object@pricePost}
    
    insideSize <- object@insideSize
    
    shares <- calcShares(object, preMerger = preMerger, revenue=TRUE)
    
    if(!preMerger){
      
    # source: epstein and rubinfeld Assumption C (appendix)
    insideSizeDelta <- sum( shares * object@priceDelta) * (object@mktElast + 1) 
    
    insideSize <- insideSize*( 1 + insideSizeDelta)
    
    }
    
    shares <- calcShares(object, preMerger= preMerger, revenue = TRUE)
    
    res <- insideSize*shares / prices
    if(market) res <- sum(res)
    return(res )
    
    
  })

setMethod(
 f= "calcShares",
 signature= "AIDS",
 definition=function(object,preMerger=TRUE,revenue=TRUE){

     if(!revenue &&
        any(is.na(object@prices))
        ){
         warning("'prices' contains missing values. Some results are missing")
        }

     prices <- calcPrices(object,preMerger)
     shares <- object@shares


     if(!preMerger){
         shares <-  shares + as.vector(object@slopes %*% log(object@priceDelta + 1))
     }

      if(!revenue){shares <- (shares/prices)/sum(shares/prices)}

     names(shares) <- object@labels
     return(shares)
 }
 )




setMethod(
          f= "elast",
          signature= "AIDS",
          definition=function(object,preMerger=TRUE,market=FALSE){


               if(market){

                   return(object@mktElast)

               }

               else{
                   shares <- calcShares(object,preMerger)

                   elast <- t(object@slopes/shares) + shares * (object@mktElast + 1) #Caution: returns TRANSPOSED elasticity matrix
                   diag(elast) <- diag(elast) - 1
                   dimnames(elast) <-  list(object@labels,object@labels)

                   return(t(elast))

               }
           }
          )




setMethod(
 f= "diversion",
 signature= "AIDS",
 definition=function(object,preMerger=TRUE,revenue=TRUE){

     if(revenue){
         diversion <- -t(object@slopes)/diag(object@slopes)
         dimnames(diversion) <-  list(object@labels,object@labels)
         return(diversion)
     }

     else{callNextMethod(object,preMerger,revenue)}

     }

          )

setMethod(
 f= "diversionHypoMon",
 signature= "AIDS",
 definition=function(object){

   return(diversion(object,revenue=FALSE))

          })

setMethod(
 f= "upp",
 signature= "AIDS",
 definition=function(object){

     if(any(is.na(object@prices))){stop("UPP cannot be calculated without supplying values to 'prices'")}

     else{return(callNextMethod(object))}
     })


setMethod(
 f= "cmcr",
 signature= "AIDS",
 definition=function(object, market= FALSE){


     ownerPre  <- object@ownerPre
     ownerPost <- object@ownerPost

     isParty <- rowSums( abs(ownerPost - ownerPre) ) > 0

     sharesPre <- calcShares(object,TRUE)
     sharesPre <- tcrossprod(1/sharesPre,sharesPre)

     marginPre <- calcMargins(object,TRUE)


     elastPre  <- t(elast(object,TRUE))

     divPre    <- elastPre/diag(elastPre)


     Bpost      <- divPre * sharesPre * ownerPost
     marginPost <- -1 * as.vector(MASS::ginv(Bpost) %*% (diag(ownerPost)/diag(elastPre))
                                  )

     cmcr <- (marginPost - marginPre)/(1 - marginPre)
     names(cmcr) <- object@labels

     cmcr <- cmcr[isParty]

     if(market){
       sharePost <- calcShares(object, preMerger=FALSE, revenue =FALSE)
       if(all(is.na(sharePost))) sharePost <- calcShares(object, preMerger=FALSE, revenue = TRUE)
       sharePost <- sharePost[isParty]
       sharePost <- sharePost/sum(sharePost)
       
       cmcr <- sum( cmcr * sharePost )
     }
     
    return(cmcr * 100)
}
 )




setMethod(
          f= "CV",
          signature= "AIDS",
          definition=function(object){

              ## computes compensating variation using the closed-form solution found in LaFrance 2004, equation 10

              if(any(is.na(object@prices))){stop("Compensating Variation cannot be calculated without supplying values to 'prices'")}

              

              slopes <- object@slopes
              intercepts <- object@intercepts
              pricePre <- log(object@pricePre)
              pricePost <- log(object@pricePost)
              insideSizePre <- object@insideSize
              
              sharePost <- calcShares(object, preMerger = FALSE, revenue = TRUE)
              
              # source: epstein and rubinfeld Assumption C (appendix)
              insideSizeDelta <- sum( sharePost * object@priceDelta) * (object@mktElast + 1) 
              
              insideSizePost <- insideSizePre*( 1 + insideSizeDelta)
              
              result <- sum(intercepts*(pricePost-pricePre)) + .5 * as.vector(t(pricePost)%*%slopes%*%pricePost - t(pricePre)%*%slopes%*%pricePre)


              if(is.na(insideSizePost)){
                  warning("Slot 'insideSize' is missing. Calculating CV as a percentage change in (aggregate) income")
                  return(result*100)}

               else{
                  return(insideSizePost*(exp(result)-1))
              }

          }
          )


setMethod(
 f= "calcMargins",
 signature= "AIDS",
 definition=function(object,preMerger=TRUE){

     priceDelta <- object@priceDelta
     ownerPre   <- object@ownerPre
     shares     <- calcShares(object,TRUE)

     elastPre <-  t(elast(object,TRUE))
     marginPre <-  -1 * as.vector(MASS::ginv(elastPre * ownerPre) %*% (shares * diag(ownerPre))) / shares

     if(preMerger){
         names(marginPre) <- object@labels
         return(marginPre)}

     else{

         marginPost <- 1 - ((1 + object@mcDelta) * (1 - marginPre) / (priceDelta + 1) )
         names(marginPost) <- object@labels
         return(marginPost)
     }

}
 )



setMethod(
 f= "calcPriceDeltaHypoMon",
 signature= "AIDS",
 definition=function(object,prodIndex,...){

     priceDeltaOld <- object@priceDelta

     ##Define system of FOC as a function of priceDelta
     FOC <- function(priceDelta){

         priceCand <- priceDeltaOld
         priceCand[prodIndex] <- priceDelta
         object@priceDelta <- exp(priceCand)-1

         shareCand <-  calcShares(object,FALSE)
         elastCand <-  elast(object,FALSE)
         marginCand <- calcMargins(object,FALSE)

         elastCand <-   elastCand[prodIndex,prodIndex]
         shareCand <-   shareCand[prodIndex]
         marginCand <-  marginCand[prodIndex]

         thisFOC <- shareCand + as.vector(t(elastCand) %*% (shareCand*marginCand))
         return(thisFOC)

     }



     ## Find price changes that set FOCs equal to 0
     minResult <- BBsolve(object@priceStart[prodIndex],FOC,quiet=TRUE,...)

     if(minResult$convergence != 0){warning("'calcPricesHypoMon' nonlinear solver may not have successfully converged. 'BBsolve' reports: '",minResult$message,"'")}


     deltaPrice <- (exp(minResult$par)-1)

     names(deltaPrice) <- object@labels[prodIndex]

     return(deltaPrice[prodIndex])

 })



setMethod(
 f= "calcPricesHypoMon",
 signature= "AIDS",
 definition=function(object,prodIndex,...){


     priceDeltaHM <- calcPriceDeltaHypoMon(object,prodIndex,...)

     prices <- object@prices[prodIndex] * (1 + priceDeltaHM)


     return(prices)

 })






aids <- function(shares,margins,prices,diversions,
                 ownerPre,ownerPost,
                 mktElast = NA_real_,
                 insideSize = NA_real_,
                 mcDelta=rep(0, length(shares)),
                 subset=rep(TRUE, length(shares)),
                 parmStart= rep(NA_real_,2),
                 priceStart=runif(length(shares)),
                 isMax=FALSE,
                 control.slopes,
                 control.equ,
                 labels=paste("Prod",1:length(shares),sep=""),
                 ...){



    if(missing(prices)){ prices <- rep(NA_real_,length(shares))}

    if(missing(diversions)){
        diversions <- tcrossprod(1/(1-shares),shares)
        diag(diversions) <- -1 


    }



    ## Create AIDS container to store relevant data
    result <- new("AIDS",shares=shares,mcDelta=mcDelta,subset=subset,
                  margins=margins, prices=prices, quantities=shares,  mktElast = mktElast,
                  ownerPre=ownerPre,ownerPost=ownerPost, parmStart=parmStart, insideSize = insideSize,
                  diversion=diversions,
                  priceStart=priceStart,labels=labels)

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

    ## Solve Non-Linear System for Price Changes
    result@priceDelta <- calcPriceDelta(result,isMax=isMax,subset=subset,...)


    ## Calculate marginal cost
    result@mcPre <-  calcMC(result,TRUE)
    result@mcPost <- calcMC(result,FALSE)


    ## Calculate Pre and Post merger equilibrium prices
    result@pricePre  <- calcPrices(result,TRUE)
    result@pricePost <- calcPrices(result,FALSE)


    return(result)
}



