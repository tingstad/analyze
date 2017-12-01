#!/bin/bash
set -o errexit

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
    local work_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local target_dir="$(cd "$1" && pwd)" # Dir to analyze
    if [ -n "$quiet" ]; then
        exec 3>/dev/null
    else
        exec 3>&1
    fi

    echo "Using temp dir $TMPDIR" >&3
    local modules="$TMPDIR/modules.tab" 
    find_modules "$target_dir" "$work_dir" "$modules" >&3
    packages "$modules" "$TMPDIR/packages-modules.tsv" >&3
    usages "$modules" "$TMPDIR/packages-modules.tsv" "$TMPDIR/deps.tsv" >&3
    dependency_tree "$modules" "${includes:-*}" "$TMPDIR/mvn.dot" >&3
    # mvn org.apache.maven.plugins:maven-dependency-plugin:2.10:analyze |awk "/Used undeclared/{s++} /Unused declared/{s--} s{print}"
    cut -f 1,5 "$modules" | sizes > "$TMPDIR/size.tab" #1,5=id,src
    echo "mvn deps" >&3
    if [ -n "$outputfile" ]; then
        mvn_deps "$TMPDIR/deps.tsv" "$TMPDIR/mvn.dot" "$TMPDIR/size.tab" > "$outputfile"
    else
        mvn_deps "$TMPDIR/deps.tsv" "$TMPDIR/mvn.dot" "$TMPDIR/size.tab"
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
    [ $# -eq 3 ] && [ -d "$1" ] && [ -d "$2" ] && [ -n "$3" ] || error "Illegal argument"
    local target_dir="$1"
    local cachefile="$2/cache_modules.tab"
    local outfile="$3"
    find "$target_dir" -name pom.xml -type f -print \
    | sort -r \
    | while read f ;do
        echo -n "Found module $f"
        local id_and_fp="$(id_and_fingerprint "$f")"
        local id="$(echo "$id_and_fp" | cut -f 1)"
        if [ "$id" = "::" ]; then
            echo "Skipping invalid $f" >&2
            continue
        fi
        local fingerprint="$(echo "$id_and_fp" | cut -f 2)"
        local existing=$(awk "\$1 == \"$id\" { print \$7 }" "$cachefile" 2>/dev/null || echo "na")
        if [ $fingerprint = "$existing" ]; then
            echo " - $id"
            awk "\$1 == \"${id}\" && \$2 != \"pom\"" "$cachefile" >> "$outfile"
            continue
        else
            [ -f "$cachefile" ] && ( grep -v "^$id"$'\t' "$cachefile" \
                > "$cachefile.2" ; mv "$cachefile.2" "$cachefile" )
        fi
        local pkg="$(mvneval "$f" project.packaging)"
        if [ "$pkg" = "pom" ]; then
            echo " - packaging pom, skipping..."
            echo -e "${id}\t${pkg}\t${f}\tn/a\tn/a\tn/a\t${fingerprint}" \
                >> "$cachefile"
            continue
        fi
        echo -n " - packaging $pkg"
        local base="$(mvneval "$f" project.basedir)"
        local src="$(mvneval "$f" project.build.sourceDirectory)"
        local resources="$(mvneval "$f" project.build.resources[0].directory)"
        echo " - $id"
        echo -e "${id}\t${pkg}\t${f}\t${base}\t${src}\t${resources}\t${fingerprint}" \
            >> "$cachefile"
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
        wc -l "$file" | awk '{ print $1 }'
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
    [ -n "$f" ] || error 'Invalid argument'
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
    [ -f "$1" ] && [ -n "$2" ] || error "Illegal argument"
    local modules="$1"
    local outfile="$2"
    # Find unique packages for a module (others will be ignored)
    echo -n "" > "$TMPDIR/packages-modules.tsv"

    # 1: id, 5: src
    cut -f 1,5 "$modules" \
    | while IFS=$'\t' read id src ;do
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
        >> "$outfile"
}

usages() {
    echo "Finding usages"
    [ $# -eq 3 ] && [ -f "$1" ] && [ -f "$2" ] && [ -n "$3" ] || error "Illegal argument"
    local modules="$1"
    local packages_modules_file="$2"
    local outfile="$3"
    # One line per apparent actual package dependency:
    local detailed="$TMPDIR/deps-detailed.tsv"
    echo -n "" > "$detailed"

    cut -f 1 "${packages_modules_file}" > "$TMPDIR/packages.txt"
    cut -f 1,4,5,6 "$modules" \
    | while IFS=$'\t' read id base src resource ;do
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
            >> "$detailed"
    done 
    # detailed for debug
    
    cat "$detailed" \
        | cut -f 1,3 \
        | sort \
        | uniq -c \
        | sed 's/^ *//' \
        | tr ' ' \\t \
        > "$TMPDIR/deps-sum-detailed.tsv"
    
    cat "$TMPDIR/deps-sum-detailed.tsv" \
        | awk 'BEGIN{
                OFS="\t";
                while(( getline line<"'${packages_modules_file}'") > 0 ) {
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
        > "$outfile"
}

mvneval() {
    mvn -B -f "$1" org.apache.maven.plugins:maven-help-plugin:2.2:evaluate -Dexpression=$2 | grep --color=never -v '^\['
}

dependency_tree() {
    [ $# -eq 3 ] && [ -f "$1" ] && [ -n "$2" ] && [ -n "$3" ] || error "Illegal argument"
    local modules="$1"
    local includes="$2"
    local outfile="$3"
    echo "dependency tree"
    rm "$outfile" 2>/dev/null || true
    cut -f 3,4 "$modules" \
        | while IFS=$'\t' read pom base ;do
            (cd "$base" && mvn -B -q org.apache.maven.plugins:maven-dependency-plugin:2.10:tree -Dincludes="$includes" -DoutputType=dot -DoutputFile="$outfile" -DappendOutput=true)
        done
}

sizes() {
    while IFS=$'\t' read id src ;do
        echo -e "$id\t"$(module_size "$src")
    done
}

module_size() {
    local d="$1"
    [ -n "$d" ] || error 'Invalid argument'
    if [ ! -d "$d" ]; then
        echo "0"
        return 0
    fi
    find "$d" -name \*.java -type f \
        -exec wc -l {} \; \
        | awk -F ' ' 'BEGIN{ s=0 } { s+=$1 } END{ print s }'
}

# reads mvn.dot and deps.tsv
# to create result dot graph
mvn_deps() {
    [ $# -eq 3 ] && [ -f "$1" ] && [ -f "$2" ] && [ -f "$3" ] || error "Illegal argument"
    local deps="$1"
    local mvn_dot="$2"
    local sizes="$3"
    echo 'digraph {' > "$TMPDIR/mvn-deps.dot"
    cat "${mvn_dot}" \
        | grep --color=never '" -> "' \
        | sort \
        | uniq \
        >> "$TMPDIR/mvn-deps.dot"
    echo '}' >> "$TMPDIR/mvn-deps.dot"
    echo 'digraph {'
    print_node_sizes "$sizes"
    cat "$TMPDIR/mvn-deps.dot" \
        | grep --color=never '" -> "' \
        | sed 's/\s*//g;s/->/'$'\t''/;s/"//g' \
        | awk 'BEGIN{
                OFS="\t";
                while(( getline line<"'"$deps"'") > 0 ) {
                    split(line,a);
                    dep[a[1] FS a[2]]=a[3];
                }
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
                        width=(dep[k] / 10);
                        print "\"" a[1] "\" -> \"" a[2] "\" [" (width ? "penwidth=" width "," : "") "color=red];";
                    } 
                    if((a[2] FS a[1]) in dep)
                        print k,"REVERSE!!!!!";
                }
                print "}";
            }' 
}

print_node_sizes() {
    [ $# -eq 1 ] && [ -f "$1" ] || error "Illegal argument"
    local file="$1"
    local lines=$(line_count "$file")
    if [ $lines -gt 0 ]; then
        local median=$(cut -f 2 "$file" | median $lines)
        local min=$(cut -f 2 "$file" | sort -n | head -n 1)
        local max=$(cut -f 2 "$file" | sort -n | tail -n 1)
        cat "$file" | awk -v median=$median -v min=$min -v max=$max 'BEGIN{
                if (min == 0) min=1
                if (max == 0) max=1
                ratio=max/min
                if (ratio > 3)
                    ratio=3
            }
            {
                size=($2 > 0 ? $2 : 1)
                size=sqrt(size / max)
                hei=(size * ratio)
                wid=(size * ratio * 1.5)
                print "\"" $1 "\" [fixedsize=true,width=" wid ",height=" hei "];"
            }'
    fi
}

median() {
    local lines="$1"
    local line=$(middle_line $lines)
    sort -n | awk "NR == $line { print }"
}

middle_line() {
    [ $# -eq 1 ] && [ -n "$1" ] && [ $1 -ge 0 ] || error "Illegal argument"
    local lines="$1"
    if [ $lines -lt 2 ]; then
        echo $lines
    else
        echo $(( $((lines + 1)) / 2 ))
    fi
}

[ -n "$TESTMODE" ] && return

main $@

