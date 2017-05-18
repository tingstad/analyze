#!/bin/bash
#set -x

testPackageDetection() {
    local src1="$(mktemp -d)"
    mkdir -p "$src1/com/foo/package1" 
    mkdir -p "$src1/com/foo/package2" 
    mkdir -p "$src1/com/foo/package2/bar" 
    mkdir -p "$src1/com/foo/package3/detail" 
    local src2="$(mktemp -d)"
    mkdir -p "$src2/com/foo/package1" 
    mkdir -p "$src2/com/foo/package4" 
    WD="$src1"
    TARGET_DIR="$src1"
    echo -e "id1\tjar\tpom.xml\t$src1\t$src1\t$src1" > "$src1/modules.tab"
    echo -e "id2\tjar\tpom.xml\t$src2\t$src2\t$src2" >>"$src1/modules.tab"

    packages

    assertTrue '' "[ -f "$src1/packages-modules.tsv" ]"
    read -r -d '' expected <<- TIL
		com.foo.package2	id1
		com.foo.package3	id1
		com.foo.package4	id2
	TIL
    assertEquals '' "$expected" "$(cat "$src1/packages-modules.tsv")"
    read -r -d '' expected <<- TIL
		com.foo.package2
		com.foo.package3
		com.foo.package4
	TIL
    assertEquals '' "$expected" "$(cat "$src1/packages.txt")"
}

testUsages() {
    local src1="$(mktemp -d)"
    mkdir -p "$src1/src/com/foo/package2" 
    local src2="$(mktemp -d)"
    mkdir -p "$src2/src/com/foo/package4" 
    WD="$src1"
    TARGET_DIR="$src1"
    echo -e "package com.foo.package2;import com.foo.package4.Two;class One{} " > "$src1/src/com/foo/package2/One.java"
    echo -e "package com.foo.package4;import com.foo.package2.One;class Two{} " > "$src2/src/com/foo/package4/Two.java"
    echo -e "id1\tjar\tpom.xml\t$src1\t$src1/src\t$src1/src" > "$src1/modules.tab"
    echo -e "id2\tjar\tpom.xml\t$src2\t$src2/src\t$src2/src" >>"$src1/modules.tab"
    cat <<- TIL > "$WD/packages-modules.tsv"
		com.foo.package2	id1
		com.foo.package3	id1
		com.foo.package4	id2
	TIL
    cut -f1 "$WD/packages-modules.tsv" > "$WD/packages.txt"

    usages

    read -r -d '' expected <<- TIL
		com/foo/package2/One.java	com.foo.package2
		com/foo/package2/One.java	com.foo.package4
		com/foo/package4/Two.java	com.foo.package2
		com/foo/package4/Two.java	com.foo.package4
	TIL
    assertEquals '' "$(echo -e "$expected" | sort)" "$(cat "$WD/deps-detailed.tsv" | sort)"
}

DIR="$( dirname "$(pwd)/$0" )"
TESTMODE="on"
source "$DIR/analyze.sh"
set +o errexit
source "$DIR/shunit2.sh"

