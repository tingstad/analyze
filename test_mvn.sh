#!/bin/bash

testMvnDependencyTreeOneSimpleModule() {
    local dir="$(mktemp -d)"
    mkdir -p "$dir"
    TMPDIR="$dir"
    echo -e "id1\tjar\tpom.xml\t${dir}\t${dir}/src\t{$dir}/src" \
        > "$TMPDIR/modules.tab"
    cat <<- EOF > "$TMPDIR/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF

    dependency_tree "$TMPDIR/modules.tab" "*" "$TMPDIR/mvn.dot"

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
    TMPDIR="$dir"
    echo -e "id1\tjar\tpom.xml\t${base1}\t${base1}/src\t${base1}/src\n" \
            "id2\tjar\tpom.xml\t${base2}\t${base2}/src\t${base2}/src" \
        > "$TMPDIR/modules.tab"
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

    dependency_tree "$TMPDIR/modules.tab" "*" "$TMPDIR/mvn.dot"

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
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF

    find_modules "$dir" "$dir" "$TMPDIR/modules.tab" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "$expected" "$(cat "$TMPDIR/modules.tab")"
}

testFindTwoModules() {
    local dir="$(mktemp -d)"
    local base1="$dir/module 1"
    local base2="$dir/module2"
    mkdir -p "$base1/src/main/java"
    mkdir -p "$base2/src/main/java"
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

    find_modules "$dir" "$dir" "$TMPDIR/modules.tab" >/dev/null

    read -r -d '' expected <<- EOF
		g:b:1	jar	$base2/pom.xml	$base2	$base2/src/main/java	$base2/src/main/resources	$(fingerprint "$base2/pom.xml")
		g:with-space-in-path:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "$expected" "$(cat "$TMPDIR/modules.tab")"
}

testFindNewModule() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF
    echo -e "id2\tjar\tpom.xml\tBASE\tSRC\tRESRC\tHASH" > "$dir/cache_modules.tab"

    find_modules "$dir" "$dir" "$TMPDIR/modules.tab" >/dev/null

    read -r -d '' expected <<- EOF
		id2	jar	pom.xml	BASE	SRC	RESRC	HASH
		g:a:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "Module should be in cache_modules" "$expected" "$(cat "$dir/cache_modules.tab")"
    assertEquals "Module should be in modules.tab" "$(echo "$expected"|tail -n1)" "$(cat "$TMPDIR/modules.tab")"
}

testFindUnchangedModule() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF
    echo -e "g:a:1\tjar\t$base1/pom.xml\t$base1\t$base1/src/main/java\t$base1/src/main/resources\t$(fingerprint "$base1/pom.xml")" > "$dir/cache_modules.tab"

    find_modules "$dir" "$dir" "$TMPDIR/modules.tab" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "Module should be in cache_modules" "$expected" "$(cat "$dir/cache_modules.tab")"
    assertEquals "Module should be in modules.tab" "$expected" "$(cat "$TMPDIR/modules.tab")"
}

testFindChangedModule() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
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
        > "$dir/cache_modules.tab"

    find_modules "$dir" "$dir" "$TMPDIR/modules.tab" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "Module should be in cache_modules" "$expected" "$(cat "$dir/cache_modules.tab")"
    assertEquals "Module should be in modules.tab" "$expected" "$(cat "$TMPDIR/modules.tab")"
}

testFindCachedPom() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
	EOF
    echo -e "g:a:1\tpom\t$base1/pom.xml\t$base1\t$base1/src/main/java\t$base1/src/main/resources\t$(fingerprint "$base1/pom.xml")" > "$dir/cache_modules.tab"

    find_modules "$dir" "$dir" "$TMPDIR/modules.tab" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	pom	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "Module should be in cache_modules" "$expected" "$(cat "$dir/cache_modules.tab")"
    assertEquals "Module should not be in modules.tab" "" "$(cat "$TMPDIR/modules.tab")"
}

testEndToEnd() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    local base2="$dir/module2"
    local base3="$dir/module3"
    mkdir -p "$base1/src/main/java/com/m1" "$base2/src/main/java/com/m2" "$base3/src/main/java/com/m3"
    TMPDIR="$dir"
    cat <<- EOF > "$dir/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>build-pom</artifactId>
		    <version>1</version>
		    <packaging>pom</packaging>
		    <modules>
		        <module>module1</module>
		        <module>module2</module>
		        <module>module3</module>
		    </modules>
		</project>
	EOF
    cat <<- EOF > "$base1/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>module-one</artifactId>
		    <version>1</version>
		    <dependencies><dependency>
		        <groupId>g</groupId>
		        <artifactId>module-two</artifactId>
		        <version>1</version>
		    </dependency></dependencies>
		</project>
	EOF
    cat <<- EOF > "$base2/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>module-two</artifactId>
		    <version>1</version>
		    <dependencies><dependency>
		        <groupId>g</groupId>
		        <artifactId>module-three</artifactId>
		        <version>1</version>
		    </dependency></dependencies>
		</project>
	EOF
    cat <<- EOF > "$base3/pom.xml"
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>module-three</artifactId>
		    <version>1</version>
		</project>
	EOF
    cat <<- EOF > "$base1/src/main/java/com/m1/One.java"
		package com.m1;
		import static com.m2.Two.A;
		import static com.m2.Two.B;
		import com.m3.*;
		public class One {}
	EOF
    cat <<- EOF > "$base2/src/main/java/com/m2/Two.java"
		package com.m2;
		public class Two { public static int A=1, B=2; }
	EOF
    cat <<- EOF > "$base3/src/main/java/com/m3/Three.java"
		package com.m3;
		public class Three {}
	EOF
    (cd "$dir" && mvn -B -q install -Dmaven.test.skip=true)

    local out="$(main -q "$dir")"

    read -r -d '' expected <<- EOF
		digraph {
		"g:module-one:1" -> "g:module-two:1" [penwidth=0.2];
		"g:module-two:1" -> "g:module-three:1";
		"g:module-one:1" -> "g:module-three:1" [penwidth=0.1,color=red];
		}
	EOF
    assertEquals "$expected" "$out"
}

DIR="$( dirname "$(pwd)/$0" )"
TESTMODE="on"
source "$DIR/analyze.sh"
set +o errexit
source "$DIR/shunit2.sh"
