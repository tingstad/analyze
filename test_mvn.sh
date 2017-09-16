#!/bin/bash

testMvnDependencyTreeOneSimpleModule() {
    local dir="$(mktemp -d)"
    mkdir -p "$dir"
    WD="$dir"
    TMPDIR="$dir"
    echo -e "id1\tjar\tpom.xml\t${dir}\t${dir}/src\t{$dir}/src" \
        > "$WD/modules.tab"
    cat <<- EOF > "$TMPDIR/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF

    dependency_tree

    read -r -d '' expected <<- TIL
		digraph "g:a:jar:1" { 
		 }
	TIL
    assertEquals "$expected " "$(cat "$TMPDIR/mvn.dot")"
}

testMvnDependencyTreeTwoModules() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    local base2="$dir/module2"
    mkdir -p "$base1/src/main/java"
    mkdir -p "$base2/src/main/java"
    WD="$dir"
    TMPDIR="$dir"
    echo -e "id1\tjar\tpom.xml\t${base1}\t${base1}/src\t${base1}/src\n" \
            "id2\tjar\tpom.xml\t${base2}\t${base2}/src\t${base2}/src" \
        > "$WD/modules.tab"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF
    cat <<- EOF > "$base2/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>b</artifactId>
		    <version>1</version>
		    <dependencies><dependency>
		        <groupId>g</groupId>
		        <artifactId>a</artifactId>
		        <version>1</version>
		    </dependency></dependencies>
		</project>
	EOF
    echo -e "public class One {}" \
        > "$base1/src/main/java/One.java"
    (cd "$base1" && mvn -B -q install -Dmaven.test.skip=true)

    dependency_tree

    expected=$(echo 'digraph "g:a:jar:1" { '\
        | sed '$a\ } digraph "g:b:jar:1" { '\
        | sed '$a\\t"g:b:jar:1" -> "g:a:jar:1:compile" ; '\
        | sed '$a\ } ')
    assertEquals "${expected}" "$(cat "$TMPDIR/mvn.dot")"
}

testFindOneModule() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
    WD="$dir"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF

    find_modules "$dir" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "${expected}" "$(cat "$WD/modules.tab")"
}

testFindTwoModules() {
    local dir="$(mktemp -d)"
    local base1="$dir/module 1"
    local base2="$dir/module2"
    mkdir -p "$base1/src/main/java"
    mkdir -p "$base2/src/main/java"
    WD="$dir"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>with-space-in-path</artifactId>
		    <version>1</version>
		</project>
	EOF
    cat <<- EOF > "$base2/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>b</artifactId>
		    <version>1</version>
		</project>
	EOF

    find_modules "$dir" >/dev/null

    read -r -d '' expected <<- EOF
		g:b:1	jar	$base2/pom.xml	$base2	$base2/src/main/java	$base2/src/main/resources	$(fingerprint "$base2/pom.xml")
		g:with-space-in-path:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "${expected}" "$(cat "$WD/modules.tab")"
}

testFindNewModule() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
    WD="$dir"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF
    echo -e "id2\tjar\tpom.xml\tBASE\tSRC\tRESRC\tHASH" > "$WD/modules.tab"

    find_modules "$dir" >/dev/null

    read -r -d '' expected <<- EOF
		id2	jar	pom.xml	BASE	SRC	RESRC	HASH
		g:a:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "${expected}" "$(cat "$WD/modules.tab")"
}

testFindUnchangedModule() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
    WD="$dir"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF
    echo -e "g:a:1\tjar\t$base1/pom.xml\t$base1\t$base1/src/main/java\t$base1/src/main/resources\t$(fingerprint "$base1/pom.xml")" > "$WD/modules.tab"

    find_modules "$dir" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "${expected}" "$(cat "$WD/modules.tab")"
}

testFindChangedModule() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
    WD="$dir"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF
    echo -e "g:a:1\tjar\tpom.xml\t${dir}\t${dir}/src\t{$dir}/src\tDIFFERENT" \
        > "$WD/modules.tab"

    find_modules "$dir" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "${expected}" "$(cat "$WD/modules.tab")"
}

DIR="$( dirname "$(pwd)/$0" )"
TESTMODE="on"
source "$DIR/analyze.sh"
set +o errexit
source "$DIR/shunit2.sh"
