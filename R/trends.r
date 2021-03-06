######################################
### process year by year estimates
######################################


processEsts <- function(ot,ageDist18){
    for(i in 1:length(ot)){
    ### add year as data
        for(j in 1:length(ot[[i]])){
            ot[[i]][[j]]$year <- i
        }
    ### separate race/sex estimates by sex
    for(lev in c('hs','cc','bach'))
        for(sex in 1:2){
            ot[[i]][[paste0(lev,'Race',c('M','F')[sex])]] <-
                subset(ot[[i]][[paste0(lev,'RaceSex')]],SEX==sex,select=-SEX)
        }
    }

    ## remname se column
    for(i in 1:length(ot)){
        for(j in 1:length(ot[[i]])){
            names(ot[[i]][[j]]) <- gsub('se2','se',names(ot[[i]][[j]]))
            if('raceEth'%in%names(ot[[i]][[j]])){
                ot[[i]][[j]]$raceEth <- gsub('Hispanic','Latinx',ot[[i]][[j]]$raceEth)
                #ot[[i]][[j]]$raceEth <- gsub(' ',' ',ot[[i]][[j]]$raceEth)
            }
        }
    }

    if(!missing(ageDist18)) attr(ot,'weightDat') <- ageDist18

    ot
}



#### combine separate year-by-year sets of estimates into
### estimates from one set of subgroups
combineDat <- function(nnn,ot,deaf=NULL){
    tdat <- do.call('rbind', lapply(ot, function(x) x[[nnn]]))
    names(tdat) <- gsub('bach|hs','y',names(tdat))
    names(tdat)[grep('edLev',names(tdat))] <- 'y'

    for(i in 1:ncol(tdat)) if(is.factor(tdat[,i])) tdat[,i] <- as.character(tdat[,i])

    if('SEX'%in%names(tdat)) tdat$SEX <- c('Male','Female')[tdat$SEX]

    if(!is.null(deaf)){
        tdat <- tdat[tdat$DEAR==ifelse(deaf,1,2),]
        tdat$DEAR <- NULL
    }

    tdat$se[tdat$se==0] <- NA


    subCols <- setdiff(names(tdat),c('y','AGEP','se','Freq','se1','se2','year','ww'))
    subsets <- if(length(subCols)>1) do.call(expand.grid,lapply(tdat[,subCols],unique))
               else cbind(unique(tdat[,subCols]))


   if(!is.null(attr(ot,'weightDat'))){
        tdat <- full_join(tdat,attr(ot,'weightDat'))
    } else
        tdat$ww <- if(any(is.na(tdat$se))) tdat$Freq else 1/tdat$se^2


    list(tdat=tdat,subCols=subCols,subsets=subsets)
}





##########################################
### functions to make tables
##########################################

###################
## functions for attainment rates
###################
getRates <- function(nnn,ot,years=c('08','18'),digits=2){
    rnd <- function(x) sprintf(paste0('%.',digits,'f'),x)
    tab <- map_dfr(years,function(y)
        ot[[y]][[nnn]]%>%
            mutate(
                rate=paste0(rnd(`I(attain >= edLev)TRUE`),' (',rnd(se),')'),
                year=paste0('20',y)
                )%>%
            select(-`I(attain >= edLev)TRUE`,-se,-Freq)
                   )%>%
        tidyr::pivot_wider(names_from=year,values_from=rate)
    if('SEX'%in%names(tab)) tab$SEX <- c('Male','Female')[tab$SEX]
    if(endsWith(nnn,'Tot')){
        tab <- mutate(tab,subgroup='Overall')%>%select(DEAR,subgroup,everything())
    } else names(tab)[2] <- 'subgroup'

    tab
}

ratesTab <- function(lev,subs,ot,years,digits,onlyDeaf){
    tab <- map_dfr(subs,function(ss)
                       getRates(paste0(lev,ss),ot=ot,years=years,digits=digits)%>%
                       filter(!subgroup%in%c('35-44','45-54','55-64'))%>%
                       mutate(SUB=ss)
                   )
    if(onlyDeaf) tab <- filter(tab,DEAR==1)%>%select(-DEAR)
    tab
}

###################
## functions for attainment trends
###################

#### makes trend table given combineDat output
trends <- function(tdat, subCols){
    trnds <- tdat%>%
        group_by(!!! lapply(subCols,sym))%>%
            group_modify(estTrend1)

    trnds$subgroup <- if(length(subCols)==1) "Overall" else trnds[[subCols[2]]]

    trnds
}

### estimate the trend
estTrend1 <- function(ddd,...){
    form <- y~year+as.factor(AGEP)
    trnd <- summary(lm_robust(form,data=ddd,weights=ww))$coef['year',]
    if(is.nan(trnd['Std. Error']))
        trnd <- summary(lm_robust(form,data=ddd,weights=ww,se_type='HC1'))$coef['year',]
    as.data.frame(rbind(trnd))
}

trendRegressionTab <- function(ddd,...){
  form <- y~year+as.factor(AGEP)
  trnd <- lm_robust(form,data=ddd,weights=ww)
trnd
}

###################
## functions for gap trends
###################

### estimate one gap trend
gapTrendOne <- function(tdat,...){
  mod <-
    if(any(is.na(tdat$se))){
      lm_robust(y~(DEAR+splines::ns(AGEP,5))*year,tdat,weights=ww)
    } else
      lm_robust(y~(DEAR+as.factor(AGEP))*year,weights=ww,data=tdat)

  as.data.frame(summary(mod)$coef)['DEAR:year',c(1,2,4)]
}

### estimate gap trend for one set of subgroups, given combineDat output
gapTrend <- function(tdat,subCols,...){
    gaps <-
        if(length(subCols)==1){
            gapTrendOne(tdat)
        } else
            tdat%>%
                group_by_at(vars(!! sym(subCols[2])))%>%
                    group_modify(gapTrendOne)
    gaps$subgroup <- if(length(subCols)==1) "Overall" else gaps[[subCols[2]]]
    gaps
}

###################
## functions to compute all tables and put them together
###################

### regression output -> estimate (se)
tabClean <- function(.data,name,digits=2){
    rnd <- function(x) sprintf(paste0('%.',digits,'f'),x)
    if(!'DEAR'%in%names(.data)) .data$DEAR <- 1
    .data%>%
       ungroup()%>%
       transmute(
           DEAR,
           subgroup,
           !! name:=paste0(rnd(Estimate),' (',rnd(`Std. Error`),')'),
           !! paste0(name,'p') := `Pr(>|t|)`
           )#%>%dplyr::select(SUB,everything())
}

### makes table for trend or gap for one subgroup/level combination
trendTab1 <- function(lev,SUB,ot,trendOrGap=c('trend','gap'),digits=2){
    fun <- switch(trendOrGap,trend=trends,gap=gapTrend)
    out <- combineDat(paste0(lev,SUB),ot)%$%
        fun(tdat,subCols)%>%
            tabClean(trendOrGap,digits=digits)
    #if(SUB=='RaceF') out$subgroup <- paste(out$subgroup,'F')
    #if(SUB=='RaceM') out$subgroup <- paste(out$subgroup,'M')
    if(SUB=='ByAgeCat') out <- filter(out,subgroup=='25-34')
    out$SUB <- SUB
    out
}

### p-value stars
stars <- function(pval)
    ifelse(pval<0.001,'***',
           ifelse(pval<0.01,'**',
                  ifelse(pval<0.05,'*',
                         ifelse(pval<0.1,'.',''))))

### put together tables for all sets of subgroups, levels, attainment or gap.
### does multiplicity adjustment, returns list of tables for 3 levels
tabsFun <- function(ot, trendOrGap=c('trend','gap'),
                     subs=c('Tot','ByAgeCat','Sex','Race','RaceM','RaceF'),
                     onlyDeaf=TRUE,digits=2){

    if(trendOrGap=='gap') onlyDeaf <- TRUE

    tabs <- sapply(c('hs','cc','bach'),
                   function(lev){
                       trnds <- map_dfr(subs,~trendTab1(lev=lev,.,ot=ot,trendOrGap=trendOrGap))

                       if(onlyDeaf){
                           trnds <- trnds%>%filter(DEAR==1)%>%select(-DEAR)
                       } else
                           trnds <- trnds%>%
                               mutate(deaf=ifelse(DEAR==1,'Deaf','Hearing'))%>%
                                   select(-DEAR)%>%
                                       pivot_wider(names_from=deaf,values_from=c('trend','trendp'))%>%
                                           rename(trend=trend_Deaf,trendp=trendp_Deaf)
                       trnds
                   }, simplify=FALSE
                   )

    psTot <- map_dbl(tabs,~ .[[paste0(trendOrGap,'p')]][1])%>%p.adjust(.,'holm')
    psSub <- do.call('c',map(tabs,~ .[[paste0(trendOrGap,'p')]][-1]))%>%p.adjust(.,'fdr')

    for(lev in c('hs','cc','bach'))
        tabs[[lev]][[paste0(trendOrGap,'p')]] <- c(psTot[lev],psSub[startsWith(names(psSub),lev)])

    tabs <- map(tabs,function(x) x%>%mutate(!! sym(trendOrGap):=paste0(!!sym(trendOrGap),stars(!!sym(paste0(trendOrGap,'p')))))%>%
                    select(-starts_with('trendp'),-starts_with('gapp')))

    tabs

}

#### makes all the trend tables
allTabs <- function(overTimeAge,overTime,
                    subs=c('Tot','ByAgeCat','Sex','Race','RaceM','RaceF'),
                    onlyDeaf=TRUE,digits=2,years=c('08','18')){

    tabs <- sapply(c('trend','gap'),
                function(x) tabsFun(overTimeAge,trendOrGap=x,subs=subs,onlyDeaf=onlyDeaf,digits=digits),
                   simplify=FALSE)

    rates <- sapply(c('hs','cc','bach'),ratesTab,
                    subs=subs,ot=overTime,years=years,digits=digits,onlyDeaf=onlyDeaf,
                    simplify=FALSE)


    sapply(c('hs','cc','bach'),
           function(x)
              full_join(rates[[x]],tabs$trend[[x]])%>%
              full_join(tabs$gap[[x]])%>%
              rename(`Deaf\nAttainment`=trend,`Deaf-Hearing\nGap`=gap)%>%
              select(SUB,subgroup,everything())%>%
              arrange(match(SUB,subs))%>%
              mutate(SUB=c(Tot="",ByAgeCat="",Sex="Sex",Race="Race/\nEthnicity",RaceM="Race/\nEthnicity:\nMale",RaceF="Race/\nEthnicity:\nFemale")[SUB]),
           simplify=FALSE
           )
  }



##########################################
### functions to make plots
##########################################

### for each level, four plots: overall, 25-34, by sex, by race/eth

figFun <- function(lev,ot,subs=c('Tot','ByAgeCat','Sex','Race')){

    dd <- map_dfr(subs, function(ss){
                ccc <- combineDat(paste0(lev,ss),ot)
                tdat <- ccc$tdat
                if(ss=='Race') tdat$raceEth <-
                    c(`African American`="Afr. Am.", `American Indian`="Am. Ind.",  `Asian/PacIsl`="Asn/PacIsl", `Latinx`="Latinx",  `Other`="Other", `White`="White")[tdat$raceEth]
                if(ss%in%c('Tot','ByAgeCat')) tdat$subgroup=' ' else names(tdat)[2] <- 'subgroup'
                if(ss=='ByAgeCat') tdat <- subset(tdat,ageRange=='25-34')
                tdat$SUB <- switch(ss,
                                   Tot='Overall',
                                   ByAgeCat='Age 25-34',
                                   Sex='By Gender',
                                   Race='By Race/Ethnicity'
                                   )
                #tdat$lab <- ifelse(tdat$DEAR==1,tdat$subgroup,paste0(tdat$subgroup,' '))
                tdat$lab <- ifelse(tdat$year==11,tdat$subgroup,'')
                tdat$grp <- paste(tdat$DEAR,tdat$subgroup)
                tdat$deaf <- ifelse(tdat$DEAR==1,'Deaf','Hearing')
                tdat
            })#%>%
        dd$SUB=factor(dd$SUB,levels=unique(dd$SUB))#)%>%
        ggplot(dd,aes(year,y,linetype=deaf,group=grp,label=lab))+
            geom_line()+geom_point(size=0.5)+
                scale_x_continuous(
                    breaks=1:11,
                    minor_breaks=NULL,
                    labels=c(2008:2018),
                    limits=c(1,13)
                    )+
                #geom_dl(method=list("last.qp",cex=0.5))+
                geom_text_repel(size=2,force=0.25,min.segment.length=0.25,segment.size=0.5)+
                scale_y_continuous(labels=function(x) paste0(x,'%'))+
                facet_wrap(~SUB,ncol=2)+
                labs(
                  title=paste("Figure", switch(lev,hs=1,cc=2,bach=3)),
                  subtitle=(paste(switch(lev, hs='High School',cc='Associates',bach='Bachelors'),'Degree Attainment, 2008-2018')),
                    x=NULL,
                    y=paste('% Attaining', switch(lev, hs='High School',cc='Associates',bach='Bachelors'),'Degree or Higher'),
                    linetype=NULL
                    )+
                    theme(legend.position='bottom',legend.margin=margin(t=0,b=-.3,unit='cm'),
                        axis.text.x = element_text(angle = 90,hjust = 1, vjust = 0.5),
                          plot.title = element_text(face = "bold"),
                          plot.subtitle=element_text(face="italic"))
}



##########################################
### results text functions
##########################################

############
### results table
############
pfun <- function(p)
  ifelse(p>=0.01,paste0("p=",sprintf("%.2f",p)),
         ifelse(p>0.001,"p<0.01","p<0.001"))



tab1 <- function(lev,SUB,what,ot=if(what=='lev') overTime else overTimeAge,deaf=what!="gap",digits=2,tab=FALSE){

  fun <- switch(what,trend=trends,gap=gapTrend,lev=levs)
  out <- combineDat(paste0(lev,SUB),ot)%$%
    fun(tdat,subCols)
  if(deaf) out <- filter(out,DEAR==1)

  if(tab) return(out)

  if("Estimate"%in%names(out))
    out <- out%>%
      arrange(desc(Estimate))%>%
        mutate(Estimate=round(Estimate,2))
  if("y2008" %in% names(out))
    out <- mutate_at(out,vars(starts_with("y")),~paste0(round(.,digits=1),'%'))


  if(SUB=='ByAgeCat') out <- filter(out,ageRange=='25-34')

  if("Pr(>|t|)"%in%names(out)) out <- mutate(out,pval=pfun(`Pr(>|t|)`))

  out <- as.data.frame(out)

  if(n_distinct(out[,2])==nrow(out)) rownames(out) <- out[,2]

  out
}



levs <- function(tdat,subCols){
  tdat%>%
    filter(year%in%c(1,11))%>%
    mutate(year=2007+year)%>%
    select(!!!syms(subCols),y,se,year)%>%
    pivot_wider(names_from='year',values_from=c("y","se"),names_sep='')
}

interactionTest <- function(out){
  w <- 1/out$`Std. Error`^2
  T <- sum(w*out$Estimate)/sum(w)
  Q <- sum(w*(out$Estimate-T)^2)
  pchisq(Q,length(w)-1,lower.tail=FALSE)
}

pval <- function(top,bottom)
    2*pnorm(as.numeric(-abs(top/bottom)))

diffP <- function(ests,ses){
    est <- ests[2]-ests[1]
    se <- sqrt(ses[2]^2+ses[1]^2)
    pval(est,se)
  }

pairWise <- function(out,groupName=names(out)[2]){
  out <- out%>%arrange(desc(Estimate))
  pvals <- NULL
  for(i in 1:(nrow(out)-1))
    for(j in (i+1):nrow(out))
      pvals <- c(pvals,
                 setNames(
                   diffP(out$Estimate[c(i,j)],out$`Std. Error`[c(i,j)]),
                   paste0(out[i,groupName],'>',out[j,groupName])
                   )
                 )
  #p.adjust(pvals,'hommel')
  pvals
}

totTest1 <- function(lev,SUB,what,ot=overTimeAge){
  if(SUB%in%c('Sex','Race')){
    out <- tab1(lev=lev,SUB=SUB,what=what,ot=ot,tab=TRUE)
    if(nrow(out)==1) return(NULL)
    if(nrow(out)==2) pvals <- c(sex=diffP(out$Estimate,out$`Std. Error`)) else
    pvals <- c(overall=interactionTest(out),pairWise(out))
  } else
    pvals <- bind_rows(
      tab1(lev,'RaceM',what)%>%mutate(sex=paste0(raceEth,'M')),
      tab1(lev,'RaceF',what)%>%mutate(sex=paste0(raceEth,'F'))
    )%>%
    group_by(raceEth)%>%group_map(~pairWise(.,groupName='sex'))%>%do.call('c',.)
  data.frame(levs=lev,subs=SUB,what=what,test=names(pvals),pvals=pvals)
}

totTest <- function(overTimeAge,levs=c('hs','cc','bach'),subs=c('Sex','Race','RaceSex'),what=c('trend','gap')){
  tab <- expand.grid(levs=levs,subs=subs,what=what,stringsAsFactors=FALSE)
  pvals <- map_dfr(1:nrow(tab),~totTest1(tab$levs[.],tab$subs[.],tab$what[.],overTimeAge))
  pvals$pvals[pvals$test=='overall'] <- p.adjust(pvals$pvals[pvals$test=='overall'],'holm')

  pvals <- pvals%>%
    group_by(levs,subs,what)%>%
    mutate(
      overall=ifelse('overall'%in%test,pvals[test=='overall']<0.05,TRUE)
      )%>%
      ungroup()
  pvals$overall[pvals$test=='overall'] <- FALSE
  pvals$pvals[pvals$overall] <- p.adjust(pvals$pvals[pvals$overall],'fdr')
  pvals$pvals[!pvals$overall&pvals$test!='overall'] <- 1
  pvals
}





extrSubs <- function(ccc,varb){
    ## tab <- with(ccc,{
    ##          tab <- NULL
    ##          for(i in 1:nrow(subsets)){
    ##              keep <- rep(TRUE,nrow(tdat))
    ##              for(j in 1:ncol(subsets)){
    ##                  keep <- keep&(tdat[,subCols[j]]==subsets[i,j])
    ##              }
    ##              tab <- cbind(tab,tdat[[varb]][keep][order(tdat$year[keep])])
    ##          }
    ##          tab})
    ddd <- ccc$tdat[,c('year',varb,ccc$subCols)]
    names(ddd) <- c('year','varb',paste0('sub',seq(length(ccc$subCols))))
    tab <- spread(ddd, key=sub1,value=varb)
    rownames(tab) <- 2007+tab$year
    tab$year <- NULL
    tab
}

tabFunBegin <- function(nnn,ot,deaf=NULL){
    ccc <- combineDat(nnn,ot,deaf)

    trnd <- trends(nnn,ot)
    if(!is.null(deaf)) trnd <- trnd[grep(paste0('DEAR=',ifelse(deaf,1,2)),names(trnd))]

    if(nnn%in%names(overTimeAge[[1]])){
        trndsAdj <- trends(nnn,overTimeAge)
        if(!is.null(deaf)) trndsAdj <-
            trndsAdj[grep(paste0('DEAR=',ifelse(deaf,1,2)),names(trndsAdj))]
    }

    ests <- extrSubs(ccc,'y')*1
    ses <- extrSubs(ccc,'se')*1

    ests <- rbind(ests,
                  Growth=ests[nrow(ests),]-ests[1,])

    ses <- rbind(ses,Growth=sqrt(ses[nrow(ses),]^2+ses[1,]^2))

    out <- list(ests=ests,ses=ses,trnd=trnd[sapply(names(ests),function(nn) grep(nn,names(trnd)))])
    if(nnn%in%names(overTimeAge[[1]]))
        out$trndsAdj <- trndsAdj[sapply(names(ests),function(nn) grep(nn,names(trndsAdj)))]
    out
}

estsRS <- function(tabb){
    tab <- rbind(tabb$ests,Trend=NA,`Trend (Adj)`=NA)
    ses <- rbind(tabb$ses,Trend=NA,`Trend (Adj)`=NA)
    for(j in 1:ncol(tab)){
        nm <- colnames(tab)[j]
        sex <- ifelse(grepl('Male',nm),'Male','Female')
        race <- substr(nm,nchar(sex)+2,nchar(nm))
        trd <- tabb$trnd[[grep(paste0('SEX=',sex,' raceEth=',race,' DEAR='),names(tabb$trnd))]]
        trdA <- tabb$trndsAdj[[grep(paste0('SEX=',sex,' raceEth=',race,' DEAR='),names(tabb$trndsAdj))]]
        tab['Trend',j] <- trd[1]*1
        tab['Trend (Adj)',j] <- trdA[1]*1
        ses['Trend',j] <- trd[2]*1
        ses['Trend (Adj)',j] <- trdA[2]*1
    }
    list(ests=tab,ses=ses)
}

tabFun <- function(nnn,ot,deaf=NULL,moe=TRUE,retEst=TRUE){

    tfb <- tabFunBegin(nnn,ot,deaf)
    if(grepl('RaceSex',nnn)) tfb <- estsRS(tfb)
    ests <- tfb$ests
    ses <- tfb$ses
    if(!grepl('RaceSex',nnn)){
        trnd <- tfb$trnd
        trndsAdj <- tfb$trndsAdj

        ests <- rbind(ests,
                      Trend=vapply(1:ncol(ests),function(j)
                          trnd[[grep(colnames(ests)[j],names(trnd))]][1]*1,1),
                      `Trend (Adj)`=vapply(1:ncol(ests),function(j)
                          trndsAdj[[grep(colnames(ests)[j],names(trnd))]][1]*1,1))
        ses <- rbind(ses,
                     Trend=vapply(1:ncol(ests),function(j)
                         trnd[[grep(colnames(ests)[j],names(trnd))]][2]*1,1),
                     `Trend (Adj)`=vapply(1:ncol(ests),function(j)
                         trndsAdj[[grep(colnames(ests)[j],names(trnd))]][2]*1,1))
    }
  #    if(retEst)
  return(list(ests=ests,ses=ses))

  #  tabFinish(ests,ses,moe)
}

tabFinish <- function(anal1,deaf=NULL,moe=TRUE){ #ests,ses,moe,strs){
    if(is.null(deaf)){
        ests <- anal1$ests
        ses <- anal1$ses
        strs <- cbind(anal1$trendStars,c('',''))
        rownames(strs) <- c('unadj','adj')
        diffStars <- anal1$diffStars
        ss <- if('SS'%in%names(anal1)) anal1$SS else c(anal1$deafSS,anal1$hearSS)
    } else if(deaf){
        ests <- anal1$deaf$ests
        ses <- anal1$deaf$ses
        strs <- anal1$trendStars
        ss <- anal1$deafSS
    } else{
        ests <- anal1$hear$ests
        ses <- anal1$hear$ses
        strs <- rbind(unadj=rep('',ncol(ests)),adj=rep('',ncol(ests)))
        ss <- anal1$hearSS
    }
    tab <- ests
    for(j in 1:ncol(ests)){
        for(i in 1:nrow(ests)){
            if(moe) tab[i,j] <- paste(round(ests[i,j],1),'$\\pm$',round(ses[i,j]*1.96,1))
            else tab[i,j] <- paste0(round(ests[i,j],1),' (',round(ses[i,j],1),')')
        }
        tab['Trend',j] <- paste0(tab['Trend',j],strs['unadj',j])
        tab['Trend (Adj)',j] <- paste0(tab['Trend (Adj)',j],strs['adj',j])

    }
    tab <- rbind(tab,`Sample Size/year`= format(ss,big.mark=','))
    if(is.null(deaf)){
        colnames(tab) <- c('Deaf','Hearing')
        ## tab <- cbind(tab,Difference=
        ##                    c(
        ##                      vapply(1:nrow(ests),
        ##                        function(i)
        ##                          diffFun(ests[i,],ses[i,],moe,
        ##                            ifelse(rownames(ests)[i]=='Trend (Adj)',diffStars[2],'')),
        ##                        'a'
        ##                      ),''
        ##                    )
        ## )
    }

  ## c(rep('',(nrow(tab)-4)),
  ##                            diffFun(ests['Growth',],ses['Growth',],moe,''),
  ##                            diffFun(ests['Trend',],ses['Trend',],moe,diffStars[1]),
  ##                            diffFun(ests['Trend (Adj)',],ses['Trend (Adj)',],moe,diffStars[2]),''))
  ##   }

    tab <- tab%>%
      tibble::rownames_to_column('Year')

    tab
}



diffFun <- function(ests,ses,moe,diffStars=''){
    est <- ests[1]-ests[2]
    se <- sqrt(ses[2]^2+ses[1]^2)
    p <- pval(est,se)

    out <- round(est,1)
    out <- if(moe) paste(out,'$\\pm$',round(1.96*se,1)) else paste0(out,' (',round(se,1),')')
    out <- paste0(out,diffStars)
    out
}







    ## errbar(2008:2016,estsD[,1],estsD[,1]+2*sesD[,1],estsD[,1]-2*sesD[,1],
##            ylim=c(0,1),type='l')#,...)
##     lines(2008:2016,estsH[,1],lty=3)
##     errbar(2008:2016,estsH[,1],estsH[,1]+2*sesH[,1],estsH[,1]-2*sesH[,1],lty=2,add=TRUE)
##     for(i in 1:ncol(estsD)){
##         errbar(2008:2016,estsD[,i],estsD[,i]+2*sesD[,i],estsD[,i]-2*sesD[,i],col=i,add=TRUE,type='l')
##         lines(2008:2016,estsH[,i],col=i,lty=3)
##         errbar(2008:2016,estsH[,i],estsH[,i]+2*sesH[,i],estsH[,i]-2*sesH[,i],col=i,add=TRUE,lty=2)
##     }
##     legend(pos,legend=c(colnames(estsD),'','Deaf','Hearing'),col=c(1:ncol(estsD),0,1,1),lty=c(rep(1,ncol(estsD)),0,1,2))
## }


changeFig <- function(nnn,ot,...){
    cccD <- combineDat(nnn,ot,deaf=TRUE)
    cccH <- combineDat(nnn,ot,deaf=FALSE)

    estsD <- extrSubs(cccD,'y')
    sesD <- extrSubs(cccD,'se')
    estsH <- extrSubs(cccH,'y')
    sesH <- extrSubs(cccH,'se')

    for(i in nrow(estsD):1){
        estsD[i,] <- 100*(estsD[i,]-estsD[1,])
        estsH[i,] <- 100*(estsH[i,]-estsH[1,])
    }

    ests <- rbind(melt(estsD),melt(estsH))
    names(ests) <- c('Year','sub','Change')
    ests$deaf <- c(rep('Deaf',prod(dim(estsD))),rep('Hearing',prod(dim(estsH))))

    ggplot(ests,aes(Year,Change,color=sub,shape=deaf,linetype=deaf))+
        geom_point()+geom_line()+labs(color='',shape='',linetype='')+
        geom_hline(yintercept=0,linetype=2)+
        ylab('Change Since 2008 (Percentage Points)')+xlab(NULL)+
        theme(axis.text.x = element_text(angle = 90, hjust = 1,vjust=0.5))

}

##     lll <- range(c(unlist(estsD,estsH)))
##     plot(2008:2016,estsD[,1],pch=16,ylim=lll,type='b',...)
##     points(2008:2016,estsH[,1],pch=17,lty=2,type='b')
##     for(i in 1:ncol(estsD)){
##         points(2008:2016,estsD[,i],pch=16,col=i,type='b')
##         points(2008:2016,estsH[,i],col=i,pch=17,lty=2,type='b')
##         #deafBeta <- trendsUnadj[[nnn]][[paste0(cccD$subCols,'=',colnames(estsD)[i],' DEAR=1')]][1]
##         #hearBeta <- trendsUnadj[[nnn]][[paste0(cccD$subCols,'=',colnames(estsD)[i],' DEAR=2')]][1]

##         #abline(a=-2008*deafBeta,b=deafBeta,col=i)
##         #abline(a=-2008*hearBeta,b=hearBeta,col=i,lty=2)
##         abline(h=0,lty=2)
##     }
##     legend(pos,legend=c(colnames(estsD),'','Deaf','Hearing'),col=c(1:ncol(estsD),0,1,1),lty=c(rep(1,ncol(estsD)),0,1,2),pch=c(rep(NA,ncol(estsD)+1),16,17))
## }






resultsTab <- function(ttt,fname='trends.csv'){
    out <- data.frame(lev=character(0),
                      deaf=character(0),
                      sss=character(0),
                      est=numeric(0),
                      serr=numeric(0),
                      pp=character(0),
                      stars=character(0))
    for(nnn in names(ttt)){
        rrr <- ttt[[nnn]]
        lev <- rep(ifelse(grepl('hs',nnn),'High School','Bachelors'),length(rrr))
        deaf <- ifelse(grepl('DEAR=1',names(rrr)),'Deaf','Hearing')
        sss <- gsub('DEAR=[12]','',names(rrr))
        if(grepl('25',nnn)) sss <- paste0(sss,'ageRange=25-29')
        rrr <- do.call('rbind',rrr)
        ddd <- data.frame(lev,deaf,sss,round(rrr[,1:2]*1,round(abs(log(min(rrr[,2]),10)))-2),
                          ifelse(rrr[,4]<0.001,'<0.001',round(rrr[,4],3)),
                          ifelse(rrr[,4]<0.001,'***',ifelse(rrr[,4]<0.01,'**',
                                                            ifelse(rrr[,4]<0.05,'*',
                                                                   ifelse(rrr[,4]<0.1,'.','')))))

        names(ddd) <- names(out)
        out <- rbind(out,ddd)
    }
    write.table(out,paste0('output/',fname),sep=',',row.names=FALSE,
                col.names=c('Level','Deaf or Hearing','Sub-Group',
                    'Change per Year','Std. Error','p-value',''))
    invisible(out)
}

#estsD,estsH,sesD,sesH,moe=TRUE,diffStars){
diffDeafHear <- function(anal1,moe=TRUE){
    estsD <- anal1$deaf$ests
    estsH <- anal1$hear$ests
    sesD <- anal1$deaf$ses
    sesH <- anal1$hear$ses

    diffTab <- NULL
    diffStars <- rbind('',anal1$diffStars)
    rownames(diffStars) <- c('Growth','Trend','Trend (Adj)')
    for(varb in c('Growth','Trend','Trend (Adj)')){
        diff <- NULL
        for(j in 1:ncol(estsD)){
            diff <- c(diff,diffFun(c(estsD[varb,j],estsH[varb,j]),
                                   c(sesD[varb,j],sesH[varb,j]),moe,diffStars[varb,j]))
        }
        diffTab <- rbind(diffTab,diff)
    }
    rownames(diffTab) <- c('Growth','Trend','Trend (Adj)')
    colnames(diffTab) <- colnames(estsD)
    diffTab
}



diffSub <- function(ests,ses,varb,moe=TRUE){
    diffTab <- matrix('',ncol(ests)-1,ncol(ests)-1)

    for(i in 1:(ncol(ests)-1)){
        for(j in (i+1):ncol(ests)){
            diffTab[i,j-1] <- diffFun(c(ests[varb,i],ests[varb,j]),
                                    c(ses[varb,i],ses[varb,j]),moe)
        }
    }
    rownames(diffTab) <- colnames(ests)[-ncol(ests)]
    colnames(diffTab) <- colnames(ests)[-1]
    diffTab
}



toList <- function(lst,vec){
  fac <- factor(
    do.call(
      'c',
      lapply(
        names(lst),
        function(nm) if(is.matrix(lst[[nm]])) rep(nm,nrow(lst[[nm]])) else nm
      )
    )
  )
    split(vec,fac)
}

mult1 <- function(trend,diff,alpha,adj){
    colnum <- ifelse(adj,2,1)
    trendTot <- trend[[1]][colnum]
    diffTot <- diff[[1]][colnum]
    trend2 <- lapply(trend[-1],function(x) x[,colnum])
    diff2 <- lapply(diff[-1],function(x) x[,colnum])

    if(trendTot>alpha) return(list(trend=lapply(trend,function(x) rep(FALSE,length(x))),
                                   diff=lapply(trend,function(x) rep(FALSE,length(x)))))

    newPs <- p.adjust(do.call('c',trend2),method='hommel')
    rej <- c(TRUE,newPs<=alpha)

    diffPs <- c(diffTot,do.call('c',diff2))
    rejD <- rep(FALSE,length(diffPs))
    rejD[rej] <- p.adjust(diffPs[rej],method='fdr')<=alpha

    list(trend=toList(trend,rej),diff=toList(diff,rejD))
}





mult2 <- function(pTrendL,pDiffL,alpha,adj){
    pHS <- pTrendL[grep('hs',names(pTrendL))]
    diffHS <- pDiffL[grep('hs',names(pTrendL))]

    pCC <- pTrendL[grep('cc',names(pTrendL))]
    diffCC <- pDiffL[grep('cc',names(pTrendL))]


    pBach <- pTrendL[grep('bach',names(pTrendL),ignore.case=TRUE)]
    diffBach <- pDiffL[grep('bach',names(pTrendL),ignore.case=TRUE)]

    rejHS <- mult1(pHS,diffHS,alpha/2,adj)
    rejCC <- mult1(pCC,diffCC,alpha/2,adj)
    rejBach <- mult1(pBach,diffBach,alpha/2,adj)

    list(trend=c(rejHS$trend,rejBach$trend)[names(pTrendL)],
         diff=c(rejHS$diff,rejBach$diff)[names(pDiffL)])
}



mult <- function(pTrendL,pDiffL,alpha,adj){

    colnum <- ifelse(adj,2,1)
    pHS <- pTrendL$hsTot[colnum]
    pBach <- pTrendL$bachTot[colnum]



    pTrend <- do.call('rbind',pTrendL)[,colnum]
    pDiff <- do.call('rbind',pDiffL)[,colnum]

    ngroup <- length(pTrend)
    rejDiff <- rejTrend <- rep(FALSE,ngroup)

    pRank <- rank(pTrend)

    for(i in ngroup:1){
        astar <- alpha/(ngroup-i+1)
        if(pTrend[pRank==i]<= astar){
            rejTrend[pRank<=i] <- TRUE
            rejDiff[pRank<= i & pDiff<= astar] <- TRUE
            stop
        }
    }
    list(trend=toList(pTrendL,rejTrend),diff=toList(pTrendL,rejDiff))
}

mult3 <- function(pTrend,alpha,adj=TRUE){
    ## control FWER for overall trends
    ## control FDR for subgroups
    ppp <- do.call('rbind',pTrend)
    ps <- if(adj) ppp[,'adj'] else ppp[,'unadj']
    padj <- c(p.adjust(ps[1:3],method='holm'),
              p.adjust(ps[-c(1:3)],method='fdr'))
    rej <- padj<alpha
    list(trend=toList(pTrend,rej))
}

mult4 <- function(pTrend,pDiff,alpha,adj=TRUE){
    ## control FWER for overall trends
    ## control FDR for subgroup trends and hearing/deaf differences
    ppp <- do.call('rbind',pTrend)
    ps <- if(adj) ppp[,'adj'] else ppp[,'unadj']
    nTrend <- length(ps)

    ddd <- do.call('rbind',pDiff)
    psd <- if(adj) ddd[,'adj'] else ddd[,'unadj']
    ## ps <- c(ps,psd)

    padj <- c(p.adjust(ps[1:3],method='holm'),
              p.adjust(ps[-c(1:3)],method='fdr'))
  rej <- padj<alpha
  rej <- c(rej,rep(FALSE,length(psd)))
    list(trend=toList(pTrend,rej[1:nTrend]),diff=toList(pDiff,rej[(nTrend+1):length(rej)]))
}


   ##  rej,trend,nn,cc=1){
##   for(rr in rej) if(!is.finite(rr[[trend]][[nn]][cc])) return('')
##   ifelse(rej$`0.001`[[trend]][[nn]][cc],'***',
##            ifelse(rej$`0.01`[[trend]][[nn]][cc],'**',
##            ifelse(rej$`0.05`[[trend]][[nn]][cc],'*',
##                   ifelse(rej$`0.1`[[trend]][[nn]][cc],'.',''))))
## }


getSampleSizes <- function(nnn,ot,deaf){
    ccc <- combineDat(nnn,ot,deaf)
    out <- with(ccc,sapply(unique(tdat[[subCols[1]]]), function(x) round(mean(tdat$Freq[tdat[[subCols[1]]]==x]))))
    if(is.null(names(out))) names(out) <- with(ccc,unique(tdat[[subCols[1]]]))
    out
}



#### functions for plotting gaps over time
gapDat <- function(nnn,ot){
  ccc <- combineDat(nnn,ot)

  gdat <- ccc$tdat%>%
    select(-Freq)%>%
    group_by_at(vars(-DEAR,-y,-se))%>%
    summarize(gap=y[DEAR==2]-y[DEAR==1],se=sqrt(se[DEAR==1]^2+se[DEAR==2]^2))%>%
    mutate(year=year+2007)

  list(gdat=gdat,subCols=ccc$subCols,subsets=ccc$subsets)
}

plotGap <- function(gdat,errbar=TRUE,se=TRUE){

  p <- if(length(gdat$subCols)==1){
    ggplot(gdat$gdat,aes(year,gap))
  } else{
    if(gdat$subCols[2]=='SEX')
      gdat$gdat <- mutate(gdat$gdat,year=year+ifelse(SEX=='Male',1,-1)*0.1)
    ggplot(gdat$gdat,aes_string("year","gap",color=gdat$subCols[2]))
  }

  p <- p+
    geom_point()+
    geom_smooth(method='lm',se=se)+
    scale_x_continuous('Year',breaks=2008:2018,minor_breaks=NULL)+
    ylab('Hearing-Deaf Gap (Percentage Points)')

  if(length(gdat$subCols)>1) p <- p+scale_color_manual(name=NULL,values=subwayPalette)

  if(errbar) p <- p+geom_errorbar(aes(ymin=gap-2*se,ymax=gap+2*se),width=0)

  p
}

gapAdjOne <- function(tab,...){
  names(tab)[grep('edLev',names(tab))] <- 'y'
  mod <- lm_robust(y~DEAR+as.factor(AGEP),data=tab,subset=!is.na(y)&!is.na(se))
  out <- as.data.frame(summary(mod)$coef)['DEAR',1:2]
  if(any(is.nan(out[['Std. Error']]))){
    mod <- update(mod,se_type='HC1')
    out <- as.data.frame(summary(mod)$coef)['DEAR',1:2]
  }
  out
}

gapAdj <- function(dat){
  names(dat)[grep('edLev',names(dat))] <- 'y'
  subCols <- setdiff(names(dat),c('y','AGEP','se','Freq','se1','se2','year','DEAR'))

  if('SEX'%in%names(dat)) dat$SEX <- c('Male','Female')[dat$SEX]


  if(!length(subCols))
    return(gapAdjOne(dat))

  dat%>%
    group_by_at(vars(!! sym(subCols)))%>%
    group_modify(gapAdjOne)%>%
    mutate(year=dat$year[1])
}


gapAdjYr <- function(nnn,overTimeAge,weightDat=NULL){
  gaps <- lapply(overTimeAge, function(ota) gapAdj(ota[[nnn]]))

  ests <- do.call('rbind',lapply(gaps,function(x) x$Estimate))
  ses <- do.call('rbind',lapply(gaps,function(x) x$`Std. Error`))
  rownames(ests) <- rownames(ses) <- 2007+seq(length(gaps))
  if(ncol(ests)>1) colnames(ests) <- colnames(ses) <- gaps[[1]][[1]]



  gtrends <- gapTrend(nnn,overTimeAge,weightDat=weightDat)
  ests <- rbind(ests,trend=gtrends$Estimate)
  ses <- rbind(ses,trend=gtrends$`Std. Error`)
  trendPs <- gtrends$`Pr(>|t|)`
  if(ncol(ests)>1) names(trendPs) <- unlist(gtrends[,1])

  list(ests=ests,ses=ses,pvals=trendPs)
}

gapDatAdj <- function(nnn,overTimeAge){
  gay <- gapAdjYr(nnn,overTimeAge)
  ccc <- combineDat(nnn,overTimeAge)
  if(ncol(gay$ests)==1)
    return(
      list(
        gdat=data.frame(year=seq(nrow(gay$est)-1)+2007,gap=gay$ests[-nrow(gay$ests)],se=gay$se[-nrow(gay$ests)]),
        subCols=ccc$subCols,
        subsets=ccc$subsets
      )
    )

  gdat <- distinct(ccc$tdat[,c(ccc$subCols[2],'year')])
  gdat$year <- gdat$year+2007
  gdat$gap <- gdat$se <- NA
  for(i in 1:nrow(gdat)){
    gdat$gap[i] <- gay$ests[as.character(gdat$year[i]),gdat[[ccc$subCols[2]]][i]]
    gdat$se[i] <- gay$ses[as.character(gdat$year[i]),gdat[[ccc$subCols[2]]][i]]
  }

  list(
    gdat=gdat,
    subCols=ccc$subCols,
    subsets=ccc$subsets
  )
}

makeGapTab <- function(gap1,moe=TRUE){
  ests <- gap1$ests
  ses <- gap1$ses
  strs <- cbind(gap1$stars,c('',''))

  tab <- ests
  for(j in 1:ncol(ests)){
    for(i in 1:nrow(ests)){
      if(moe) tab[i,j] <- paste(round(ests[i,j],1),'$\\pm$',round(ses[i,j]*1.96,1))
      else tab[i,j] <- paste0(round(ests[i,j],1),' (',round(ses[i,j],1),')')
    }
    tab['trend',j] <- paste0(tab['trend',j],strs[j])
  }
  tab
}

