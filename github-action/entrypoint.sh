#!/bin/sh -l

out=$(/app/mzap $1)
echo "output=$out" >> $GITHUB_ENV
