#!/bin/bash
#

TODAY=$(date +"%y%m")
LASTWEEK=$(date +"%y%m" --date='7 days ago')

echo $TODAY
echo $LASTWEEK

WEB=/osm/planet-mirror/web

rsync -lptv planet.openstreetmap.org::planet/pbf/planet-$TODAY*.pbf* $WEB/pbf
rsync -lptv planet.openstreetmap.org::planet/pbf/planet-$LASTWEEK*.pbf* $WEB/pbf

#remove older than 30 days
find $WEB/planet -name "planet-*pbf*" -type f -mtime +30 -exec rm -f {} \;