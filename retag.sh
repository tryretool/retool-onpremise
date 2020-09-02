#!/bin/bash
B=$(git rev-list HEAD -- retag.sh | tail -1)
git tag -f testcase-A $B~2 &&
git tag -f testcase-B $B~1 &&
git tag -f testcase-C $B