#!/bin/bash

iniFile="harvester.ini"
repeat=false
maxError=10
sleep=60

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
    printf "* Error: Invalid argument %s *\n" "$1"
    exit 1
    ;;
  esac
  shift
done

if ! [ -f "$iniFile" ]; then
  echo "ini file doesn't exists"
  exit 1
fi

# dest file & log
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
  sourceArr=([source]=${source[0]} [prefix]=${source[1]} [url]=${source[2]} [metadataPrefix]=${source[3]} [set]=${source[4]} [ictx]=${source[5]} [op]=${source[6]})
  for key in "${!sourceArr[@]}"; do echo "$key=${sourceArr[$key]}"; done
else
  printf "Unknown source %s\n" "$inputSource"
  exit 1
fi

dataPath="${globalArr[home_dir]}/${sourceArr[source]}"
log="${globalArr[log]}/${sourceArr[source]}.log"
baseUrl="${sourceArr[url]}"

i=0
params=()

params+=("verb=ListRecords")
if [ -n "$from" ]; then
  params+=("from=$from")
fi
if [ -n "$to" ]; then
  params+=("until=$to")
fi
if [ -n "${sourceArr[ictx]}" ]; then
  params+=("ictx=${sourceArr[ictx]}")
fi
if [ -n "${sourceArr[op]}" ]; then
  params+=("op=${sourceArr[op]}")
fi

if [ -z $resumptionToken ]; then
  params+=("set=${sourceArr[set]}")
  params+=("metadataPrefix=${sourceArr[metadataPrefix]}")
  if [ -d "$dataPath" ]; then
    if [ "$(ls -A "$dataPath")" ]; then
      rm $dataPath/*
    fi
  else
    mkdir $dataPath
  fi
else
  params+=("resumptionToken=$resumptionToken")
  if [ -d "$dataPath" ]; then
    i=$(ls $dataPath | grep -Po "[0-9]+(?=.xml)" | sort -g | tail -n1)
  else
    mkdir $dataPath
  fi
fi

url=$(printf "&%s" "${params[@]}")
url=${url:1}
url="$baseUrl?$url"

now=$(date)
error=0

>"$dataPath"/temp # create or clean temp file
first=1
while true; do
  now=$(date)
  if grep "<ListRecords" $dataPath/temp >/dev/null; then
    token=$(grep -Po "<resumptionToken[^>]*>\K([^<\s]*)" $dataPath/temp)

    params=()
    params+=("verb=ListRecords")
    params+=("resumptionToken=$token")
    if [ -n "${sourceArr[ictx]}" ]; then
      params+=("ictx=${sourceArr[ictx]}")
    fi
    if [ -n "${sourceArr[op]}" ]; then
      params+=("op=${sourceArr[op]}")
    fi

    url=$(printf "&%s" "${params[@]}")
    url=${url:1}
    url="$baseUrl?$url"

    ((i += 1))
    if [ "$token" != "" ]; then
      cat $dataPath/temp >$dataPath/$i.xml
      echo "$now: $url" >>$log
      curl -s -k "$url" >$dataPath/temp
    else
      cat $dataPath/temp >$dataPath/$i.xml
      break
    fi
  else
    if [ $first -eq 1 ]; then
      first=0
    else
      echo "$now: error - attempt: $(($error + 1)) / $maxError"
      if [ "$repeat" = true ] && [ $error -lt $maxError ]; then
        ((error += 1))
        sleep $sleep
      else
        error=0
        break
      fi
    fi
    now=$(date)
    echo "$now: $url" >>$log
    curl -s -k "$url" >$dataPath/temp
  fi
done

rm $dataPath/temp
