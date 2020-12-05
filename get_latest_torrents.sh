#!/bin/sh
# Matija Nalis <mnalis-osmplanetbt@voyager.hr> started 20201119, MIT licence
cd ~/osm || exit 31
WAIT=10m
MAXWEEKS=3
WOPT="-q --no-hsts --wait=$WAIT --random-wait"

# this works, but is not optimal:
# wget --no-hsts -nv 'https://planet.openstreetmap.org/pbf/?C=M;O=D' -nd  -w3 -L   -Q100k -r  -l1 -R tmp -R 1 -R html -E --accept-regex '.*torrent

# This is optimized version doing minimal network access
get_torrent() {
	URL=https://planet.openstreetmap.org/$1
	HTML=$2
        wget $WOPT -N --no-if-modified-since --default-page $HTML $URL
        TORRENT=$(sed -ne 's/^.*href="\([a-z0-9\.\-]*\.torrent\)".*$/\1/p' $HTML | sort -ru | head -n1)
        if [ ! -f "$TORRENT" ]
        then
        	wget $WOPT -N "$URL$TORRENT"
        	
        	# we use transmission-daemon; those two lines add new torrent, and remove oldest .osm.pbf (as we don't have infinite disk space)
        	transmission-remote -a "$TORRENT"
        	# tail -n +3 means delete 3rd and more torrents (eg. keep only latest 2)
        	transmission-remote -l | awk '/\.osm\.pbf$/ { print $1 }' | tac  | tail -n +$MAXWEEKS | xargs -r -i transmission-remote -t {} --remove-and-delete
        fi
}

get_torrent pbf/ index_pbf.html
#get_torrent pbf/full-history/ index_history.html
