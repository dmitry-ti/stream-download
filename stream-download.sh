#!/bin/bash

STATUS_OK=0
STATUS_ERROR=1

OUTPUT_PLAYLIST_FILENAME="output.m3u8"
MAX_RETRIES=5

getMasterPlaylist() {
  local url="$1"
  local referer="$2"
  
  local header=$([ ! -z "$referer" ] && echo "--header \"Referer: $referer\"" || echo "")
  local command="curl --compressed --connect-timeout 300 --max-time 600 "$header" \"$url\" 2> /dev/null"
  eval "$command"
}

getMediaPlaylistUrl() {
  local masterPlaylist="$1"
  local media="$2"
  
  echo "$masterPlaylist" | grep -E "^[^#].*\.m3u8$" | head -n "$media" | tail -n 1
}

getMediaPlaylist() {
  local url="$1"
  local referer="$2"
  
  local header=$([ ! -z $referer ] && echo "--header \"Referer: $referer\"" || echo "")
  local command="curl --compressed --connect-timeout 300 --max-time 600 "$header" \"$url\" 2>/dev/null"
  eval "$command"
}

getPlaylistTag() {
  local mediaPlaylist="$1"
  local tag="$2"
  
  echo "$mediaPlaylist" | sed -n "s/#$tag://p"
}

isUrl() {
  local value="$1"
  
  local regex="^https?://"
  if [[ $value =~ $regex ]] ; then
    echo "true"  
  else
    echo "false"
  fi
}

isValidMediaPlaylist() {
  local mediaPlaylist="$1"

  local header=$(echo "$mediaPlaylist" | head -n 1)
  if [[ "$header" != "#EXTM3U" ]]; then
    echo "false"
    return
  fi

  echo "true"
}

getBaseUrl() {
  local url="$1"
  
  echo ${url%/*} 
}

processMediaSegment() {
  local segmentNumber="$1"
  local segmentUrl="$2"
  local baseUrl="$3"
  local outputDir="$4"
  local referer="$5"
  
  local outputPlaylistPath="$outputDir/$OUTPUT_PLAYLIST_FILENAME"

  # Check if segment was already processed
  if grep "^$segmentNumber.ts$" "$outputPlaylistPath" &> /dev/null; then
    return
  fi

  if [[ "$(isUrl "$segmentUrl")" == "false" ]]; then
    segmentUrl="$baseUrl/$segmentUrl"
  fi

  # Start segment download in background
  local segmentOutputFilename="$segmentNumber.ts"
  local segmentOutputPath="$outputDir/$segmentOutputFilename"
  local wgetLogPath="$outputDir/$segmentNumber.log"

  echo "Downloading segment \"$segmentUrl\" => \"$segmentOutputPath\""
  local header=$([ ! -z $referer ] && echo "--header \"Referer: $referer\"" || echo "")
  local command="wget --timeout=300 "$header" -b -O \"$segmentOutputPath\" -o \"$wgetLogPath\" \"$segmentUrl\" &> /dev/null"
  eval "$command"

  # Save segment filename to output playlist
  echo "$segmentOutputFilename" >> "$outputPlaylistPath"
}

main() {
  if [[ $# < 2 || $# > 3 ]] ; then
    echo "Usage: stream-dowload.sh <masterPlaylistUrl> <outputDirPrefix> <host>"
    exit $STATUS_ERROR
  fi

  local masterPlaylistUrl="$1"
  local outputDirPrefix="$2"
  local host="$3"

  local outputDir
  outputDir="${outputDirPrefix}_$(date +%Y-%m-%d_%H-%M-%S)"
  mkdir "$outputDir"
  if [ $? -ne 0 ] ; then
    echo "Error: could not create output directory: $outputDir"
    return
  fi

  local masterPlaylist=$(getMasterPlaylist "$masterPlaylistUrl" "$host")
  
  echo "$masterPlaylist" | grep -E "^#EXT-X-STREAM-INF:.*" | nl -w1 -s": "
  read -p "Select media to download [1]: " media
  
  if [ -z "$media" ] ; then
    media=1
  fi
  
  local mediaPlaylistUrl=$(getMediaPlaylistUrl "$masterPlaylist" "$media")

  if [ -z "$mediaPlaylistUrl" ]; then
    echo "Error: Could not get media playlist url"
    return $STATUS_ERROR
  fi
  
  local baseUrl=$(getBaseUrl "$masterPlaylistUrl")
  if [[ "$(isUrl "$mediaPlaylistUrl")" == "false" ]]; then
    mediaPlaylistUrl="$baseUrl/$mediaPlaylistUrl"
  fi
  
  echo "mediaPlaylistUrl=$mediaPlaylistUrl"
  
  local mediaPlaylist
  local targetDuration
  local mediaSequence
  local updateBeginTime
  local updateDuration
  local sleepDuration

  local try=0

  while true
  do
    if (( try >= MAX_RETRIES )); then
      echo "Error: Too many retries"
      return
    fi

    updateBeginTime=$SECONDS
    echo "Updating media playlist..."
    
    mediaPlaylist=$(getMediaPlaylist "$mediaPlaylistUrl" "$host")
    if [[ "$(isValidMediaPlaylist "$mediaPlaylist")" == "false" ]]; then
     echo "Warning: Invalid media playlist format"
     ((try++))
     continue
    fi
    
    targetDuration=$(getPlaylistTag "$mediaPlaylist" "EXT-X-TARGETDURATION")
    if [ -z "$targetDuration" ]; then
      echo "Warning: Could not read target duration (EXT-X-TARGETDURATION)"
      ((try++))
     continue
    fi

    mediaSequence=$(getPlaylistTag "$mediaPlaylist" "EXT-X-MEDIA-SEQUENCE")
    if [ -z "$mediaSequence" ]; then
      echo "Warning: Could not read media sequence (EXT-X-MEDIA-SEQUENCE)"
      ((try++))
     continue
    fi

    try=0
    
    echo "$mediaPlaylist" | grep -v "^#" | while IFS= read -r segmentUrl ; do processMediaSegment "$((mediaSequence++))" "$segmentUrl" "$baseUrl" "$outputDir" "$host"; done
    
    updateDuration=$(($SECONDS - $updateBeginTime))
    sleepDuration=$(($targetDuration - $updateDuration))
    if (( sleepDuration > 0 )); then
      echo "Wating for $sleepDuration seconds..."
      sleep "$sleepDuration"
    fi
  done
}

main "$@"
