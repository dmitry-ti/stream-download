main() {
  local filename="$1"
  local min="$2"
  local max="$3"
  local counter=0
  
  for i in $(seq "$min" "$max")
  do
    if [ -z $(grep "^$i.ts" "$filename") ]; then
      echo "segment $i is missing"
      ((counter++))
    fi
  done
  echo "Found $counter missing segments in total."
}

main "$@"
