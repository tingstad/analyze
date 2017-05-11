#!/bin/bash
set -o errexit

INCLUDE="*" # Maven artifact include pattern

# Work Dir
WD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

find-modules() {
    local outfile="$WD/modules.tab"
	if [ -f "$outfile" ]; then
		echo "Using cached file: $outfile"
		return
	fi
    echo -n "" > "$outfile"
    find "$TARGET_DIR" -name pom.xml -type f -print0 \
    | while read -d $'\0' f ;do
        echo -n "Found module $f"
        local pkg="$(mvneval $f project.packaging)"
        if [ "$pkg" = "pom" ]; then
            echo " - packaging pom, skipping..."
            continue;
        fi
        echo -n " - packaging $pkg"
        local base="$(mvneval "$f" project.basedir)"
        local src="$(mvneval "$f" project.build.sourceDirectory)"
        local resources="$(mvneval "$f" project.build.resources[0].directory)"
        local id="$(artifact-id "$f")"
        echo " - $id" 
        echo -e "$id\t$pkg\t$f\t$base\t$src\t$resources" \
            >> "$outfile"
    done
}

artifact-id() {
    local f="$1"
    echo "$(mvneval "$f" project.groupId):$(mvneval "$f" project.artifactId):$(mvneval "$f" project.version)"    
}

packages() {
	echo "Finding packages"
    # Find unique packages for a module (others will be ignored)
    echo -n "" > "$WD/packages-modules.tsv"

    # 1: id, 5: src
    cut -f 1,5 "$WD/modules.tab" \
    | while read id src ;do
		if [ ! -d "$src" ]; then
			continue
		fi
        local len="${#src}"
        find "$src" -mindepth 1 -type d \
        | cut -c $[ $len + 2 ]- \
        | awk '{ print "'"$id"'\t" $0 }' 
    done \
        | awk 'BEGIN{ OFS="\t"; }
            { map[$2]=($1 "/" map[$2]); } 
            END{
                for (k in map){ 
                    v=map[k]; gsub(/[^\/]/,"",v); 
                    if(length(v)>1) 
                        delete map[k];
                }
                for (k in map){ 
                    print "2 " k " " map[k]
                    c=k;
                    while(c in map){
                        i=c;
                        gsub(/\/[^\/]*$/,"",c);
                    }
                    map2[i]=map[k];
                }
                for (k in map2){
                    v=map2[k];
                    gsub(/[\/]/,"",v);
                    gsub(/[\/]/,".",k);
                    print k,v;
                }  
            }' 
#TODO fix
#        | sort \
#        >> "$WD/packages-modules.tsv"
    
    # Packages:
    cut -f 1 "$WD/packages-modules.tsv" > "$WD/packages.txt"
}

usages() {
	echo "Finding usages"
    # One line per apparent actual package dependency:
    local outfile="$WD/deps-detailed.tsv"
    echo -n "" > "$outfile"

    cut -f 1,4,5,6 "$WD/modules.tab" \
    | while read id base src resource ;do
        find "$base" \( -path "$src/*" -or -path "$resource/*" \) -type f \
            -exec fgrep --binary-files=without-match -H -o -f "$WD/packages.txt" {} \; \
            | sed -r 's|^(.*/)?([^/]+)/src/main/([^:]+):(.+)|\2\t\3\t\4|' \
            >> "$outfile"
			#TODO sed->awk. first column id instead of dir(?)
    done 
    # detailed for debug
    
    cat "$WD/deps-detailed.tsv" \
        | cut -f 1,3 \
        | sort \
        | uniq -c \
        | sed 's/^ *//' \
        | tr ' ' \\t \
        > "$WD/deps-sum-detailed.tsv"
    
    cat "$WD/deps-sum-detailed.tsv" \
        | awk 'BEGIN{
                OFS="\t";
                while(( getline line<"'$WD/packages-modules.tsv'") > 0 ) {
                    split(line,a);
                    modul[a[1]]=a[2];
                }
            }
            {
                from=$2; to=modul[$3];
                if(from != to){
                    dep[from "/" to]+=$1;
                }
            }
            END{
                for(k in dep){
                    split(k,a,"/");
                    print a[1],a[2],dep[k];
                }
            }' \
        | sort \
        > "$WD/deps.tsv"
}

mvneval() {
    mvn -B -f "$1" org.apache.maven.plugins:maven-help-plugin:2.2:evaluate -Dexpression=$2 | grep -v '^\['
}

artifactids() {
	echo "artifact ids"
    cut -f 2 "$WD/packages-modules.tsv" \
        > "$WD/modules.txt"
    cut -f 1 "$WD/deps.tsv" \
        >>"$WD/modules.txt"
    cat "$WD/modules.txt" \
        | sort \
        | uniq \
        | while read d ;do
            f=$(find "$TARGET_DIR" -path "*/$d/pom.xml" -type f -print)
            id="$(mvneval $f project.groupId):$(mvneval $f project.artifactId):$(mvneval $f project.version)"
            echo -e "$d\t$id"
        done \
        > "$WD/modules-ids.tsv"
}

dependency-tree() {
	echo "dependency tree"
    # TODO This command assumes projects are located at depth 2 - merge with previous cmd?
    find $TARGET_DIR -mindepth 2 -maxdepth 2 -name pom.xml -type f -printf '%h\n' \
        | while read d ;do
            cd "$d" \
            && mvn -B -q dependency:tree -Dincludes=$INCLUDE -DoutputType=dot -DoutputFile=$WD/mvn.dot -DappendOutput=true \
            && cd .. 
        done
}

mvn-deps() {
	echo "mvn deps"
    cat "$WD/mvn.dot" \
        | grep '" -> "' \
        | sort \
        | uniq \
        | sed 's/\s*//g;s/->/\t/;s/"//g' \
        | awk 'BEGIN{
                OFS="\t";
                while(( getline line<"'$WD/modules-ids.tsv'") > 0 ) {
                    split(line,a);
                    id[a[1]]=a[2];
                }
                while(( getline line<"'$WD/deps.tsv'") > 0 ) {
                    split(line,a);
                    if(!id[a[1]]) print "FANT IKKE ID " a[1];
                    if(!id[a[2]]) print "FANT IKKE ID " a[2];
                    dep[id[a[1]] FS id[a[2]]]=a[3];
                }
                print "digraph {";
            }
            {
                split($1,a,":");
                from=a[1] ":" a[2] ":" a[4];
                split($2,a,":");
                to=a[1] ":" a[2] ":" a[4];
                k=(from FS to);
                if(!mvn[k]){
                    mvn[k]=1;
                    deps=dep[from FS to];
                    width=(deps ? (deps / 10) : 0); 
                    print "\"" from "\" -> \"" to "\"" (width ? " [penwidth=" width "]" : "") ";";
                }
            }
            END{
                for(k in dep){
                    if(!(k in mvn)){
                        split(k,a);
                        print "\"" a[1] "\" -> \"" a[2] "\" [penwidth=" (dep[k] / 10) ",color=red];";
                    
                    if((a[2] FS a[1]) in dep)
                        print k,"REVERSE!!!!!";
                }
                print "}";
            }' 
}

[ -n TESTMODE ] && return

main() {

    TARGET_DIR="$(readlink -f "$1")" # Dir to analyze

    find-modules
    packages
    usages
    artifactids
    dependency-tree
    mvn-deps

    echo 'digraph {' > "$WD/mvn-deps.dot"
    cat "$WD/mvn.dot" \
        | grep '" -> "' \
        | sort \
        | uniq \
        >> "$WD/mvn-deps.dot"
    echo '}' >> "$WD/mvn-deps.dot"
}

