#!/bin/bash

testMvnDependencyTreeOneSimpleModule() {
    local dir="$(mktemp -d)"
    mkdir -p "$dir"
    TMPDIR="$dir"
    echo -e "id1\tjar\tpom.xml\t${dir}\t${dir}/src\t${dir}/src" \
        > "$TMPDIR/modules.tab"
    cat <<- EOF > "$TMPDIR/pom.xml"
		$(project g a 1)
	EOF

    dependency_tree "$TMPDIR/modules.tab" "*" "$TMPDIR/mvn.dot" >/dev/null

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
		$(project g a 1)
	EOF
    cat <<- EOF > "$base2/pom.xml"
		$(project g b 1 \
		    "$(dependency g a 1)" \
		)
	EOF
    echo -e "public class One {}" \
        > "$base1/src/main/java/One.java"
    (cd "$base1" && mvn -B -q install -Dmaven.test.skip=true)

    dependency_tree "$TMPDIR/modules.tab" "*" "$TMPDIR/mvn.dot" >/dev/null

    expected=$(echo 'digraph "g:a:jar:1" { ' \
        | append ' } digraph "g:b:jar:1" { ' \
        | append "\t"'"g:b:jar:1" -> "g:a:jar:1:compile" ; ' \
        | append ' } ')
    assertEquals "${expected}" "$(cat "$TMPDIR/mvn.dot")"
}

append() {
    awk -v str="$1" '{ print } END{ print str }'
}

testFindOneModule() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		$(project g a 1)
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
		$(project g with-space-in-path 1)
	EOF
    cat <<- EOF > "$base2/pom.xml"
		$(project g b 1)
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
		$(project g a 1)
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
		$(project g a 1)
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
		$(project g a 1)
	EOF
    echo -e "g:a:1\tjar\tpom.xml\t${dir}\t${dir}/src\t${dir}/src\tDIFFERENT" \
        > "$dir/cache_modules.tab"

    find_modules "$dir" "$dir" "$TMPDIR/modules.tab" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	jar	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "$expected" "$(cat "$dir/cache_modules.tab")"
    assertEquals "$expected" "$(cat "$TMPDIR/modules.tab")"
}

testFindCachedPom() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    mkdir -p "$base1/src/main/java"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		$(project g a 1)
	EOF
    echo -e "g:a:1\tpom\t$base1/pom.xml\t$base1\t$base1/src/main/java\t$base1/src/main/resources\t$(fingerprint "$base1/pom.xml")" > "$dir/cache_modules.tab"

    find_modules "$dir" "$dir" "$TMPDIR/modules.tab" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	pom	$base1/pom.xml	$base1	$base1/src/main/java	$base1/src/main/resources	$(fingerprint "$base1/pom.xml")
	EOF
    assertEquals "Module should be in cache_modules" "$expected" "$(cat "$dir/cache_modules.tab")"
    assertEquals "Module should not be in modules.tab" "" "$(cat "$TMPDIR/modules.tab")"
}

testUndeclaredUse() {
    local dir="$(mktemp -d)"
    local base1="$dir/module1"
    local base2="$dir/module2"
    local base3="$dir/module3"
    mkdir -p "$base1/src/main/java/com" "$base2/src/main/java/com" "$base3/src/main/java/com"
    TMPDIR="$dir"
    cat <<- EOF > "$base1/pom.xml"
		$(project g a 1 \
		    "$(dependency g b 1)" \
		)
	EOF
    cat <<- EOF > "$base2/pom.xml"
		$(project g b 1 \
		    "$(dependency g c 1)" \
		)
	EOF
    cat <<- EOF > "$base3/pom.xml"
		$(project g c 1)
	EOF
    cat <<- EOF > "$base1/src/main/java/com/A.java"
		package com;
		import com.C;
		public class A { C c; }
	EOF
    cat <<- EOF > "$base2/src/main/java/com/B.java"
		package com;
		public class B {}
	EOF
    cat <<- EOF > "$base3/src/main/java/com/C.java"
		package com;
		public class C {}
	EOF
    for d in "$base3" "$base2" "$base1"; do
        (cd "$d" && mvn -B -q -o install -Dmaven.test.skip=true)
    done
    cat <<- EOF > "$TMPDIR/modules.tab"
		g:a:1	jar	pom.xml	${base1}
		g:b:1	jar	pom.xml	${base2}
		g:c:1	jar	pom.xml	${base3}
	EOF

    undeclared_use "$TMPDIR/modules.tab" "$TMPDIR/undeclared.tab" >/dev/null

    read -r -d '' expected <<- EOF
		g:a:1	g:c:1	0
	EOF
    assertEquals "$expected" "$(cat "$TMPDIR/undeclared.tab")"
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
		$(project g module-one 1 \
		    "$(dependency g module-two 1)" \
		)
	EOF
    cat <<- EOF > "$base2/pom.xml"
		$(project g module-two 1 \
		    "$(dependency g module-three 1)" \
		)
	EOF
    cat <<- EOF > "$base3/pom.xml"
		$(project g module-three 1)
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
		"g:module-three:1" [fixedsize=true,width=2.37171,height=1.58114];
		"g:module-two:1" [fixedsize=true,width=2.37171,height=1.58114];
		"g:module-one:1" [fixedsize=true,width=3.75,height=2.5];
		"g:module-one:1" -> "g:module-two:1" [penwidth=0.2];
		"g:module-two:1" -> "g:module-three:1";
		"g:module-one:1" -> "g:module-three:1" [penwidth=0.1,color=red];
		}
	EOF
    assertEquals "$expected" "$out"
}

project() {
    cat <<- EOF
		<project>
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>$1</groupId>
		    <artifactId>$2</artifactId>
		    <version>$3</version>
		    <properties>
		        <maven.compiler.source>1.6</maven.compiler.source>
		        <maven.compiler.target>1.6</maven.compiler.target>
		    </properties>
		    <dependencies>$4</dependencies>
		</project>
	EOF
}

dependency() {
    cat <<- EOF
		    <dependency>
		        <groupId>$1</groupId>
		        <artifactId>$2</artifactId>
		        <version>$3</version>
		    </dependency>
	EOF
}

DIR="$( dirname "$(pwd)/$0" )"
TESTMODE="on"
source "$DIR/analyze.sh"
set +o errexit
source "$DIR/shunit2.sh"
