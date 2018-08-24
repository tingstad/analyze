#!/bin/bash
set -o errexit

FILE="kfp-app.dot"
if [ -n "$1" ]; then
    [ -f "$1" ]
    FILE="$1"
elif [ ! -f kfp-app.dot ]; then
    ./analyze.sh -s -o kfp-app.dot ../kfp-app/
fi

APPEND="$(cat - <<- EOF
	"kfp-app-documents" -> "kfp-app-core-webapp" [style=dotted,color=red];
EOF
)"

cat "$FILE" \
| sed -n '/->/!p; /-> "sb1/p; /-> "no/p' \
| sed -r 's/"(sb1|no)[^:]*:/"/g' \
| sed '/kfp-app-example/d' \
| sed 's/:[5-9][0-9][.0-9]*-SNAPSHOT//g' \
| sed 's/\[penwidth=[0-9.]*\]//;s/penwidth=[0-9.]*,//' \
| sed 's/style=dashed/&,color=red/' \
| awk -v append="$APPEND" '{
    if ($0 ~ /^"kfp-(app-core-webapp|jetty)" \[/)
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

