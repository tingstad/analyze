#!/bin/bash
set -o errexit

repo="$(mvn help:evaluate -Dexpression=settings.localRepository | egrep -v '^(\[INFO\]|Download)')"

main() {
    if [ $# -ne 2 -o ! -f "$1" -o -z "$2" ]; then
        echo "$#,$0,$1,$2,$3"
        print_usage_and_exit
    fi
    tree "$1" "$2"
}

tree() {
    [ $# -eq 2 ] && [ -f "$1" ] && [ -n "$2" ] || error "Illegal argument"
    local file="$1"
    local pattern="$2"
    awk -F '"' -v repo="$repo" -v pattern="$pattern" -v file="$file" '
        function main(file, pattern,  line, cmd, src, root, success, result, from, to) {
            #print "main " file
            cmd = mvn_dep_tree(file)
            root = ""
            success = 0
            while ((cmd | getline line) > 0 ) {
                if (line ~ "^.INFO. BUILD SUCCESS") {
                    success = 1
                }
                if (line ~ "^.INFO.* -> ") {
                    split(line, a, "\"")
                    src = a[2]
                    dest = a[4]
                    if (!root) {
                        root = src
                    }
                    if (src == root) {
                        split(dest, a, ":")
                        gsub("\\.", "/", a[1])
                        if (len(a) == 5)
                            path = a[1] "/" a[2] "/" a[4] "/" a[2] "-" a[4] ".pom"
                        else
                            path = a[1] "/" a[2] "/" a[5] "/" a[2] "-" a[5] ".pom"
                        from = coordinate(src)
                        to = coordinate(dest)
                        print from " -> " to
                        seen[from]++
                        if (!seen[to]) {
                            result = main(repo "/" path, "")
                            #print result " result (" from ", " to ")"
                            if (result) print to " -> \"ERROR " result "\""
                        }
                    }
                }
            }
            error = close(cmd)
            if (error) {
                #print "ERROR " error " " ERRNO
                #exit error
                return error
            }
            #if (!success) print "no succes: " cmd
            return !success
        }
        function mvn_dep_tree(file) {
            return "mvn --batch-mode --non-recursive --fail-fast --file \"" file "\" dependency:tree -DoutputType=dot"
        }
        function coordinate(node_string) {
            split(node_string, a, ":")
            groupId = a[1]
            artifactId = a[2]
            version = (len(a) <= 5 ? a[4] : a[5])
            return groupId ":" artifactId ":" version
        }
        function len(arr) {
            count = 0
            for (k in arr) ++count
            return count
        }
        BEGIN {
            main(file, "")
        }'
}

pom() {
    [ $# -eq 1 ] && [ -f "$1" ] || error "Illegal argument"
    mvn --batch-mode --non-recursive --fail-fast --file "$1" dependency:tree -DoutputType=dot
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
		Emulates previously existing mvn dependency:tree -Dverbose
		
		Usage: $0 POM_FILE PATTERN
		
		  POM_FILE  The root project to analyze. Should be built so the local maven
		            repo can be used.
		  PATTERN   Regexp for the "includes" dependency. (".*" for all.)
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
                s = substr(tag, index(tag, ">")+1)
                return substr(s, 1, index(s, "<")-1)
            }
            !a && /<artifactId>/ { a = content($0) }
            !g && /<groupId>/ { g = content($0) }
            !v && /<version>/ { v = content($0) }
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
        | awk 'BEGIN { OFS = "\t"; }
            { map[$2] = ($1 "/" map[$2]); }
            # map[pkg] = id1/id2/
            END {
                # delete packages not unique to a single module
                for (k in map) {
                    v = map[k]; gsub(/[^\/]/, "", v)
                    if (length(v) > 1)
                        delete map[k]
                }
                # keep only broadest packages
                for (k in map) {
                    c = k
                    while (c in map) {
                        i = c
                        gsub(/\/[^\/]*$/, "", c)
                        if (i == c) break
                    }
                    map2[i] = map[k]
                }
                # print results
                for (k in map2) {
                    v = map2[k]
                    gsub(/[\/]/, "", v)
                    gsub(/[\/]/, ".", k)
                    print k, v
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
            | clean_up_fgrep \
            | awk -F: 'BEGIN { OFS = "\t" } {
                        d[1] = "'"$src"'"; d[2] = "'"$resource"'"
                        for (s in d) {
                            if (index($1, d[s]) == 1) {
                                $1 = substr($1, length(d[s]) + 2)
                                break
                            }
                        } print "'"$id"'", $1, $2; }' \
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
        | awk 'BEGIN {
                OFS = "\t"
                while ( (getline line<"'${packages_modules_file}'") > 0 ) {
                    split(line, a)
                    modul[a[1]] = a[2]
                }
            }
            {
                from = $2; to = modul[$3]
                if (from != to) {
                    dep[from "/" to] += $1
                }
            }
            END {
                for (k in dep) {
                    split(k, a, "/")
                    print a[1], a[2], dep[k]
                }
            }' \
        | sort \
        > "$outfile"
}

clean_up_fgrep() {
    awk -F: '{
        OFS = FS
        if (NF == 2) {
            f = $1
            print
        }
        else
            print f, $0
    }'
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
            (cd "$base" && mvn -B -q org.apache.maven.plugins:maven-dependency-plugin:2.10:tree -Dincludes="$includes" -Dscope=runtime -DoutputType=dot -DoutputFile="$outfile" -DappendOutput=true)
        done
}

undeclared_use() {
    [ $# -eq 2 ] && [ -f "$1" ] && [ -n "$2" ] || error "Illegal argument"
    local modules="$1"
    local targetfile="$2"
    echo "undeclared use"
    cut -f 1,3,4 "$modules" \
        | while IFS=$'\t' read id pom base ;do
            (cd "$base" \
                && mvn -B org.apache.maven.plugins:maven-dependency-plugin:2.10:analyze \
                    -DignoreNonCompile=true \
                    -DscriptableOutput=true \
                | parse_mvn_analyze "$id" \
                >> "$targetfile"
            )
        done
}

parse_mvn_analyze() {
    [ $# -eq 1 ] && [ -n "$1" ] || error "Illegal argument"
    local id="$1"
    grep '^$$%%%' \
    | awk -F : '
        {
            OFS = "\t"
            groupId = $3
            artifactId = $4
            version = $7
            from = "'"$id"'"
            to = groupId ":" artifactId ":" version
            print from, to, 0
        }'
}

concat_deps() {
    [ $# -eq 2 ] && [ -f "$1" ] && [ -f "$2" ] || error "Illegal argument"
    local deps="$1"
    local undeclared="$2"
    echo "concat dependencies"
    if is_empty "$deps"; then
        cat "$undeclared" > "$deps"
    elif ! is_empty "$undeclared"; then
        fgrep -v -f <(cut -f 1-2 "$deps") "$undeclared" >> "$deps"
    fi
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
        | tr -d ' \t"' \
        | sed 's/->/'$'\t''/' \
        | awk 'BEGIN {
                OFS = "\t"
                while ( (getline line<"'"$deps"'") > 0 ) {
                    split(line, a)
                    dep[a[1] FS a[2]] = a[3]
                }
            }
            {
                split($1, a, ":")
                from = a[1] ":" a[2] ":" a[4]
                split($2, a, ":")
                to = a[1] ":" a[2] ":" a[4]
                k = (from FS to)
                if (!mvn[k]) {
                    mvn[k] = 1
                    deps = dep[from FS to]
                    width = (deps ? (deps / 10) : 0)
                    print "\"" from "\" -> \"" to "\"" (width ? " [penwidth=" width "]" : "") ";"
                }
            }
            END {
                for (k in dep) {
                    if (!(k in mvn)) {
                        split(k, a)
                        width = (dep[k] / 10)
                        print "\"" a[1] "\" -> \"" a[2] "\" [" (width ? "penwidth=" width "," : "") "color=red];"
                    }
                    if ((a[2] FS a[1]) in dep)
                        print k,"REVERSE!!!!!"
                }
                print "}"
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
        cat "$file" | awk -v median=$median -v min=$min -v max=$max '
            BEGIN {
                if (min == 0) min = 1
                if (max == 0) max = 1
                ratio = max / min
                if (ratio > 3)
                    ratio = 3
            }
            {
                size = ($2 > 0 ? $2 : 1)
                size = sqrt(size / max)
                hei = (size * ratio)
                wid = (size * ratio * 1.5)
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

