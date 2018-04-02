#!/usr/bin/awk -f

function main() {
    if (ARGC < 2 || ARGC > 3) {
        print "Usage: dependency_tree.awk FILE [PATTERN]"
        exit 1
    }
    file = ARGV[1]
    repo = get_repo()
    error = tree(file, "")
    if (error) {
        print "ERROR " error
        exit error
    }
}

function tree(file, pattern,  line, cmd, src, root, success, result, from, to) {
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
                    result = tree(repo "/" path, "")
                    #print result " result (" from ", " to ")"
                    if (result) print to " -> \"ERROR " result "\""
                }
            }
        }
    }
    error = close(cmd)
    if (error) {
        return error
    }
    return !success
}

function get_repo() {
    cmd = "mvn help:evaluate -Dexpression=settings.localRepository"
    repo = ""
    while ((cmd | getline line) > 0) {
        if (line !~ /^(.INFO|Download)/)
            repo = line
    }
    error = close(cmd)
    if (error) {
        print "ERROR evaluating maven repo; " error
        exit error
    }
    if (length(repo) == 0) {
        print "Could not evaluate maven repo"
        exit 1
    }
    return repo
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
    if (test_mode) exit
    main()
}

