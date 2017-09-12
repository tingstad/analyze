#!/bin/bash
set -o errexit

# Work Dir
WD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TMPDIR="$(mktemp -d)"

main() {
    while getopts ":hi:o:q" opt; do
        case $opt in
            h) print_usage_and_exit 0 ;;
            i) includes="$OPTARG" ;;
            o) outputfile="$OPTARG" ;;
            q) quiet=1 ;;
            \?)echo "Invalid option: -$OPTARG" >&2
               print_usage_and_exit ;;
            :) echo "Option -$OPTARG requires an argument" >&2
               print_usage_and_exit ;;
        esac
    done
    if [ $[ $# - $OPTIND ] -gt 0 ]; then
        echo "Too many arguments." >&2
        print_usage_and_exit
    fi
    shift $((OPTIND-1))
    if [ -z "$1" ]; then
        echo "Missing target dir parameter" >&2
        print_usage_and_exit
    elif [ ! -d "$1" ]; then
        echo "'$1' is not a directory" >&2
        print_usage_and_exit
    fi
    local target_dir="$(cd "$1" && pwd)" # Dir to analyze
    if [ -n "$quiet" ]; then
        exec 3>/dev/null
    else
        exec 3>&1
    fi

    find_modules "$target_dir" >&3
    packages >&3
    usages >&3
    dependency_tree "${includes:-*}" >&3
    # mvn dependency:analyze |awk "/Used undeclared/{s++} /Unused declared/{s--} s && / "$includes":/{print}" 
    echo "mvn deps" >&3
    if [ -n "$outputfile" ]; then
        mvn_deps > "$outputfile"
    else
        mvn_deps
    fi
}

print_usage_and_exit() {
    local exit_code=${1-1}
    if [ $exit_code -eq 0 ]; then
        print_usage
    else
        print_usage >&2
    fi
    exit $exit_code
}

print_usage() {
    cat <<- EOF
		Usage: $0 [OPTION...] DIR
		
		  -h            Help
		  -i pattern    Filter dependencies using pattern. Syntax is
		                [groupId]:[artifactId]:[type]:[version]
		  -o filename   Write output to file
		  -q            Quiet
	EOF
}

find_modules() {
    local target_dir="$1"
    local outfile="$WD/modules.tab"
    find "$target_dir" -name pom.xml -type f -print0 \
    | while read -d $'\0' f ;do
        echo -n "Found module $f"
        local id_and_fp="$(id_and_fingerprint "$f")"
        local id="$(echo "$id_and_fp" | cut -f 1)"
        local fingerprint="$(echo "$id_and_fp" | cut -f 2)"
        local existing=$(awk "\$1 == \"$id\" { print \$7 }" "$outfile" 2>/dev/null || echo "na")
        if [ $fingerprint = "$existing" ]; then
            echo " - $id"
            continue
        else
            [ -f "$outfile" ] && sed -i "/^$id\t/d" "$outfile"
        fi
        local pkg="$(mvneval "$f" project.packaging)"
        if [ "$pkg" = "pom" ]; then
            echo " - packaging pom, skipping..."
            echo -e "${id}\t${pkg}\t${f}\tn/a\tn/a\tn/a\t${fingerprint}" \
                >> "$outfile"
            continue
        fi
        echo -n " - packaging $pkg"
        local base="$(mvneval "$f" project.basedir)"
        local src="$(mvneval "$f" project.build.sourceDirectory)"
        local resources="$(mvneval "$f" project.build.resources[0].directory)"
        echo " - $id"
        echo -e "${id}\t${pkg}\t${f}\t${base}\t${src}\t${resources}\t${fingerprint}" \
            >> "$outfile"
    done | grep --color=never . \
        || error "No modules (pom.xml files) found"
}

fingerprint() {
    id_and_fingerprint "$1" | cut -f 2
}

error() {
    echo "$1" >&2
    exit ${2-1}
}

is_empty() {
    local lines=$(line_count "$1")
    [ "$lines" -eq "0" ]
}

line_count() {
    local file="$1"
    if [ -f "$file" ]; then
        wc -l "$file" | cut -d ' ' -f 1
    else
        echo "0"
    fi
}

id_and_fingerprint() {
    local e="$TMPDIR/effective-pom.xml"
    effective_pom "$1" > "$e"
    local id="$(cat "$e" | artifact_id_from_pom)"
    local fp="$(cat "$e" | digest | cut -d ' ' -f 1)"
    echo -e "$id\t$fp"
}

digest() {
    md5sum 2>/dev/null || md5 -r
}

artifact_id() {
    effective_pom "$1" \
        | artifact_id_from_pom
}

effective_pom() {
    local f="$1"
    local o="$TMPDIR/effective-pom.xml"
    mvn -B -q -f "$f" org.apache.maven.plugins:maven-help-plugin:2.2:effective-pom -Doutput="$o"
    sed '/<!--/d' "$o"
}

artifact_id_from_pom() {
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
    echo -n "" > "$TMPDIR/packages-modules.tsv"

    # 1: id, 5: src
    for_modules | cut -f 1,5 \
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
                # keep only broadest packages
                for (k in map){ 
                    c=k;
                    while(c in map){
                        i=c;
                        gsub(/\/[^\/]*$/,"",c);
                        if (i == c) break;
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
        >> "$TMPDIR/packages-modules.tsv"
    
    # Packages:
    cut -f 1 "$TMPDIR/packages-modules.tsv" > "$TMPDIR/packages.txt"
}

usages() {
    echo "Finding usages"
    # One line per apparent actual package dependency:
    local outfile="$TMPDIR/deps-detailed.tsv"
    echo -n "" > "$outfile"

    for_modules | cut -f 1,4,5,6 \
    | while read id base src resource ;do
        find "$base" \( -path "$src/*" -or -path "$resource/*" \) -type f \
            -exec fgrep --color=never --binary-files=without-match -H -o -f "$TMPDIR/packages.txt" {} \; \
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
    
    cat "$TMPDIR/deps-detailed.tsv" \
        | cut -f 1,3 \
        | sort \
        | uniq -c \
        | sed 's/^ *//' \
        | tr ' ' \\t \
        > "$TMPDIR/deps-sum-detailed.tsv"
    
    cat "$TMPDIR/deps-sum-detailed.tsv" \
        | awk 'BEGIN{
                OFS="\t";
                while(( getline line<"'$TMPDIR/packages-modules.tsv'") > 0 ) {
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
        > "$TMPDIR/deps.tsv"
}

mvneval() {
    mvn -B -f "$1" org.apache.maven.plugins:maven-help-plugin:2.2:evaluate -Dexpression=$2 | grep --color=never -v '^\['
}

dependency_tree() {
    local includes="$1"
    echo "dependency tree"
    rm "$TMPDIR/mvn.dot" 2>/dev/null || true
    for_modules | cut -f 3,4 \
        | while read pom base ;do
            (cd "$base" && mvn -B -q dependency:tree -Dincludes="$includes" -DoutputType=dot -DoutputFile="$TMPDIR/mvn.dot" -DappendOutput=true)
        done
}

for_modules() {
    awk '$2 != "pom"' "$WD/modules.tab"
}

# reads mvn.dot and deps.tsv
# to create result dot graph
mvn_deps() {
    echo 'digraph {' > "$TMPDIR/mvn-deps.dot"
    cat "$TMPDIR/mvn.dot" \
        | grep --color=never '" -> "' \
        | sort \
        | uniq \
        >> "$TMPDIR/mvn-deps.dot"
    echo '}' >> "$TMPDIR/mvn-deps.dot"
    cat "$TMPDIR/mvn-deps.dot" \
        | grep --color=never '" -> "' \
        | sed 's/\s*//g;s/->/\t/;s/"//g' \
        | awk 'BEGIN{
                OFS="\t";
                while(( getline line<"'"$TMPDIR/deps.tsv"'") > 0 ) {
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

