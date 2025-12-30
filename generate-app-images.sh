#!/usr/bin/env bash
# generate-app-images.sh
# Generates HTML files with images from each app folder, excluding images with "hero" in the name

set -u

PROGNAME=$(basename "$0")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$SCRIPT_DIR/apps"

usage() {
  cat <<EOF
Usage: $PROGNAME [options]

Options:
  -n          Dry-run (show what would be done)
  -h          Show this help

This script scans all app folders in ./apps/ (flutter, kotlin, react-native, swift)
and generates an HTML file for each app with all images except those containing "hero" in the name.

Example:
  # dry-run
  $PROGNAME -n
  
  # generate HTML files for all apps
  $PROGNAME

EOF
}

DRY_RUN=0

while getopts ":nh" opt; do
  case $opt in
    n) DRY_RUN=1 ;;
    h) usage; exit 0 ;;
    *) echo "Unknown option: -$OPTARG"; usage; exit 2 ;;
  esac
done

if [ ! -d "$APPS_DIR" ]; then
  echo "Apps directory not found: $APPS_DIR"
  exit 1
fi

echo "Scanning apps in: $APPS_DIR (dry-run=$DRY_RUN)"

# Image extensions to look for
IMAGE_EXTENSIONS="png jpg jpeg gif svg webp"

# Function to get relative GitHub URL for an image
get_github_url() {
  local file="$1"
  local repo_path="${file#$SCRIPT_DIR/}"
  echo "https://raw.githubusercontent.com/dopebase/assets/refs/heads/main/$repo_path"
}

# Function to get alt text from filename
get_alt_text() {
  local basename="$1"
  # Remove extension and replace hyphens/underscores with spaces
  local alt="${basename%.*}"
  alt="${alt//-/ }"
  alt="${alt//_/ }"
  echo "$alt"
}

# Function to process an app folder
process_app_folder() {
  local app_folder="$1"
  local app_name="$(basename "$app_folder")"
  local output_file="$app_folder/generated.html"
  
  echo "Processing: $app_name"
  
  # Find all images, excluding those with "hero" in the name
  local images=()
  for ext in $IMAGE_EXTENSIONS; do
    while IFS= read -r -d '' file; do
      # Skip files with "hero" in the name (case-insensitive)
      if [[ ! "${file##*/}" =~ [Hh][Ee][Rr][Oo] ]]; then
        images+=("$file")
      fi
    done < <(find "$app_folder" -maxdepth 1 -type f -iname "*.$ext" -print0 2>/dev/null)
  done
  
  if [ ${#images[@]} -eq 0 ]; then
    echo "  ✗ No images found (excluding hero images)"
    return
  fi
  
  # Sort images
  IFS=$'\n' sorted_images=($(sort <<<"${images[*]}"))
  unset IFS
  
  echo "  Found ${#sorted_images[@]} images"
  
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  DRY: Would create $output_file with ${#sorted_images[@]} images"
    for img in "${sorted_images[@]}"; do
      echo "    - $(basename "$img")"
    done
  else
    # Generate HTML
    {
      for img in "${sorted_images[@]}"; do
        local basename="$(basename "$img")"
        local url="$(get_github_url "$img")"
        local alt="$(get_alt_text "$basename")"
        echo "<img src=\"$url\" alt=\"$alt\" class=\"alignnone shadow size-large wp-image-1000\" />"
      done
    } > "$output_file"
    
    echo "  ✓ Created: $output_file"
  fi
}

# Find all app folders (one level deep in each platform folder)
app_count=0
for platform_folder in "$APPS_DIR"/*; do
  [ -d "$platform_folder" ] || continue
  
  platform_name="$(basename "$platform_folder")"
  echo ""
  echo "=== Platform: $platform_name ==="
  
  for app_folder in "$platform_folder"/*; do
    [ -d "$app_folder" ] || continue
    
    # Skip folders that start with . or are named create-link-images.rb
    [[ "$(basename "$app_folder")" == .* ]] && continue
    [[ "$(basename "$app_folder")" == "create-link-images.rb" ]] && continue
    
    process_app_folder "$app_folder"
    app_count=$((app_count+1))
  done
done

echo ""
echo "=== Summary ==="
echo "Processed $app_count app folders"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry-run complete. No files were written."
fi

exit 0
