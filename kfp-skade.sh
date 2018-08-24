#!/bin/bash
set -o errexit

DIR="$(cd "$(dirname "$0")" && pwd)"

FILE="$DIR/kfp-skade.dot"
if [ -n "$1" ]; then
    [ -f "$1" ]
    FILE="$1"
elif [ ! -f "$FILE" ]; then
    "$DIR/analyze.sh" -s -o "$FILE" ~/git/kfp-skade/
fi

APPEND="$(cat - <<- EOF
	#
EOF
)"

cat "$FILE" \
| sed -n '/->/!p; /-> "sb1/p; /-> "no/p' \
| sed -r 's/"(sb1|no)[^:]*:/"/g' \
| sed 's/:[0-9][0-9.]*\(-SNAPSHOT\)*//g' \
| sed 's/\[penwidth=[0-9.]*\]//;s/penwidth=[0-9.]*,//' \
| sed 's/style=dashed/&,color=red/' \
| awk -v append="$APPEND" '{
    if ($0 ~ /^"kfp-skade-server" \[/)
        app[$0] = 1
    else if ($0 ~ /^}$/) {
        print append
        print "subgraph app{ rank=source;"
        for (k in app)
            print k
        print "}"
        print
    }
    else
        print
}'

