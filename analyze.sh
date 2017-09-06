#!/bin/bash
set -o errexit

INCLUDE="*" # Maven artifact include pattern

# Work Dir
WD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

main() {
    local includes="*"
    while getopts ":hi:" opt; do
        case $opt in
            h)
                print_usage_and_exit
                ;;
            i)
                includes="$OPTARG"
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                print_usage_and_exit
                ;;
            :)
                echo "Option -$OPTARG requires an argument" >&2
                print_usage_and_exit
                ;;
        esac
    done
    if [ $[ $# - $OPTIND ] -gt 0 ]; then
        echo "Too many arguments." >&2
        print_usage_and_exit
    fi
    shift $((OPTIND-1))
    if [ -z "$1" -o ! -d "$1" ]; then
        print_usage_and_exit
    fi
    TARGET_DIR="$(cd "$1" && pwd)" # Dir to analyze

    find_modules
    packages
    usages
    dependency_tree
    # mvn dependency:analyze |awk "/Used undeclared/{s++} /Unused declared/{s--} s && / "$INCLUDE":/{print}" 
    mvn_deps
}

print_usage_and_exit() {
        cat <<- EOF >&2
			Usage: $0 [OPTION...] DIR
			
			  -h    help
		EOF
        exit 1
}

find_modules() {
    local outfile="$WD/modules.tab"
    if [ -f "$outfile" ]; then
        echo "Using cached file: $outfile"
        # TODO check hash of mvn org.apache.maven.plugins:maven-help-plugin:2.2:effective-pom
        # to increase performance
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
        echo -e "${id}\t${pkg}\t${f}\t${base}\t${src}\t${resources}" \
            >> "$outfile"
    done
}

artifact-id() {
    local f="$1"
    local o="$WD/effective-pom.xml"
    mvn -B -q -f "$f" org.apache.maven.plugins:maven-help-plugin:2.2:effective-pom -Doutput="$o"
    cat "$o" \
        | artifact-id-from-pom
}

artifact-id-from-pom() {
    sed '/<parent>/,/<\/parent>/d' \
        | awk '
            function content(tag) {
                s = substr(tag, index(tag, ">")+1);
                return substr(s, 1, index(s, "<")-1);
            }
            !a && /<artifactId>/ { a=content($0) }
            !g && /<groupId>/ { g=content($0) }
            !v && /<version>/ { v=content($0) }
            END { print g ":" a ":" v }'
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
            # map[pkg] = id1/id2/
            END{
                # delete packages not unique to a single module
                for (k in map){ 
                    v=map[k]; gsub(/[^\/]/,"",v); 
                    if(length(v)>1) 
                        delete map[k];
                }
                # keep only deepest packages
                for (k in map){ 
                    c=k;
                    while(c in map){
                        i=c;
                        gsub(/\/[^\/]*$/,"",c);
                    }
                    map2[i]=map[k];
                }
                # print results
                for (k in map2){
                    v=map2[k];
                    gsub(/[\/]/,"",v);
                    gsub(/[\/]/,".",k);
                    print k,v;
                }  
            }' \
        | sort \
        >> "$WD/packages-modules.tsv"
    
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
            -exec fgrep --color=never --binary-files=without-match -H -o -f "$WD/packages.txt" {} \; \
            | awk -F: 'BEGIN{OFS="\t"} {
                        d[1]="'"$src"'"; d[2]="'"$resource"'";
                        for(s in d){
                            if(index($1,d[s])==1) {
                                $1=substr($1,length(d[s])+2);
                                break;
                            }
                        } print "'"$id"'",$1,$2; }' \
            >> "$outfile"
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

dependency_tree() {
    echo "dependency tree"
    cut -f 3,4 "$WD/modules.tab" \
        | while read pom base ;do
            (cd "$base" && mvn -B -q dependency:tree -Dincludes="$INCLUDE" -DoutputType=dot -DoutputFile="$WD/mvn.dot" -DappendOutput=true)
        done
}

# reads mvn.dot and deps.tsv
# to create result dot graph
mvn_deps() {
    echo "mvn deps"
    echo 'digraph {' > "$WD/mvn-deps.dot"
    cat "$WD/mvn.dot" \
        | grep '" -> "' \
        | sort \
        | uniq \
        >> "$WD/mvn-deps.dot"
    echo '}' >> "$WD/mvn-deps.dot"
    cat "$WD/mvn-deps.dot" \
        | grep '" -> "' \
        | sed 's/\s*//g;s/->/\t/;s/"//g' \
        | awk 'BEGIN{
                OFS="\t";
                while(( getline line<"'"$WD/deps.tsv"'") > 0 ) {
                    split(line,a);
                    dep[a[1] FS a[2]]=a[3];
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
                    } 
                    if((a[2] FS a[1]) in dep)
                        print k,"REVERSE!!!!!";
                }
                print "}";
            }' 
}


[ -n "$TESTMODE" ] && return

main $@

