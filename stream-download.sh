#!/bin/bash

STATUS_OK=0
STATUS_ERROR=1

OUTPUT_PLAYLIST="output.m3u8"

getMasterPlaylist() {
  local url="$1"
  local referer="$2"
  
  local header=$([ ! -z "$referer" ] && echo "--header \"Referer: $referer\"" || echo "")
  local command="curl --compressed "$header" \"$url\" 2> /dev/null"
  eval "$command"
}

getMediaPlaylistUrl() {
  local masterPlaylist="$1"
  local media="$2"
  
  echo "$masterPlaylist" | grep -E "^[^#].*\.m3u8$" | head -n "$media" | tail -n 1
}

getMediaPlaylist() {
  local mediaPlaylistUrl="$1"
  local referer="$2"
  
  local header=$([ ! -z $referer ] && echo "--header \"Referer: $referer\"" || echo "")
  local command="curl --compressed "$header" \"$mediaPlaylistUrl\" 2>/dev/null"
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
  local outputDir="$3"
  local referer="$4"
  
  if grep "^$segmentNumber.ts$" "$outputDir/$OUTPUT_PLAYLIST" &> /dev/null; then
    return
  fi

  local segmentOutputName="$segmentNumber.ts"
  local wgetLogfile="$segmentNumber.log"

  echo "$segmentOutputName" >> "$outputDir/$OUTPUT_PLAYLIST"
  echo "Downloading segment $outputDir/$segmentOutputName"
  local header=$([ ! -z $referer ] && echo "--header \"Referer: $referer\"" || echo "")
  local command="wget "$header" -b -O \"$outputDir/$segmentOutputName\" -o \"$outputDir/$wgetLogfile\" \"$segmentUrl\" &> /dev/null"
  eval "$command"
}

main() {
  if [[ $# < 2 || $# > 3 ]] ; then
    echo "Usage: stream-dowload.sh <masterPlaylistUrl> <channelName> <host>"
    exit $STATUS_ERROR
  fi

  local masterPlaylistUrl="$1"
  local channel="$2"
  local host="$3"

  local outputDir
  outputDir="${channel}_$(date +%Y-%m-%d_%H-%M-%S)"
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

  while true
  do
    updateBeginTime=$SECONDS
    echo "Updating media playlist..."
    
    mediaPlaylist=$(getMediaPlaylist "$mediaPlaylistUrl" "$host")
    #isValidMediaPlaylist "$mediaPlaylist"
    if [[ "$(isValidMediaPlaylist "$mediaPlaylist")" == "false" ]]; then
     echo "Error: Invalid media playlist"
     return
    fi
    
    targetDuration=$(getPlaylistTag "$mediaPlaylist" "EXT-X-TARGETDURATION")
    mediaSequence=$(getPlaylistTag "$mediaPlaylist" "EXT-X-MEDIA-SEQUENCE")
    if [ -z "$mediaSequence" ]; then
      echo "Error: Could not get media sequence"
      return
    fi
    
    echo "$mediaPlaylist" | grep -v "^#" | while IFS= read -r segmentUrl ; do if [[ "$(isUrl "$segmentUrl")" == "false" ]]; then segmentUrl="$baseUrl/$segmentUrl"; fi; processMediaSegment "$((mediaSequence++))" "$segmentUrl" "$outputDir" "$host"; done
    
    updateDuration=$(($SECONDS - $updateBeginTime))
    sleepDuration=$(($targetDuration - $updateDuration))
    if (( sleepDuration > 0 )); then
      echo "Wating for $sleepDuration seconds..."
      sleep "$sleepDuration"
    fi
  done
}

main "$@"
