#!/bin/sh
# Matija Nalis <mnalis-osmplanetbt@voyager.hr> started 20201119, MIT licence
# Downloads planet*.pbf and planet*.osm.bz2 files fast using aria2c, and check for race conditions and data corruption.
#
# Requirements: "sudo apt-get install wget aria2 psmisc"

# Note: $TMP must have enough space to hold big files being downloaded (and preferably be on same filesystem as $WEB)
TMP=/osm/planet-mirror/tmp
# WEB directory where files will be published (your public_html or subfolder)
WEB=/osm/planet-mirror/web
# Verbosity: from 0=errors to 5=debug
VERBOSE=4
# Random wait inteval of $WAIT +-50% when before downloading files from planet.openstreetmap.org
WAIT=1m
# Delete files older than $MAXDAYS days from your $WEB directory
MAXDAYS=32
# Prealloc: "none" (use sparse files, allocates spaces as download goes) or "falloc" (reduces fragmentation, eats disk space and fails immedeately if not enough space)
PREALLOC="none"
# Aria2 max parallel connections
PARALLEL=16

#
# no user-configurable parts below
#
YEAR=$(date +"%Y")
YEARLASTWEEK=$(date +"%Y" --date='7 days ago')
WGET_OPT="-q --no-hsts --wait=$WAIT --random-wait"
ARIA2_LOG="aria2.$$.log"
ARIA2_OPT="--file-allocation=$PREALLOC --follow-torrent=true --seed-time=0 -s $PARALLEL -j $PARALLEL  --quiet --log=${ARIA2_LOG} --log-level=notice"

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
	PREFIX="$1"
	EXT="$2"
	SUB="$3"
	MAX="$4"

	SUB2="`printf $SUB | tr / _`"
	HTML="index_${SUB2}.html"
	SUBDIR="${SUB}/"
	URL_BASE=https://planet.openstreetmap.org/$SUBDIR
	DEST_DIR="${WEB}/${SUBDIR}"

	test -d "$DEST_DIR" || mkdir "$DEST_DIR"
	if [ ! -d "${DEST_DIR}." ]
	then
		logger 0 "FATAL ERROR: script error: destination subdirectory $DEST_DIR does not exist"
		return 33
	fi

	logger 5 "DEBUG: download/update list of torrents at ${URL_BASE} to $HTML"
	wget $WGET_OPT -N --no-if-modified-since --default-page $HTML $URL_BASE
	NEWEST_TORRENT=$(sed -ne 's/^.*href="\('${PREFIX}'-[a-z0-9\.\-]*\.torrent\)".*$/\1/p' $HTML | grep -v latest | sort -ru | head -n1)
	logger 5 "DEBUG: newest torrent from $HTML for prefix $PREFIX determined to be ${NEWEST_TORRENT}"
	NEWEST_FILE=`basename $NEWEST_TORRENT .torrent`

	if [ -z "$NEWEST_TORRENT" ]
	then
		logger 2 "WARNING: No .torrent files found at $URL_BASE (if we have just entered new year, we will retry with previous year)"
		return 1
	fi

	if [ -f "${NEWEST_FILE}" -o -f "${NEWEST_FILE}.torrent" -o -f "${NEWEST_FILE}.aria2" ] && fuser -s ${NEWEST_FILE}*
	then
		logger 1 "WARNING: another process is using ${NEWEST_FILE}*, skipping download"
		return 2
	fi

	if [ -f "${DEST_DIR}${NEWEST_FILE}" ]
	then
		logger 4 "INFO: skipping download of already published ${DEST_DIR}${NEWEST_FILE}"
		return 0
	fi

	# get newest .torrent
	logger 5 "DEBUG: download/update ${URL_BASE}${NEWEST_TORRENT}"
	wget $WGET_OPT -N "${URL_BASE}${NEWEST_TORRENT}"

	# download FAST everything contained in .torrent
	logger 5 "DEBUG: aria2 download files from ${URL_BASE}${NEWEST_TORRENT}"
	aria2c $ARIA2_OPT -x$MAX "${NEWEST_TORRENT}"

	# get newest .md5
	NEWEST_MD5="${NEWEST_FILE}.md5"
	logger 5 "DEBUG: download/update MD5 ${URL_BASE}${NEWEST_MD5}"
	rm -f "${NEWEST_MD5}"
	wget $WGET_OPT -N "${URL_BASE}${NEWEST_MD5}"

	# verify MD5
	logger 5 "DEBUG: verifying MD5 ${NEWEST_MD5}"
	md5sum --check --quiet "$NEWEST_MD5" || return 3
	logger 5 "DEBUG: successful MD5 check of ${NEWEST_MD5}, publishing files"

	mv -f $NEWEST_FILE "$DEST_DIR${NEWEST_FILE}.tmp" && mv -f "$DEST_DIR${NEWEST_FILE}.tmp" "$DEST_DIR${NEWEST_FILE}" && \
	cp -af $NEWEST_TORRENT $DEST_DIR && \
	mv -f $NEWEST_MD5  $DEST_DIR && \
	logger 3 "NOTICE: $NEWEST_FILE downloaded OK."

	return 0
}

# get yearly version of torrent - just append $YEAR (or $YEARLASTWEEK if newyear) to subdir
get_torrent_with_year() {
	Y_PREFIX="$1"
	Y_EXT="$2"
	Y_SUB="$3"
	Y_MAX="$4"

	# get latest torrent in current $YEAR, but if there are none, fall back to $YEARLASTWEEK
	if ! get_torrent "$Y_PREFIX" "$Y_EXT" "${Y_SUB}/${YEAR}" $Y_MAX
	then
		[ "$YEAR" != "$YEARLASTWEEK" ] && get_torrent "$Y_PREFIX" "$Y_EXT" "${Y_SUB}/${YEARLASTWEEK}" $Y_MAX
	fi
}

#
# remove files older than $MAXDAYS days
#

logger 5 "DEBUG: removing files older than $MAXDAYS days"
find $WEB/pbf -name "history-*.pbf*" -type f -mtime +$MAXDAYS -exec rm -f {} \;
find $WEB/pbf -name "planet-*.pbf*" -type f -mtime +$MAXDAYS -exec rm -f {} \;
find $WEB/planet -name "history-*.bz2*" -type f -mtime +$MAXDAYS -exec rm -f {} \;
find $WEB/planet -name "planet-*.bz2*" -type f -mtime +$MAXDAYS -exec rm -f {} \;
find $WEB/planet -name "changesets-*.bz2*" -type f -mtime +$MAXDAYS -exec rm -f {} \;
find $WEB/planet -name "discussions-*.bz2*" -type f -mtime +$MAXDAYS -exec rm -f {} \;

#
# download files
#

get_torrent "planet" "pbf" "pbf" 4
#get_torrent "history" "pbf" "pbf/full-history" 1

get_torrent_with_year "planet" "bz2" "planet" 1
#get_torrent_with_year "changesets" "bz2" "planet" 1
#get_torrent_with_year "discussions" "bz2" "planet" 1
#get_torrent_with_year "history" "bz2" "planet/full-history" 1

test -f ${ARIA2_LOG} && mv -f ${ARIA2_LOG} aria2.log.old

logger 5 "DEBUG: $0 script finished."
