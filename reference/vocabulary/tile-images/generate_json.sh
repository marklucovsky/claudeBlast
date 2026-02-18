#!/bin/bash

# Ensure correct usage
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <directory> <pageName> [cutoffTime (YYYYMMDDHHMM)]"
    exit 1
fi

# Assign arguments
directory="$1"
pageName="$2"
cutoffTime="$3"

# Validate directory
if [ ! -d "$directory" ]; then
    echo "Error: Directory does not exist."
    exit 1
fi

# Prepare JSON output file
jsonOutput="$directory/output.json"
echo "[" > "$jsonOutput"

firstEntry=true

# Process PNG files sorted by modification time (oldest first)
find "$directory" -type f -name "*.png" -print0 | xargs -0 stat -f "%m %N" | sort -n | awk '{print $2}' | while IFS= read -r file; do
    filename=$(basename -- "$file" .png)

    # Get file's last modified time in YYYYMMDDHHMM format
    fileTime=$(stat -f "%Sm" -t "%Y%m%d%H%M" "$file")

    # Check against cutoff time if provided
    if [ -n "$cutoffTime" ] && [ "$fileTime" -lt "$cutoffTime" ]; then
        echo "Skipping file: $file (older than cutoff)"
        continue
    fi

    # Append JSON entry
    if [ "$firstEntry" = false ]; then
        echo "," >> "$jsonOutput"
    fi
    firstEntry=false

    echo "{ \"value\": \"$filename\", \"pages\": [\"$pageName\"] }" >> "$jsonOutput"
done

# Close JSON array
echo "]" >> "$jsonOutput"

echo "JSON output saved to: $jsonOutput"
exit 0

