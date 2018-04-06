#!/usr/bin/awk -f

function run_tests() {
    arr[1] = 1
    assert_equals("Array with one element should have length 1", 1, len(arr))
    arr[2] = 1
    assert_equals("Array with two elements should have length 2", 2, len(arr))
    split("a:b:c:d:e:f", arr, ":")
    assert_equals("Array with six elements should have length 6", 6, len(arr))
    assert_equals("Invalid file should give error", 1, tree("non_existing"))
    assert_match("Should evaluate mvn repo", "^/.*[^/]$", get_repo())

    assert_equals("Normal coordinate", "grp:art:jar:1", coordinate("grp:art:jar:1:compile"))
    assert_equals("Test-jar coordinate", "grp:art:test-jar:1", coordinate("grp:art:test-jar:tests:1:test"))

    arr_mvn_out[1] = "[INFO] digraph \"grp:art:jar:1\" {"
    arr_mvn_out[2] = "[INFO]  \"grp:art:jar:1\" -> \"grp:dep:jar:1:compile\" ;"
    arr_mvn_out[3] = "[INFO] BUILD SUCCESS"
    retval = tree("foo/pom.xml", "", arr_tree, arr_mvn_out)
    assert_equals("Should not give error", 0, retval)
    assert_equals("Tree should have size 2", 2, len(arr_tree))
    assert_equals("Tree should contain dependency", "grp:dep:jar:1", arr_tree["grp:art:jar:1"])
    assert_equals("Tree should contain error", "ERROR 1 grp:dep:jar:1", arr_tree["grp:dep:jar:1"])
    assert_equals("Output should contain dependencies", \
            "\"grp:art:jar:1\" -> \"grp:dep:jar:1\"\n" \
            "\"grp:dep:jar:1\" -> \"ERROR 1 grp:dep:jar:1\"" \
            , str_out)
    for (k in arr_tree) delete arr_tree[k]

    arr_mvn_out[1] = "[INFO] digraph \"grp:art:jar:1\" {"
    arr_mvn_out[2] = "[INFO]  \"grp:art:jar:1\" -> \"grp:dep:jar:1:compile\" ;"
    arr_mvn_out[3] = "[INFO]  \"grp:art:jar:1\" -> \"grp:dep2:jar:1:compile\" ;"
    arr_mvn_out[4] = "[INFO] BUILD SUCCESS"
    retval = tree("foo/pom.xml", "", arr_tree, arr_mvn_out)
    assert_equals("Should not give error", 0, retval)
    assert_equals("Tree should have size 3", 3, len(arr_tree))
    assert_equals("Tree should contain error", "ERROR 1 grp:dep:jar:1", arr_tree["grp:dep:jar:1"])
    assert_equals("Tree should contain error", "ERROR 1 grp:dep2:jar:1", arr_tree["grp:dep2:jar:1"])
    assert_equals("Tree should contain dependency", "grp:dep:jar:1/grp:dep2:jar:1", arr_tree["grp:art:jar:1"])
}

function assert_equals(message, expected, actual) {
    if (expected == actual)
        ok(message)
    else
        fail(message, expected, actual)
}

function assert_match(message, expected, actual) {
    if (actual ~ expected)
        ok(message)
    else
        fail(message, expected, actual)
}

function ok(message) {
    succeeded++
    print "OK: " message
}

function fail(message, expected, actual) {
    print "FAIL: " message " Expected '" expected "' but was '" actual "'"
    exit 1
}

BEGIN {
    test_mode = 1
    print "Running tests"
    run_tests()
    print "Ran " succeeded " tests successfully!"
}

