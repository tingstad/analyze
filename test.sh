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
    echo -e "id1\tjar\tpom.xml\t$src1\t$src1\t$src1" > "$WD/modules.tab"
    echo -e "id2\tjar\tpom.xml\t$src2\t$src2\t$src2" >>"$WD/modules.tab"

    packages

    assertTrue '' "[ -f "$WD/packages-modules.tsv" ]"
    read -r -d '' expected <<- TIL
		com.foo.package2	id1
		com.foo.package3	id1
		com.foo.package4	id2
	TIL
    assertEquals '' "$expected" "$(cat "$WD/packages-modules.tsv")"
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
    echo -e "package com.foo.package2;\nimport com.foo.package4.Two;public class One{} " \
        > "$src1/src/com/foo/package2/One.java"
    echo -e "package com.foo.package4;\nimport com.foo.package2.One;public class Two{} " \
        > "$src2/src/com/foo/package4/Two.java"
    echo -e "id1\tjar\tpom.xml\t$src1\t$src1/src\t$src1/src" > "$WD/modules.tab"
    echo -e "id2\tjar\tpom.xml\t$src2\t$src2/src\t$src2/src" >>"$WD/modules.tab"
    cat <<- TIL > "$WD/packages-modules.tsv"
		com.foo.package2	id1
		com.foo.package4	id2
	TIL
    cut -f1 "$WD/packages-modules.tsv" > "$WD/packages.txt"

    usages

    read -r -d '' expected <<- TIL
		id1	com/foo/package2/One.java	com.foo.package2
		id1	com/foo/package2/One.java	com.foo.package4
		id2	com/foo/package4/Two.java	com.foo.package2
		id2	com/foo/package4/Two.java	com.foo.package4
	TIL
    assertEquals '' "$(echo -e "$expected" | sort)" "$(cat "$WD/deps-detailed.tsv" | sort)"
    assertEquals '' "$(echo -e "id1\tid2\t1\nid2\tid1\t1" | sort)" "$(cat "$WD/deps.tsv" | sort)"
}

testNoParameters() {
    local out="$(main 2>&1)"

    assertEquals 'Should print usage' "Usage:" "$(echo "$out" | cut -d' ' -f1)"
}

testMvnDependencyTreeOneModule() {
    local dir="$(mktemp -d)"
    mkdir -p "$dir/module1"
    WD="$dir"
    TARGET_DIR="$dir"
    cat <<- EOF > "$TARGET_DIR/module1/pom.xml"
		<project>
			<modelVersion>4.0.0</modelVersion>
			<groupId>g</groupId>
			<artifactId>a</artifactId>
			<version>1</version>
		</project>
	EOF

    dependency-tree

    read -r -d '' expected <<- TIL
		digraph "g:a:jar:1" { 
		 }
	TIL
    assertEquals "$expected " "$(cat "$WD/mvn.dot")"
}

testMvnDependencyTreeTwoModules() {
    local dir="$(mktemp -d)"
    mkdir -p "$dir/module1"
    mkdir -p "$dir/module2"
    WD="$dir"
    TARGET_DIR="$dir"
    cat <<- EOF > "$TARGET_DIR/module1/pom.xml"
		<project>
			<modelVersion>4.0.0</modelVersion>
			<groupId>g</groupId>
			<artifactId>a</artifactId>
			<version>1</version>
		</project>
	EOF
    cat <<- EOF > "$TARGET_DIR/module2/pom.xml"
		<project>
			<modelVersion>4.0.0</modelVersion>
			<groupId>g</groupId>
			<artifactId>b</artifactId>
			<version>1</version>
			<dependencies><dependency>
				<groupId>g</groupId>
				<artifactId>a</artifactId>
				<version>1</version>
				<type>pom</type>
			</dependency></dependencies>
		</project>
    
	EOF

    dependency-tree

    read -r -d '' expected <<- TIL
		digraph "g:a:jar:1" { 
		} digraph "g:b:jar:1" { 
		       "g:b:jar:1" -> "g:a:jar:1" ;
		 }
	TIL
    assertEquals "$expected " "$(cat "$WD/mvn.dot")"
}

testUsages2() {
    local src1="$(mktemp -d)"
    mkdir -p "$src1/src/com/foo/package2" 
    local src2="$(mktemp -d)"
    mkdir -p "$src2/src/com/foo/package4" 
    WD="$src1"
    TARGET_DIR="$src1"
    echo -e "package com.foo.package2;\nimport com.foo.package4.Two;public class One{} " \
        > "$src1/src/com/foo/package2/One.java"
    echo -e "package com.foo.package4;\npublic class Two{} " \
        > "$src2/src/com/foo/package4/Two.java"
    echo -e "id1\tjar\tpom.xml\t$src1\t$src1/src\t$src1/src" > "$WD/modules.tab"
    echo -e "id2\tjar\tpom.xml\t$src2\t$src2/src\t$src2/src" >>"$WD/modules.tab"
    cat <<- TIL > "$WD/packages-modules.tsv"
		com.foo.package2	id1
		com.foo.package4	id2
	TIL
    cut -f1 "$WD/packages-modules.tsv" > "$WD/packages.txt"

    usages

    read -r -d '' expected <<- TIL
		id1	com/foo/package2/One.java	com.foo.package2
		id1	com/foo/package2/One.java	com.foo.package4
		id2	com/foo/package4/Two.java	com.foo.package4
	TIL
    assertEquals '' "$(echo -e "$expected" | sort)" "$(cat "$WD/deps-detailed.tsv" | sort)"
    assertEquals '' "$(echo -e "id1\tid2\t1" | sort)" "$(cat "$WD/deps.tsv" | sort)"
}

DIR="$( dirname "$(pwd)/$0" )"
TESTMODE="on"
source "$DIR/analyze.sh"
set +o errexit
source "$DIR/shunit2.sh"

