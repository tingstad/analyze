./seopp-anon.sh |\
( read -r -d '' APPEND <<- EOF
	"kunde" -> "kjerne" [label=http style=dashed];
	"admin" -> "kjerne" [label=http style=dashed];
	"fitnesse-server" -> "kunde" [label=http style=dashed];
	subgraph luster_db{
	    rank=sink;
	    "DB admin"[shape="cylinder"];
	    "DB kjerne"[shape="cylinder"];
	}
	"datalag-admin" -> "DB admin" [penwidth=5.6];
	"datalag-kjerne" -> "DB kjerne" [penwidth=1.2];
	"admin" -> "DB admin" [color=red]; /* MobilOgNettbrettRepo */
	"kjerne" -> "DB kjerne" [color=red]; /* KundedataService */
	"datalag-admin" -> "DB kjerne" [color=red]; /* KjerneRepository */
	"fitnesse-server" -> "DB kjerne" [color=red]; /* automatiserttest.fitnesse.database */
	"kunde" -> "mocklogin" [color=gray];
	"mocklogin" -> "DB kjerne" [color=red]; /* UtfyllingLaster */
	"kunde" -> "kunde-innganger";
	"kunde" -> "jetty-kunde";
	"kunde-deploy" -> "kunde";
	"kunde-deploy" -> "jetty-kunde";
	"admin" -> "jetty-admin";
	"admin-deploy" -> "admin";
	"admin-deploy" -> "jetty-admin";
	"kjerne-deploy" -> "kjerne";
	"kunde" -> "db-server" [color=gray];
	"admin" -> "db-server" [color=gray];
EOF
awk -v append="$APPEND" '{
    if ($0 ~ /^"(kunde|admin|kjerne|fitnesse-server|ytelsestest)" \[/)
        app[$0]=1
    else if ($0 ~ /"sb1\./) {
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
}' \
| sed -r 's/"sb1.[^:]+:/"/g'
)

