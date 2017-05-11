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
    #echo -e "id2\tjar\tpom.xml\t$src2\t$src2\t$src2" >>"$src1/modules.tab"

    packages

    assertTrue '' "[ -f "$src1/packages-modules.tsv" ]"
}

DIR="$( dirname "$(pwd)/$0" )"
TESTMODE="on"
source "$DIR/analyze.sh"
set +o errexit
source "$DIR/shunit2.sh"

