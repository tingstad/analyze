#!/bin/bash
#set -x

testPackageDetection() {
    local src1="$(mktemp -d)"
    mkdir -p "$src1/com/foo/package1" 
    mkdir -p "$src1/com/foo/package2/bar" 
    mkdir -p "$src1/com/foo/package3/detail" 
    local src2="$(mktemp -d)"
    mkdir -p "$src2/com/foo/package1" 
    mkdir -p "$src2/com/foo/package3" 
    mkdir -p "$src2/com/foo/package4" 
    TMPDIR="$src1"
    echo -e "id1\tjar\tpom.xml\t$src1\t$src1\t$src1" > "$TMPDIR/modules.tab"
    echo -e "id2\tjar\tpom.xml\t$src2\t$src2\t$src2" >>"$TMPDIR/modules.tab"

    packages "$TMPDIR/modules.tab" "$TMPDIR/packages-modules.tsv"

    assertTrue '' "[ -f "$TMPDIR/packages-modules.tsv" ]"
    read -r -d '' expected <<- TIL
		com.foo.package2	id1
		com.foo.package3.detail	id1
		com.foo.package4	id2
	TIL
    assertEquals '' "$expected" "$(cat "$TMPDIR/packages-modules.tsv")"
}

testPackageDetectionSingleModule() {
    local src1="$(mktemp -d)"
    mkdir -p "$src1/com/foo/package1" 
    mkdir -p "$src1/com/foo/package2/bar" 
    TMPDIR="$src1"
    echo -e "id1\tjar\tpom.xml\t$src1\t$src1\t$src1" > "$TMPDIR/modules.tab"

    packages "$TMPDIR/modules.tab" "$TMPDIR/packages-modules.tsv"

    read -r -d '' expected <<- TIL
		com	id1
	TIL
    assertEquals '' "$expected" "$(cat "$TMPDIR/packages-modules.tsv")"
}

testUsages() {
    local src1="$(mktemp -d)"
    mkdir -p "$src1/src/com/foo/package2" 
    local src2="$(mktemp -d)"
    mkdir -p "$src2/src/com/foo/package4" 
    TMPDIR="$src1"
    echo -e "package com.foo.package2;\nimport com.foo.package4.Two;public class One{} " \
        > "$src1/src/com/foo/package2/One.java"
    echo -e "package com.foo.package4;\nimport com.foo.package2.One;public class Two{} " \
        > "$src2/src/com/foo/package4/Two.java"
    echo -e "id1\tjar\tpom.xml\t$src1\t$src1/src\t$src1/src" > "$TMPDIR/modules.tab"
    echo -e "id2\tjar\tpom.xml\t$src2\t$src2/src\t$src2/src" >>"$TMPDIR/modules.tab"
    cat <<- TIL > "$TMPDIR/packages-modules.tsv"
		com.foo.package2	id1
		com.foo.package4	id2
	TIL

    usages "$TMPDIR/modules.tab" "$TMPDIR/packages-modules.tsv" "$TMPDIR/deps.tsv"

    read -r -d '' expected <<- TIL
		id1	com/foo/package2/One.java	com.foo.package2
		id1	com/foo/package2/One.java	com.foo.package4
		id2	com/foo/package4/Two.java	com.foo.package2
		id2	com/foo/package4/Two.java	com.foo.package4
	TIL
    assertEquals '' "$(echo -e "$expected" | sort)" "$(cat "$TMPDIR/deps-detailed.tsv" | sort)"
    assertEquals '' "$(echo -e "id1\tid2\t1\nid2\tid1\t1" | sort)" "$(cat "$TMPDIR/deps.tsv" | sort)"
}

testUsages2() {
    local src1="$(mktemp -d)"
    mkdir -p "$src1/src/com/foo/package2" 
    local src2="$(mktemp -d)"
    mkdir -p "$src2/src/com/foo/package4" 
    TMPDIR="$src1"
    echo -e "package com.foo.package2;\nimport com.foo.package4.Two;public class One{} " \
        > "$src1/src/com/foo/package2/One.java"
    echo -e "package com.foo.package4;\npublic class Two{} " \
        > "$src2/src/com/foo/package4/Two.java"
    echo -e "id1\tjar\tpom.xml\t${src1}\t${src1}/src\t{$src1}/src" > "$TMPDIR/modules.tab"
    echo -e "id2\tjar\tpom.xml\t${src2}\t${src2}/src\t{$src2}/src" >>"$TMPDIR/modules.tab"
    cat <<- TIL > "$TMPDIR/packages-modules.tsv"
		com.foo.package2	id1
		com.foo.package4	id2
	TIL

    usages "$TMPDIR/modules.tab" "$TMPDIR/packages-modules.tsv" "$TMPDIR/deps.tsv"

    read -r -d '' expected <<- TIL
		id1	com/foo/package2/One.java	com.foo.package2
		id1	com/foo/package2/One.java	com.foo.package4
		id2	com/foo/package4/Two.java	com.foo.package4
	TIL
    assertEquals '' "$(echo -e "$expected" | sort)" "$(cat "$TMPDIR/deps-detailed.tsv" | sort)"
    assertEquals '' "$(echo -e "id1\tid2\t1" | sort)" "$(cat "$TMPDIR/deps.tsv" | sort)"
}

testNoParameters() {
    local out="$(main 2>&1)"

    read -r -d '' expected <<- EOF
		Missing target dir parameter
		Usage: $0 [OPTION...] DIR
	EOF
    assertEquals "$expected" "$(echo "$out" | head -n2)"
}

testNotExistingTargetArgument() {
    local out="$(main doesNotExist 2>&1)"

    read -r -d '' expected <<- EOF
		'doesNotExist' is not a directory
		Usage: $0 [OPTION...] DIR
	EOF
    assertEquals "$expected" "$(echo "$out" | head -n2)"
}

testArgumentHelp() {
    local out="$(main -h)"

    read -r -d '' expected <<- EOF
		Usage: $0 [OPTION...] DIR
		
		  -h            Help
		  -i pattern    Filter dependencies using pattern. Syntax is
		                [groupId]:[artifactId]:[type]:[version]
		  -o filename   Write output to file
		  -q            Quiet
	EOF
    assertEquals "$expected" "$out"
}

testArgumentUnknown() {
    local out="$(main -x 2>&1)"

    read -r -d '' expected <<- EOF
		Invalid option: -x
		Usage: $0 [OPTION...] DIR
	EOF
    assertEquals "$expected" "$(echo "$out" | head -n2)"
}

testArgumentNotDirectory() {
    local out="$(main 'file' 2>&1)"

    read -r -d '' expected <<- EOF
		'file' is not a directory
		Usage: $0 [OPTION...] DIR
	EOF
    assertEquals "$expected" "$(echo "$out" | head -n2)"
}

testArgumentiWithoutRequiredParameter() {
    local out="$(main -i 2>&1)"

    read -r -d '' expected <<- EOF
		Option -i requires an argument
		Usage: $0 [OPTION...] DIR
	EOF
    assertEquals "$expected" "$(echo "$out" | head -n2)"
}

testArgumentoWithoutRequiredParameter() {
    local out="$(main -o 2>&1)"

    read -r -d '' expected <<- EOF
		Option -o requires an argument
		Usage: $0 [OPTION...] DIR
	EOF
    assertEquals "$expected" "$(echo "$out" | head -n2)"
}

testArgumentsSuperflous() {
    local out="$(main one two 2>&1)"

    read -r -d '' expected <<- EOF
		Too many arguments.
		Usage: $0 [OPTION...] DIR
	EOF
    assertEquals "$expected" "$(echo "$out" | head -n2)"
}

testArgumentsSuperflousWithOption() {
    local out="$(main -i inc one two 2>&1)"

    read -r -d '' expected <<- EOF
		Too many arguments.
		Usage: $0 [OPTION...] DIR
	EOF
    assertEquals "$expected" "$(echo "$out" | head -n2)"
}

testNoModulesFound() {
    local dir="$(mktemp -d)"
    TMPDIR="$dir"
    local out="$(main -q "$dir" 2>&1)"

    assertEquals "No modules (pom.xml files) found" "$out"
}

testArtifactIdFromSimplePom() {
    actual=$(cat <<- EOF | artifact_id_from_pom 
		<project xmlns="http://maven.apache.org/POM/4.0.0">
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		</project>
		EOF
    )
 
    assertEquals "g:a:1" "$actual"
}

testArtifactIdFromPom() {
    actual=$(cat <<- EOF | artifact_id_from_pom
		<project xmlns="http://maven.apache.org/POM/4.0.0">
		    <modelVersion>4.0.0</modelVersion>
		    <groupId>g</groupId>
		    <artifactId>a</artifactId>
		    <version>1</version>
		    <build>
		      <pluginManagement>
		        <plugins>
		          <plugin>
		            <artifactId>maven-antrun-plugin</artifactId>
		            <version>1.3</version>
		          </plugin>
		        </plugins>
		      </pluginManagement>
		    </build>
		</project>
		EOF
    )

    assertEquals "g:a:1" "$actual"
}

testThatEffectivePomFailsWithutArgument() {
    local actual=$(effective_pom 2>&1)

    assertEquals 'Invalid argument' "$actual"
}

testModuleSize() {
    local dir="$(mktemp -d)"
    mkdir -p "$dir/src/pkg"
    cat <<- EOF > "$dir/src/pkg/One.java"
		package pkg;
		public class One{}
		// This file is 3 lines
	EOF
    cat <<- EOF > "$dir/src/pkg/Two.java"
		package pkg;
		
		public class Two{}
		// This file is
		// 5 lines
	EOF

    local actual=$(module_size "$dir")

    assertEquals '8' "$actual"
}

testModuleSizes() {
    local dir="$(mktemp -d)"
    mkdir -p "$dir/one" "$dir/two"
    cat <<- EOF > "$dir/one/One.java"
		public class One{}
		// This file is 2 lines
	EOF
    cat <<- EOF > "$dir/two/Two.java"
		public class Two{}
		// This file is
		// 3 lines
	EOF
    read -r -d '' modules <<- EOF
		g:module-one:1	$dir/one/
		g:module-two:1	$dir/two/
	EOF

    local actual=$(echo "$modules" | sizes)

    read -r -d '' expected <<- EOF
		g:module-one:1	2
		g:module-two:1	3
	EOF
    assertEquals "$expected" "$actual"
}

testFindModulesNoArgumentsShouldFail() {
    local actual="$(find_modules 2>&1)"

    assertEquals "Illegal argument" "$actual"
}

testFindModulesOneArgumentShouldFail() {
    local actual="$(find_modules WRONG 2>&1)"

    assertEquals "Illegal argument" "$actual"
}

testFindModulesTooManyArguments() {
    local actual="$(find_modules . . . . 2>&1)"

    assertEquals "Illegal argument" "$actual"
}

testMiddleLine0() {
    assertEquals "0" "$(middle_line 0)"
}
testMiddleLine1() {
    assertEquals "1" "$(middle_line 1)"
}
testMiddleLine2() {
    assertEquals "1" "$(middle_line 2)"
}
testMiddleLine3() {
    assertEquals "1" "$(middle_line 3)"
}
testMiddleLine4() {
    assertEquals "2" "$(middle_line 4)"
}

testFinalGraph() {
    local dir="$(mktemp -d)"
    cat <<- EOF > "$dir/mvn-deps.dot"
		digraph {
		    "g:module-one:jar:1" -> "g:module-two:jar:1:compile" ; 
		    "g:module-two:jar:1" -> "g:module-three:jar:1:compile" ; 
		    "g:module-two:jar:1:compile" -> "g:module-three:jar:1:compile" ; 
		}
	EOF
    cat <<- EOF > "$dir/deps.tsv"
		g:module-one:1	g:module-three:1	1
		g:module-one:1	g:module-two:1	2
	EOF
    cat <<- EOF > "$dir/sizes.tab"
		g:module-one:1	10
		g:module-two:1	20
	EOF

    local out="$(mvn_deps "$dir/deps.tsv" "$dir/mvn-deps.dot" "$dir/sizes.tab")"

    read -r -d '' expected <<- EOF
		digraph {
		"g:module-one:1" [width=0.75,height=0.5];
		"g:module-two:1" [width=1.5,height=1.0];
		"g:module-one:1" -> "g:module-two:1" [penwidth=0.2];
		"g:module-two:1" -> "g:module-three:1";
		"g:module-one:1" -> "g:module-three:1" [penwidth=0.1,color=red];
		}
	EOF
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

