## a high-level interface to all bertrand functions


bertrand.alm <- function(
  demand = c("logit","ces","aids"),
  prices,quantities,margins,
  ownerPre,ownerPost,
  mktElast = NA_real_,
  insideSize = ifelse(demand == "logit",sum(quantities,na.rm=TRUE), sum(prices*quantities,na.rm=TRUE)),
  diversions,
  mcDelta=rep(0,length(prices)),
  subset=rep(TRUE,length(prices)),
  priceOutside=ifelse(demand== "logit",0, 1),
  priceStart=prices,
  isMax=FALSE,
  parmStart,
  control.slopes,
  control.equ,
  labels=paste("Prod",1:length(prices),sep=""),
  ...){
  

demand <- match.arg(demand)


shares_revenue <- shares_quantity <- quantities/sum(quantities)



if(all(!is.na(prices))) shares_revenue <- prices*shares_quantity/sum(prices*shares_quantity) 

if(demand == "aids"){
  
  if(missing(prices)){ prices <- rep(NA_real_,length(shares_revenue))}
  
  if(missing(parmStart)) parmStart <- rep(NA_real_,2)
  
  if(missing(priceStart)) priceStart <- runif(length(shares_revenue))
  
  if(missing(diversions)){
    diversions <- tcrossprod(1/(1-shares_revenue),shares_revenue)
    diag(diversions) <- -1 
    
    
  }
  
}

else if (demand %in% c("logit","ces")){
  
  if(missing(parmStart)){
    parmStart <- rep(.1,2)
    nm <- which(!is.na(margins))[1] 
    if(demand == "logit"){
    parmStart[1] <- -1/(margins[nm]*prices[nm]*(1-shares_quantity[nm])) #ballpark alpha for starting values
    }
    else{parmStart[1] <- 1/(margins[nm]*(1-shares_revenue[nm])) - shares_revenue[nm]/(1-shares_revenue[nm])} #ballpark gamma for starting values
    }
  if(missing(priceStart)) priceStart <- prices
}





  
result <-   switch(demand,
         aids=new("AIDS",shares=shares_revenue,mcDelta=mcDelta,subset=subset,
                  margins=margins, prices=prices, quantities=shares_revenue,  mktElast = mktElast,
                  insideSize = insideSize,
                  ownerPre=ownerPre,ownerPost=ownerPost, parmStart=parmStart,
                  diversion=diversions,
                  priceStart=priceStart,labels=labels),
         
         logit=  new("LogitALM",prices=prices, shares=shares_quantity,
                     margins=margins,
                     ownerPre=ownerPre,
                     ownerPost=ownerPost,
                     mktElast = mktElast,
                     mcDelta=mcDelta,
                     subset=subset,
                     priceOutside=priceOutside,
                     priceStart=priceStart,
                     shareInside= sum(shares_quantity),
                     parmsStart=parmStart,
                     insideSize = insideSize,
                     labels=labels),
         
         ces = new("CESALM",prices=prices, shares=shares_revenue,
                   margins=margins,
                   ownerPre=ownerPre,
                   ownerPost=ownerPost,
                   mktElast = mktElast,
                   mcDelta=mcDelta,
                   subset=subset,
                   priceOutside=priceOutside,
                   priceStart=priceStart,
                   shareInside=sum(shares_revenue),
                   parmsStart=parmStart,
                   insideSize =insideSize,
                   labels=labels),
         
         linear=new("Linear",prices=prices, quantities=shares_quantity,margins=margins,
                    shares=shares_quantity,mcDelta=mcDelta, subset=subset,
                    ownerPre=ownerPre,diversion=diversions, symmetry=TRUE,
                    ownerPost=ownerPost, priceStart=priceStart,labels=labels)
  )
  

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

## Solve Non-Linear System for Price Changes (AIDS only)
if (demand == "aids"){
result@priceDelta <- calcPriceDelta(result,isMax=isMax,subset=subset,...)
}


## Calculate marginal cost
result@mcPre <-  calcMC(result,TRUE)
result@mcPost <- calcMC(result,FALSE)



## Solve Non-Linear System for Price Changes
result@pricePre  <- calcPrices(result,preMerger=TRUE,isMax=isMax,...)
result@pricePost <- calcPrices(result,preMerger=FALSE,isMax=isMax,subset=subset,...)

return(result)

}