#!/usr/bin/awk -f

function main() {
    if (ARGC < 2 || ARGC > 2) {
        prnt("Usage: dependency_tree.awk FILE")
        return 1
    }
    file = ARGV[1]
    repo = get_repo()
    error = tree_top(file, repo)
    if (error) {
        prnt("ERROR " error)
        return error
    }
    #for (k in arr_tree) {
    #    print k " -> " arr_tree[k]
    #}
    return 0
}

function tree_top(file, repo) {
    prnt("digraph {")
    retval_treetop = tree(file, "",  arr_tree, arr_mvn_out)
    if (retval_treetop) return retval_treetop
    prnt("}")
    return 0
}

function tree(file, scope, arr_tree, arr_mvn_out, n, k, line, src, root, success, result, from, to) {
    root = ""
    success = 0
    get_dep_tree(file, arr_mvn_out)
    n = len(arr_mvn_out)
    for (k = 1; k <= n; ++k) {
        line = arr_mvn_out[k]
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
                from = coordinate(src) (scope ? ":" scope : "")
                to = coordinate(dest)
                is_root = (scope == "")
                dest_scope = get_scope(to)
                trans_scope = transitive_scope(scope, dest_scope)
                to = set_scope(to, trans_scope)
                if (!is_root && !trans_scope) continue #no deeper
                add_child(arr_tree, from, to)
                print_dep(from, to)
                seen[without_pkg(from)]++
                if (!seen[without_pkg(to)]) {
                    result = tree(repo "/" path(dest), trans_scope, arr_tree)
                    if (result) {
                        err_node = "ERROR " result " " to
                        add_child(arr_tree, to, err_node)
                        print_dep(to, err_node)
                    }
                }
            }
        }
    }
    return !success
}

function transitive_scope(from, to) {
    if (len(table) == 0) {
        table["compile,compile"] = "compile"
        table["compile,runtime"] = "runtime"
        table["provided,compile"] = "provided"
        table["provided,runtime"] = "provided"
        table["runtime,compile"] = "runtime"
        table["runtime,runtime"] = "runtime"
        table["test,compile"] = "test"
        table["test,runtime"] = "test"
    }
    return table[from "," to]
}

function add_child(arr_tree, key, child) {
    prefix = (arr_tree[key] ? (arr_tree[key] "/") : "")
    arr_tree[key] = prefix child
}

function print_dep(from, to) {
    prnt(format(from, to))
}

function prnt(str) {
    if (test_mode) str_out = (str_out ? str_out "\n" : "") str
    else print str
}

function format(from, to) {
    return "\"" from "\" -> \"" to "\";"
}

function get_dep_tree(file, dest_arr) {
    if (test_mode) return 0
    cmd = mvn_dep_tree(file)
    c = 0
    while ((cmd | getline line) > 0) {
        dest_arr[++c] = line
    }
    retval = close(cmd) #Syntax error in old awks(?)
    return retval
}

function mvn_dep_tree(file) {
    return "mvn --batch-mode --non-recursive --fail-fast --file \"" file "\" dependency:tree -DoutputType=dot"
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

function coordinate(node_string) {
    split(node_string, a, ":")
    n = len(a)
    # groupId:artifactId:(packaging/classifier):[type:]version[:scope]
    groupId = a[1]
    artifactId = a[2]
    packaging = a[3]
    if (n == 4) {
        type = "jar"
        version = a[4]
        scope = "compile"
        return groupId ":" artifactId ":" packaging ":" version
    } else if (n == 6) {
        type = a[4]
        version = a[5]
        scope = a[6]
    } else if (a[n] ~ /compile|provided|runtime|test|system/) {
        type = "jar"
        version = a[4]
        scope = a[5]
    } else {
        type = a[4]
        version = a[5]
        scope = "compile"
    }
    return groupId ":" artifactId ":" packaging ":" version ":" scope
}

function path(node_string) {
    split(node_string, a, ":")
    gsub("\\.", "/", a[1])
    group_path = a[1]
    artifactId = a[2]
    version = (len(a) <= 5 ? a[4] : a[5])
    return group_path "/" artifactId "/" version "/" artifactId "-" version ".pom"
}

function without_pkg(str_coord) {
    split(str_coord, a, ":")
    groupId = a[1]
    artifactId = a[2]
    version = a[4]
    return groupId ":" artifactId ":" version
}

function get_scope(str_coord) {
    split(str_coord, a, ":")
    if (len(a) < 5) {
        print "ERROR: too short coordinate: " str_coord
        exit 1
    }
    return a[5]
}

function set_scope(str_coord, scope) {
    if (!scope) return str_coord
    split(str_coord, a, ":")
    if (len(a) < 5) {
        print "ERROR: too short coordinate: " str_coord
        exit 1
    }
    return a[1] ":" a[2] ":" a[3] ":" a[4] ":" scope
}

function len(arr) {
    count = 0
    for (k in arr) ++count
    return count
}

BEGIN {
    if (test_mode) exit
    retval = main()
    exit retval
}

