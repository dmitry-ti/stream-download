#!/bin/bash

main() {
  if [ $# != 2 ] ; then
    echo "Error: expected 2 arguments: playlist and output filenames"
    return
  fi
  local playlist="$1"
  if [ ! -f "$playlist" ]; then
    echo "Error: playlist file not found"
    return
  fi
  local output="$2"
  if [ -f "$output" ]; then
    echo "Error: output file already exists"
    return
  fi
  grep "^.*\.ts$" "$playlist" | sort -n | xargs cat > "$output"
}

main "$@"