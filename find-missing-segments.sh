STATUS_OK=0
STATUS_ERROR=1

main() {
  if [ $# != 1 ] ; then
    echo "Usage: find-missing-segments.sh <output.m3u8>"
    exit $STATUS_ERROR
  fi

  local filename="$1"
  
  local firstSegment="$(basename "$(head -n 1 $filename)" ".ts")"
  local lastSegment="$(basename "$(tail -n 1 $filename)" ".ts")"
  echo "First segment: $firstSegment, last segment: $lastSegment"

  local counter=0
  
  for i in $(seq "$firstSegment" "$lastSegment")
  do
    if [ -z $(grep "^$i.ts" "$filename") ]; then
      echo "segment $i is missing"
      ((counter++))
    fi
  done
  echo "Found $counter missing segments in total."
}

main "$@"
