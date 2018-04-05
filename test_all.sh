#!/bin/bash

./test.sh && \
./test_mvn.sh
awk -f test_dep_tree.awk -f dependency_tree.awk

