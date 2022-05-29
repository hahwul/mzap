#!/bin/sh -l

out=$(/app/mzap $1)
echo "::set-output name=output::$out"