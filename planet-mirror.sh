#!/bin/bash
#

TODAY=$(date +"%y%m")
LASTWEEK=$(date +"%y%m" --date='7 days ago')
YEAR=$(date +"%Y")
YEARLASTWEEK=$(date +"%Y" --date='7 days ago')

WEB=/osm/planet-mirror/web

#remove older than 30 days
find $WEB/pbf -name "planet-*pbf*" -type f -mtime +30 -exec rm -f {} \;
find $WEB/planet -name "planet-*bz2*" -type f -mtime +30 -exec rm -f {} \;

#get pbf files
rsync -lptv planet.openstreetmap.org::planet/pbf/planet-$TODAY*.pbf* $WEB/pbf/
rsync -lptv planet.openstreetmap.org::planet/pbf/planet-$LASTWEEK*.pbf* $WEB/pbf/

#get bz2 files
rsync -lptv planet.openstreetmap.org::planet/planet/$YEAR/planet-$TODAY*.bz2* $WEB/planet/
#rsync -lptv planet.openstreetmap.org::planet/planet/$YEARLASTWEEK/planet-$LASTWEEK*.bz2* $WEB/planet/
