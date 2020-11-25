#!/bin/bash
#

TODAY=$(date +"%y%m")
LASTWEEK=$(date +"%y%m" --date='7 days ago')
YEAR=$(date +"%Y")
YEARLASTWEEK=$(date +"%Y" --date='7 days ago')

WEB=/osm/planet-mirror/web

#remove older than 32 days
find $WEB/pbf -name "planet-*pbf*" -type f -mtime +32 -exec rm -f {} \;
find $WEB/planet/$YEAR -name "planet-*bz2*" -type f -mtime +32 -exec rm -f {} \;

#get pbf files
rsync -lptv planet.openstreetmap.org::planet/pbf/planet-$TODAY*.pbf* $WEB/pbf/
# get pbf from last week in case of month change
if [ $TODAY != $LASTWEEK ]
then
	rsync -lptv planet.openstreetmap.org::planet/pbf/planet-${LASTWEEK}2*.pbf* $WEB/pbf/
	rsync -lptv planet.openstreetmap.org::planet/pbf/planet-${LASTWEEK}3*.pbf* $WEB/pbf/
fi

#get bz2 files
#rsync -lptv planet.openstreetmap.org::planet/planet/$YEAR/planet-$TODAY*.bz2* $WEB/planet/$YEAR
#if [ $TODAY != $LASTWEEK ]
#then
#	rsync -lptv planet.openstreetmap.org::planet/planet/$YEARLASTWEEK/planet-${LASTWEEK}2*.bz2* $WEB/planet/$YEARLASTWEEK
#	rsync -lptv planet.openstreetmap.org::planet/planet/$YEARLASTWEEK/planet-${LASTWEEK}3*.bz2* $WEB/planet/$YEARLASTWEEK
#fi