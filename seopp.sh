sed -r 's/"[^"]*seopp-([^:]+):[0-9.]*-SNAPSHOT"/"\1"/g' |\
( read -r -d '' APPEND << EOF
"kunde" -> "kjerne" [label=http style=dashed];
"admin" -> "kjerne" [label=http style=dashed];
subgraph luster_db{
rank=sink;
"DB admin"[shape="cylinder"];
"DB kjerne"[shape="cylinder"];
}
"datalag-admin" -> "DB admin" [penwidth=5.6];
"datalag-kjerne" -> "DB kjerne" [penwidth=1.2];
"admin" -> "DB admin" [color=red]; /* MobilOgNettbrettRepo */
"kjerne" -> "DB kjerne" [color=red]; /* KundedataService */
"datalag-admin" -> "DB kjerne" [color=red]; */ KjerneRepository */
EOF
awk -v append="$APPEND" '{
    if ($0 ~ /^"(kunde|admin|kjerne|ytelsestest)" \[/)
        app[$0]=1
    else if ($0 ~ /"sb1\.[^"]+"/) {
        sb[substr($0, index($0, "\"sb1."))]=1
        print
    }
    else if ($0 ~ /^}$/) {
        print append
        print "subgraph app{ rank=source;"
        for (k in app)
            print k
        print "}"
        print "subgraph { rank=same;"
        for (k in sb)
            print k
        print "}"
        print
    }
    else
        print
}' )

