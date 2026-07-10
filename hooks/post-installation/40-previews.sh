#!/bin/bash
# post-installation hook: reproduce preview config from the previous instance.
# Runs once on a fresh install.
#
# Note: OC\Preview\Imaginary (last provider) needs the imaginary backend + a
# NC_preview_imaginary_url in nextcloud.env; the Movie/MKV/MP4/AVI providers need
# ffmpeg (already added by nextcloud/Dockerfile).
# Hooks already run as www-data (entrypoint uses `su -p www-data`), so call occ directly.
set -euo pipefail

occ() { php /var/www/html/occ "$@"; }

# Scalars (types match the source config.php: integers/boolean where noted).
occ config:system:set enable_previews          --type=boolean --value=true
occ config:system:set preview_max_x            --type=integer --value=2048
occ config:system:set preview_max_y            --type=integer --value=2048
occ config:system:set preview_max_memory       --type=integer --value=4096
occ config:system:set jpeg_quality             --type=integer --value=80
occ config:system:set preview_concurrency_all  --type=integer --value=6
occ config:system:set preview_concurrency_new  --type=integer --value=5

# Enabled preview providers, in the same order as the source config.
providers=(
  Font JPEG GIF HEIC XBitmap Movie PDF Image TXT MarkDown
  Epub TIFF MKV MP4 AVI PNG SVG Imaginary
)

# Reset any providers the fresh install enabled by default, then set ours by index.
# (bash turns \\ into \, so php receives e.g. OC\Preview\Font)
occ config:system:delete enabledPreviewProviders
i=0
for p in "${providers[@]}"; do
  echo "enabledPreviewProviders[$i] = OC\\Preview\\$p"
  occ config:system:set enabledPreviewProviders "$i" --value="OC\\Preview\\$p"
  i=$((i + 1))
done

# Preview Generator: extra square preview for the Memories app timeline view.
# https://github.com/nextcloud/previewgenerator#im-using-the-memories-app
# (previewgenerator is installed by 10-install-apps.sh, which runs before this.)
echo "previewgenerator coverWidthHeightSizes = 256"
occ config:app:set previewgenerator coverWidthHeightSizes --value=256
