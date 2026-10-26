#!/bin/sh

if [ "$#" -lt 2 ]; then
    echo "Error: expected a directory and search string"
    exit 1
fi

filesdir=$1
searchstr=$2

if [ ! -d "$filesdir" ]; then
    echo "Error: $filesdir is not a directory"
    exit 1
fi

numfiles=$(find "$filesdir" -type f | wc -l | tr -d '[:space:]')

matchinglines=$(grep -r -h -F -- "$searchstr" "$filesdir" | wc -l | tr -d '[:space:]')

echo "The number of files are $numfiles and the number of matching lines are $matchinglines"
