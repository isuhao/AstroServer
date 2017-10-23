#!/bin/bash
sumLine=0
sumDZ=0
itertime=0
storageLine=0
ccLine=0
datestamp=""
timestamp=""
sleeptime=8 # assigned by nextsleeptime or firstsleeptime
nextsleeptime=8  # the rest are the normal sleep time
firstsleeptime=30 #the first time running needs to prepare for long time
username="wamdm"
mastername="wamdm100"
nodenum=`cat nodehostname | wc -l`
recoverRedisSleepTime=10
gennum=$1 #the total number of images per ccd
sumpost=1984
stoppost=1986 # master and slave
printpost=1985
stoppostMC=1987 #master and client
icRowNum=1
abhost="null" #abnormal star node, 
#abnormal star bernoulli Param. 
#control the abnorm is occuring or not. bernoulliParam [0,1] is larger,
#the abnorm will occur more easily.
bernoulliDefault="0.1"
geometricDefault="0.995" 
bernoulliParam="0"
geometricParam="0"
#geometric Param control the number of the abnormal number
#control the number of abnormal stars if the abnorm is occuring.
#if geometricParam is larger in abnorm phase, the abnormal stars will be more.
aborder="" #the order which the abnormal node need to run
ordre=""   #the order which the normal node need to run
redisWriteMode="perBlockAsaString"
blockNum=10000 # use in "perBlockAsaString" , "-1" represents the current parameter is invalid 
redisIP="10.0.82.111:7001"
maxLogSize=10485760 #B, 10MB
maxCacheSize=10485760 #B, 1MB
threadNumber=20 #threads write to redis
writeLogRound=5 #write master log per 5 * $sleeptime (s)
stopFlag="" #used for detecting "stop!" order
stopClient="" #used for detecting "stop!" order
#getTemplateFlag could be "first" :the first run flag to lanuch astroDB_cache
#"gt" means the template table gen phase
getTemplateFlag="first" 
if [ -n "$2" ] ;then
getTemplateFlag="gt" #genTemplateTable
fi
templateTable="template_table" #gwac/ is root
sourceFilePath="catalog.csv" #gwac/ is root
newLogName=$(ls logs/ | grep "master" | tail -1)
#pid=`lsof -Pnl +M -i4 | grep $sumpost | awk '{ print $2}'`
cRowNum=1 #the current listen_cache.txt row line
#echo $pid
if [ ! -n "$1" ] ;then  
echo "input the total number of images per ccd."
exit 0
fi
#elif [ "$pid" == "" ]
#then
# echo "run \" nohup ./listenSlaves.sh & \" first."
# exit 0
#fi
if [ "$getTemplateFlag" == "first" ]
then
if [ "$newLogName" == "" ]
then 
     newLogName="master_${mastername}_1_`date "+%Y-%m-%d-%H:%M:%S"`"
     echo -e "TotalLine TotalSize(MB) TotalTime(s) StorageLine CrossCertifiedErrorLine Timestamp\n0 0 0 0 0 0 0" > logs/$newLogName
fi
# put the recoverRedisNode in the background to recover the redis server.
nohup >/dev/null 2>&1 ./recoverRedisNode.sh $recoverRedisSleepTime 2>&1 &
eval $(tail -1 logs/$newLogName | awk '{sl=$1;sd=$2;it=$3;stl=$4;ccl=$5;dt=$6;time=$7} END{print "sumLine="sl";sumDZ="sd";itertime="it";storageLine="stl";ccLine="ccl";datestamp="dt";timestamp="time}')
fi

:>listen_cache.txt
lsof -Pnl +M -i4 | grep $sumpost | awk '{print $2}' | xargs kill >/dev/null 2>&1
nohup >/dev/null 2>&1 ./listenSlaves.py $mastername $sumpost 2>&1 &

for((gentime=1;gentime<=$gennum;gentime++))
do
ccdno=0
nodesta=0
current=`date "+%Y-%m-%d %H:%M:%S"`
timeStamp=`date -d "$current" +%s`
nsec=`date "+%N"`
currentTimeStamp1=$(echo "$timeStamp*1000.0+$nsec/1000000.0"|bc)
#echo $currentTimeStamp1
#abhost="wamdm81"
   if [ "$getTemplateFlag" == "gt" -o "$getTemplateFlag" == "first" ]
   then

   order="cd gwac/gwac_dbgen_cluster/; nohup ./sendStaDataPerNode.sh $mastername ccdno $bernoulliDefault $geometricDefault $redisIP $templateTable $sourceFilePath $threadNumber $getTemplateFlag $redisWriteMode $blockNum ra0 dec0 xi yi >/dev/null 2>&1 &"
   aborder="cd gwac/gwac_dbgen_cluster/; nohup ./sendStaDataPerNode.sh $mastername ccdno $bernoulliParam $geometricParam $redisIP $templateTable $sourceFilePath $threadNumber $getTemplateFlag $redisWriteMode $blockNum ra0 dec0 xi yi >/dev/null 2>&1 &"
	   if [ "$getTemplateFlag" == "first" ]
		then
                         sleeptime=$firstsleeptime
			 getTemplateFlag="next"
		fi
		
	else
         sleeptime=$nextsleeptime
   order="echo $bernoulliDefault $geometricDefault $getTemplateFlag ra0 dec0 xi yi >/tmp/slave.pipe"
 
   aborder="echo $bernoulliParam $geometricParam $getTemplateFlag ra0 dec0 xi yi >/tmp/slave.pipe"
   fi
    	# abhost cannot be "", or else the shell will skip this parameter 
	./parallelSendOrder.sh $abhost "$order" "$aborder" "$username"
#sleep 1000
gentimecopy=$gentime
echo "finished! ($gentime times)"
abhost="null"
bernoulliParam="0"
geometricParam="0"

while true
do
tmp=`sed -n ${cRowNum}p listen_cache.txt`
if [ "$tmp" == "" ]
then
#clean listen_cache to reduce its size

cacheSize=`ls -lk listen_cache.txt 2>/dev/null | awk '{print $5}'`
 if [ $cacheSize -gt $maxCacheSize ]
 then
   :>listen_cache.txt  
   cRowNum=1          
 fi                  
#clean listen_cache to reduce its size
 continue
fi
cRowNum=$(($cRowNum+1))     

pretmp=`echo $tmp | awk '{print $1}'`
suftmp=`echo $tmp | awk '{print substr($0,length($1)+2)}'`
#echo $tmp
if [ "$pretmp" == "stop" ]
then
   nodesta=$(($nodesta+1))
   eval $(echo $suftmp | awk '{h=$1;rn=$2;abs=$3;t=$4} END{print "host="h";resultNum="rn";abStarNum="$3";timeout="t}')
  
   #echo $suftmp $resultNum
   if [ "$timeout" == "" ] 
   then
      if [ $abStarNum -eq 0 ]
       then
      echo "dataGen on $host has stopped, including $resultNum results ($nodesta/$nodenum nodes)."
      else
      echo -e "dataGen on $host has stopped, including $resultNum results and \033[33;1m$abStarNum\033[0m abnormal stars ($nodesta/$nodenum nodes)."
      fi
   else
      if [ $abStarNum -eq 0 ]
       then
      echo -e "\033[31;1mdataGen on $host is $timeout, including $resultNum results ($nodesta/$nodenum nodes).\033[0m"
      else
      echo -e "\033[31;1mdataGen on $host is $timeout, including $resultNum results and \033[33;1m$abStarNum\033[0m abnormal stars ($nodesta/$nodenum nodes).\033[0m" 
      fi
   fi
   
   if [ $nodesta -eq $nodenum ]
   then
   #echo "all nodes have finished data generation ($i time)."
   current=`date "+%Y-%m-%d %H:%M:%S"`
   timeStamp=`date -d "$current" +%s`
   nsec=`date "+%N"`
   currentTimeStamp2=$(echo "$timeStamp*1000.0+$nsec/1000000.0"|bc)   
   interval=$(echo "$sleeptime-($currentTimeStamp2-$currentTimeStamp1)/1000.0" | bc)
   
   echo "all nodes have finished data generation ($gentimecopy times), and sleep $interval(s)."
   sleep $interval
   #lsof -Pnl +M -i4 | grep $sumpost | awk '{print $2}' | xargs kill 
   #pkill listenSlaves.sh
   break
   fi
   continue
elif [ "$pretmp" == "force" ]
then
    echo -e "\033[33;1mStop cluster now!\033[0m"
    for line1 in `awk -F "-" '{print $1}' nodehostname` 
     do 
       echo "force" | nc -q 0 $line1 $stoppost #master and slave
       info=`nc -lp $stoppost` # master and slave
       echo "$info"
       echo "$info" | ./send.py $suftmp $stoppostMC #master and client
     done
     echo "finished" | ./send.py $suftmp $stoppostMC #master and client
     lsof -Pnl +M -i4 | grep $sumpost | awk '{print $2}' | xargs kill
     ps ax | grep [.]/recoverRedisNode.sh | awk '{print $1}' | while read rpid
        do
           kill $rpid
        done
     itertime=$(($itertime+($gentimecopy-1)*$sleeptime))
     if [ "$getTemplateFlag" != "gt" ] 
     then
     #### log
     logSize=`ls -lk logs/$newLogName 2>/dev/null | awk '{print $5}'`
     if [ $logSize -le $maxLogSize ] 
     then
       echo $sumLine $sumDZ $itertime $storageLine $ccLine $datestamp $timestamp >>logs/$newLogName       
        exit 0   
     fi
     newLogNum=$(echo $newLogName | awk -F "_" '{print $3}')
     newLogNum=$(($newLogNum+1)) 
     newLogName="master_${mastername}_${newLogNum}_`date "+%Y-%m-%d-%H:%M:%S"`"
     echo -e "TotalLine TotalSize(MB) TotalTime(s) StorageLine CrossCertifiedErrorLine Timestamp\n$sumLine $sumDZ $itertime $storageLine $ccLine $datestamp $timestamp" > logs/$newLogName
     ####log
    fi
elif [ "$pretmp" == "stop!" ]
then
     echo -e "\033[33;1mCluster will stop next time in the normal way!\033[0m"
     gentime=$gennum
     stopFlag="finished!"
     stopClient=$suftmp
elif [ "$pretmp" == "print" ]
then 
    itertimetmp=$(($itertime+($gentimecopy-1)*$sleeptime))
    echo $sumLine $sumDZ $datestamp $timestamp | nc -q 0 $suftmp $printpost 
elif [ "$pretmp" == "abnormal" ]
then
    eval $(echo $suftmp | awk '{h=$1;b=$2;g=$3} END{print "abhost="h";bernoulliParam="b";geometricParam="g}')
    echo -e "\033[33;1mset abnormal stars on $abhost next time!\033[0m"
else
   eval $(echo $suftmp | awk -v sl=$sumLine -v sd=$sumDZ -v stl=$storageLine -v ccl=$ccLine -v dt=$datestamp -v time=$timestamp '{sl+=$1;sd+=$2;stl+=$6;ccl+=$7;dt=$3;time=$4} END{print "sumLine="sl";sumDZ="sd";storageLine="stl";ccLine="ccl";datestamp="dt";timestamp="time}')      
#  echo $sumLine $sumDZ $storageLine $ccLine $datestamp $timestamp
fi 
done
  logRound=`expr $gentimecopy % $writeLogRound`
  if [ $logRound -eq 0 ]
    then
    itertimeRound=$(($itertime+$gentimecopy*$sleeptime))
####log   
    logSize=`ls -lk logs/$newLogName 2>/dev/null | awk '{print $5}'`
     if [ $logSize -le $maxLogSize ]
     then
       echo $sumLine $sumDZ $itertimeRound $storageLine $ccLine $datestamp $timestamp >>logs/$newLogName
     else
     newLogNum=$(echo $newLogName | awk -F "_" '{print $3}')
     newLogNum=$(($newLogNum+1))
     newLogName="master_${mastername}_${newLogNum}_`date "+%Y-%m-%d-%H:%M:%S"`"
     echo -e "TotalLine TotalSize(MB) TotalTime(s) StorageLine CrossCertifiedErrorLine Timestamp\n$sumLine $sumDZ $itertimeRound $storageLine $ccLine $datestamp $timestamp" > logs/$newLogName
####log
     fi
 fi
done 2>/dev/null

if [ "$getTemplateFlag" == "next" ]
then
   ps ax | grep [.]/recoverRedisNode.sh | awk '{print $1}' | while read rpid
    do
        kill $rpid
    done
	
   for line in `awk -F "-" '{print $1}' nodehostname`  # 
     do 
      ./send.py $line $stoppost "kill"
     done
elif [ "$getTemplateFlag" == "gt" ]
then
   for line in `awk -F "-" '{print $1}' nodehostname`
     do 
      ./send.py $line $stoppost "exit"
     done
fi 2>/dev/null

pid=`lsof -Pnl +M -i4 | grep $sumpost | awk '{print $2}'` 
kill $pid
wait $pid 2>/dev/null  # do not display "kill" information
itertime=$(($itertime+$gentimecopy*$sleeptime))
#echo $gentimecopy $gentime
if [ "$getTemplateFlag" == "next" ]
then
####log
logSize=`ls -lk logs/$newLogName 2>/dev/null | awk '{print $5}'`
 if [ $logSize -le $maxLogSize ]
     then
       echo $sumLine $sumDZ $itertime $storageLine $ccLine $datestamp $timestamp >>logs/$newLogName   
 else
     newLogNum=$(echo $newLogName | awk -F "_" '{print $3}')
     newLogNum=$(($newLogNum+1))
     newLogName="master_${mastername}_${newLogNum}_`date "+%Y-%m-%d-%H:%M:%S"`"
     echo -e "TotalLine TotalSize(MB) TotalTime(s) StorageLine CrossCertifiedErrorLine Timestamp\n$sumLine $sumDZ $itertime $storageLine $ccLine $datestamp $timestamp" > logs/$newLogName
####log
 fi
fi
if [ "$stopFlag" != "" ]
then 
echo $stopFlag | nc -q 0 $stopClient $stoppostMC
fi
