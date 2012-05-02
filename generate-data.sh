#!/bin/bash

BUCKET_BASE=BUCKET%
BUCKET_COUNT=$(($RANDOM % 128))
KEY_BASE=KEY%
KEY_COUNT=$(($RANDOM % 65536))
HOST_LIST=(127.0.0.1:8098)
DATA_SIZE=128
DATA_SOURCE=/dev/random
VERBOSE=0
MAXPROC=$((`ulimit -u` / 2))

while [ "${1:0:1}" = "-" -a  "${#1}" -gt 1 ]; do
 case ${1:1} in
      k=* | keys=*)
	arry=(${1/=/ })
	KEY_COUNT=${arry[1]}
	unset arry
	shift
	;;
      k | keys)
	shift
	KEY_COUNT=$1
	shift
	;;
      K=* | KEY=*)
	arry=(${1/=/ })
	KEY_BASE=${arry[1]}
	[ "${KEY_BASE//%/}" = "$KEY_BASE" ] && KEY_BASE="${KEY_BASE}%"
	unset arry
	shift
	;;
      K | KEY)
	shift
	KEY_BASE=$1
	shift
	[ "${KEY_BASE//%/}" = "$KEY_BASE" ] && KEY_BASE="${KEY_BASE}%"
	;;
      b=* | buckets=*)
	arry=(${1/=/ })
	BUCKET_COUNT=${arry[1]}
	unset arry
	shift
	;;
      b | buckets)
	shift
	BUCKET_COUNT=$1
	shift
	;;
      B=* | BUCKET=*)
	arry=(${1/=/ })
	BUCKET_BASE=${arry[1]}
	[ "${BUCKET_BASE//%/}" = "$BUCKET_BASE" ] && BUCKET_BASE="${BUCKET_BASE}%"
	unset arry
	shift
	;;
      B | BUCKET)
	shift
	BUCKET_BASE=$1
	shift
	[ "${BUCKET_BASE//%/}" = "$BUCKET_BASE" ] && BUCKET_BASE="${BUCKET_BASE}%"
	;;
      d=* | size=*)
	arry=(${1/=/ })
	DATA_SIZE=${arry[1]}
	unset arry
	shift
	;;
      d | size)
	shift
	DATA_SIZE=$1
	shift
	;;
      m | maxproc)
	shift
	MAXPROC=$1
	shift
	;;
      m=* | maxproc=*)
	arry=(${1/=/ })
        MAXPROC=${arry[1]}
	unset arry
	shift
	;;
      data=*)
	arry=(${1/=/ })
	DATA_SOURCE=${arry[1]}
	unset arry
	shift
	;;
      data)
	shift
	DATA_SOURCE=$1
	shift
	;;
      v)
	shift
	VERBOSE=1
	if [ -n "$1" -a "${1//[^0-9]/}" = "$1" ]; then
		VERBOSE=$1
		shift
	fi
	;;
      v=*)
	arry=(${1/=/ })
	VERBOSE=${arry[1]}
	unset arry
	shift
	;;
      pw)
	shift
	PW=$1
	shift
	;;
      pw=*)
	arry=(${1/=/ })
        PW=${arry[1]}
        unset arry
        shift
        ;;
      dw)
	shift
	DW=$1
	shift
	;;
      dw=*)
	arry=(${1/=/ })
        DW=${arry[1]}
        unset arry
        shift
        ;;
      *)
	echo "Unknown flag $1"
	exit
	;;
 esac
done

[ $# -gt 0 ] && HOST_LIST=($*)

if [ $VERBOSE -gt 0 ]; then
 echo "BUCKET_BASE: $BUCKET_BASE"
 echo "BUCKET_COUNT: $BUCKET_COUNT"
 echo "KEY_BASE: $KEY_BASE"
 echo "KEY_COUNT: $KEY_COUNT"
 echo "HOST: ${HOST_LIST[*]}"
 echo "DATA_SIZE: $DATA_SIZE"
 echo "VERBOSE LEVEL: $VERBOSE"
 echo "..."
fi

opts=""
gets=""
if [ -n "$PW" ]; then
 [ -z "$gets" ] && gets="?" || gets="${gets}&"
 opts="$opts with pw=$PW"
 gets="${gets}pw=$PW"
fi
if [ -n "$DW" ]; then
 [ -z "$gets" ] && gets="?" || gets="${gets}&"
 opts="$opts with dw=$DW"
 gets="${gets}dw=$DW"
fi
echo "Writing $DATA_SIZE bytes data in $KEY_COUNT keys to $BUCKET_COUNT buckets using ${#HOST_LIST[*]} nodes$opts."

bucket_sub=""
key_sub=""
hostidx=0;
proccnt=0;
for i in `seq 1 $BUCKET_COUNT`; do
	[ $BUCKET_COUNT -gt 1 ] && bucket_sub=`printf "%03X" $i`
	bucket=${BUCKET_BASE//%/$bucket_sub}
	[ $VERBOSE = 1 ] && echo "Putting $KEY_COUNT keys in bucket '$bucket'" 
	for j in `seq 1 $KEY_COUNT`; do
		[ $KEY_COUNT -gt 1 ] && key_sub=`printf "%03X" $j`	
		host=${HOST_LIST[$hostidx]}
		key=${KEY_BASE//%/$key_sub}
		[ $VERBOSE = 2 ] && echo -e -n "\rPutting $DATA_SIZE bytes in key '$key' in bucket '$bucket' using node '$host'$opts" 
		[ $VERBOSE -gt 2 ] && echo dd if=$DATA_SOURCE bs=1 count=$DATA_SIZE 2\>/dev/null \| curl -s $host/BUCKETS/$bucket/KEYS/$key$gets -X PUT -H "content-type: application/octet-stream" --data-binary @-
		dd if=$DATA_SOURCE bs=1 count=$DATA_SIZE </dev/null 2>/dev/null | curl -s $host/buckets/$bucket/keys/$key$gets -X PUT -H "content-type: application/octet-stream" --data-binary @- 2>&1 >/dev/null &
		proccnt=$(($proccnt + 1))
		hostidx=$((hostidx + 1))
		if [ $hostidx -ge ${#HOST_LIST[*]} ]; then
			hostidx=0
		fi
		while [ $proccnt -gt $MAXPROC ]; do 
			sleep 0.1 
			proccnt=`ps | grep 'curl -s' | wc -l`
		done	
	done
done
