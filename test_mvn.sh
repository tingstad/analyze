testMvnDependencyTreeOneSimpleModule() {
    local dir="$(mktemp -d)"
    mkdir -p "$dir"
    WD="$dir"
    TARGET_DIR="$dir"
    echo -e "id1\tjar\tpom.xml\t${dir}\t${dir}/src\t{$dir}/src" > "$WD/modules.tab"
    cat <<- EOF > "$TARGET_DIR/pom.xml"
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
    local base1="$dir/module1"
    local base2="$dir/module2"
    mkdir -p "$base1/src/main/java"
    mkdir -p "$base2/src/main/java"
    WD="$dir"
    TARGET_DIR="$dir"
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
    (cd "$base1" && mvn -B -q -o install -Dmaven.test.skip=true)

    dependency-tree

    expected=$(echo 'digraph "g:a:jar:1" { '\
        | sed '$a\ } digraph "g:b:jar:1" { '\
        | sed '$a\\t"g:b:jar:1" -> "g:a:jar:1:compile" ; '\
        | sed '$a\ } ')
    assertEquals "${expected}" "$(cat "$WD/mvn.dot")"
}

DIR="$( dirname "$(pwd)/$0" )"
TESTMODE="on"
source "$DIR/analyze.sh"
set +o errexit
source "$DIR/shunit2.sh"
