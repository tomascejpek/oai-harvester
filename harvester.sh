#!/bin/bash

iniFile="harvester.ini"
repeat=false

while [ $# -gt 0 ]; do
  case "$1" in
  --iniFile=*)
    iniFile="${1#*=}"
    ;;
  --source=*)
    inputSource="${1#*=}"
    ;;
  --repeat=*)
    repeat="${1#*=}"
    ;;
  --resumptionToken=*)
    resumptionToken="${1#*=}"
    ;;
  --from=*)
    from="${1#*=}"
    ;;
  --to=*)
    to="${1#*=}"
    ;;
  *)
    printf "* Error: Invalid argument $1 *\n"
    exit 1
    ;;
  esac
  shift
done

if ! [ -f "$iniFile" ]; then
  echo "ini file doesn't exists"
  exit 1
fi

if grep "^global|" $iniFile >/dev/null; then
  globalIni=$(grep "^global|" $iniFile)
  IFS='|' read -ra global <<<"$globalIni"
  declare -A globalArr
  globalArr=([home_dir]=${global[1]} [log]=${global[2]})
  echo ${globalArr[home_dir]}
else
  echo "Missing global configuration"
  exit 1
fi

if grep "^$inputSource|" $iniFile >/dev/null; then
  sourceIni=$(grep "^$inputSource|" $iniFile)
  IFS='|' read -ra source <<<"$sourceIni"
  declare -A sourceArr
  sourceArr=([source]=${source[0]} [prefix]=${source[1]} [url]=${source[2]} [metadataPrefix]=${source[3]} [set]=${source[4]})
  for key in "${!sourceArr[@]}"; do echo "$key=${sourceArr[$key]}"; done
else
  printf "Unknown source $inputSource\n"
  exit 1
fi

dataPath="${globalArr[home_dir]}/${sourceArr[source]}"
log="${globalArr[log]}/${sourceArr[source]}.log"
baseUrl="${sourceArr[url]}"

i=0

if [ -n "$from" ]; then
  from="&from"=$from
fi
if [ -n "$to" ]; then
  to="&until"=$to
fi
if [ -z $resumptionToken ]; then
  url="$baseUrl?verb=ListRecords&set=${sourceArr[set]}&metadataPrefix=${sourceArr[metadataPrefix]}$from$to"
  if [ -d "$dataPath" ]; then
    rm $dataPath/*
  else
    mkdir $dataPath
  fi
else
  url="$baseUrl?verb=ListRecords&resumptionToken=$resumptionToken"
  if [ -d "$dataPath" ]; then
    i=$(ls $dataPath | grep -Po "[0-9]+(?=.xml)" | sort -g | tail -n1)
  else
    mkdir $dataPath
  fi
fi

now=$(date)
error=0
echo "$now: Downloading URL: $url" >$log
curl -s -k $url >$dataPath/temp

while true; do
  now=$(date)
  if grep "ListRecords" $dataPath/temp >/dev/null; then
    echo "ok" >>$log
    break
  else
    echo "error" >>$log
    if [ "$repeat" = true ] && [ $error -lt 3 ]; then
      ((error += 1))
      sleep 60
    else
      error=0
      break
    fi
    now=$(date)
    echo "$now: Downloading URL: $url" >>$log
    curl -s -k $url >$dataPath/temp
  fi
done

while true; do
  now=$(date)
  if grep "ListRecords" $dataPath/temp >/dev/null; then
    token=$(grep -Po "<resumptionToken[^>]*>\K([^<\s]*)" $dataPath/temp)
    ((i += 1))
    if [ "$token" != "" ]; then
      cat $dataPath/temp >$dataPath/$i.xml
      echo "$now: $baseUrl?verb=ListRecords&resumptionToken=$token" >>$log
      curl -s -k "$baseUrl?verb=ListRecords&resumptionToken=$token" >$dataPath/temp
    else
      cat $dataPath/temp >$dataPath/$i.xml
      break
    fi
  else
    echo "error"
    if [ "$repeat" = true ] && [ $error -lt 10 ]; then
      ((error += 1))
      sleep 60
    else
      error=0
      break
    fi
    now=$(date)
    echo "$now: $baseUrl?verb=ListRecords&resumptionToken=$token" >>$log
    curl -s -k "$baseUrl?verb=ListRecords&resumptionToken=$token" >$dataPath/temp
  fi
done

rm $dataPath/temp
