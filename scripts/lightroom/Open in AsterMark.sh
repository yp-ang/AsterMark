#!/bin/sh
# Lightroom Classic post-processing action: after an export, open the export folder in AsterMark.
# Install: copy this file to ~/Library/Application Support/Adobe/Lightroom/Export Actions/
# then choose it under Export ▸ Post-Processing ▸ After Export.
# The folder (not the individual files) is opened so AsterMark gets access to the whole album.
[ -n "$1" ] && open -a AsterMark "$(dirname "$1")"
