#!/bin/sh
# Matija Nalis <mnalis-osmplanetbt@voyager.hr> started 20201119, MIT licence
# Downloads planet*.pbf and planet*.osm.bz2 files fast using aria2c, and check for race conditions and data corruption.
#
# Requirements: "sudo apt-get install wget aria2 psmisc"

# Note: $TMP must have enough space to hold big files being downloaded (and preferably be on same filesystem as $WEB)
TMP=/osm/planet-mirror/tmp
# WEB directory where files will be published (your public_html or subfolder)
WEB=/osm/planet-mirror/web
# Verbosity: 0=error only, 3=all messages
VERBOSE=3
# Random wait inteval of $WAIT +-50% when before downloading files from planet.openstreetmap.org
WAIT=1m
# Delete files older than $MAXDAYS days from your $WEB directory
MAXDAYS=32
# Prealloc: "none" (use sparse files, allocates spaces as download goes) or "falloc" (reduces fragmentation, eats disk space and fails immedeately if not enough space)
PREALLOC="none"

#
# no user-configurable parts below
#
YEAR=$(date +"%Y")
YEARLASTWEEK=$(date +"%Y" --date='7 days ago')
WGET_OPT="-q --no-hsts --wait=$WAIT --random-wait"
ARIA2_OPT="--file-allocation=$PREALLOC --follow-torrent=true --quiet"

# log text with timestamp, if user wants us to be that $VERBOSE
logger() {
	LOGLEVEL="$1"
	MSG="$2"
	[ "$VERBOSE" -ge $LOGLEVEL ] &&  echo "`date --rfc-3339=seconds` $MSG"
}

#
# sanity check for directories we're going to use
#

if [ ! -d $WEB ]
then
	logger 0 "FATAL ERROR: web directory $WEB does not exist"
	exit 31
fi

test -d "$TMP" || mkdir "$TMP"
if ! cd $TMP
then
	logger 0 "FATAL ERROR: temp directory $TMP does not exist"
	exit 32
fi

# this works, but is not optimal:
#   wget --no-hsts -nv 'https://planet.openstreetmap.org/pbf/?C=M;O=D' -nd  -w3 -L   -Q100k -r  -l1 -R tmp -R 1 -R html -E --accept-regex '.*torrent

# This is optimized version doing minimal network access
# if things misbehave after a system crash, you may want to clear $TMP dir
get_torrent() {
	SUBDIR=$1
	HTML=$2
	MAX=$3
	URL_BASE=https://planet.openstreetmap.org/$SUBDIR
	DEST_DIR="${WEB}/${SUBDIR}"
	test -d "$DEST_DIR" || mkdir "$DEST_DIR"
	if [ ! -d "${DEST_DIR}." ]
	then
		logger 0 "FATAL ERROR: script error: destination subdirectory $DEST_DIR does not end with /"
		return 33
	fi

	wget $WGET_OPT -N --no-if-modified-since --default-page $HTML $URL_BASE
	NEWEST_TORRENT=$(sed -ne 's/^.*href="\([a-z0-9\.\-]*\.torrent\)".*$/\1/p' $HTML | sort -ru | head -n1)
	NEWEST_FILE=`basename $NEWEST_TORRENT .torrent`

	if [ -z "$NEWEST_TORRENT" ]
	then
		logger 1 "WARNING: No .torrent files found at $URL_BASE, happy new year? (will retry with previous year)"
		return 1
	fi

	if fuser -s ${NEWEST_FILE}*
	then
		logger 0 "WARNING: another process is using ${NEWEST_FILE}*, skipping download"
		return 2
	fi

	if [ -f "$DEST_DIR${NEWEST_FILE}" ]
	then
		logger 3 "INFO: skipping download of already published $DEST_DIR${NEWEST_FILE}"
		return 0
	fi

	# if newest .torrent is not yet downloaded, or if main transfer was interrupted, try downloading (again)
	if [ ! -f "$NEWEST_TORRENT" -o -f "${NEWEST_FILE}.aria2" ]
	then
		# get newest .torrent, and everything contained in it!
		wget $WGET_OPT -N "${URL_BASE}${NEWEST_TORRENT}"
		aria2c $ARIA2_OPT -x$MAX -s$MAX "${NEWEST_TORRENT}"

		# get newest .md5
		NEWEST_MD5="${NEWEST_FILE}.md5"
		wget $WGET_OPT -N "${URL_BASE}${NEWEST_MD5}"

		# verify MD5
		md5sum --check --quiet "$NEWEST_MD5" || return 3

		mv -f $NEWEST_FILE "$DEST_DIR${NEWEST_FILE}.tmp" && mv -f "$DEST_DIR${NEWEST_FILE}.tmp" "$DEST_DIR${NEWEST_FILE}" && \
		cp -af $NEWEST_TORRENT $DEST_DIR && \
		mv -f $NEWEST_MD5  $DEST_DIR && \
		logger 2 "NOTICE: $NEWEST_FILE downloaded OK."
	fi
	return 0
}

#
# remove files older than $MAXDAYS days
#

find $WEB/pbf -name "planet-*.pbf*" -type f -mtime +$MAXDAYS -exec rm -f {} \;
find $WEB/planet -name "planet-*.bz2*" -type f -mtime +$MAXDAYS -exec rm -f {} \;

#
# download files
#

get_torrent pbf/ index_pbf.html 4
#get_torrent pbf/full-history/ index_history.html 1

# get latest torrent in current $YEAR, but if there are none, fall back to $YEARLASTWEEK
if ! get_torrent "planet/$YEAR/" "index_planet_bz2_${YEAR}.html" 1
then
	get_torrent "planet/$YEARLASTWEEK/" "index_planet_bz2_${YEARLASTWEEK}.html" 1
fi
