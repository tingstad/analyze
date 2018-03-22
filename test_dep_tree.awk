#!/usr/bin/awk -f

function run_tests() {
    arr[1] = 1
    assert_equals("Array with one element should have length 1", 1, len(arr))
    arr[2] = 1
    assert_equals("Array with two elements should have length 2", 2, len(arr))
    split("a:b:c:d:e:f", arr, ":")
    assert_equals("Array with six elements should have length 6", 6, len(arr))
    assert_equals("Invalid file should give error", 1, main("non_existing"))
}

function array_of_len(n) {
}

function assert_equals(message, expected, actual) {
    if (expected == actual) {
        print "OK: " message
    } else {
        print "FAIL: " message " Expected '" expected "' but was '" actual "'"
        exit 1
    }
}
BEGIN {
    test_mode = 1
    run_tests()
}

