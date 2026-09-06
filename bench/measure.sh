#!/bin/sh
# usage: measure.sh LABEL OUTFILE cmd args...   (stdout of the command -> OUTFILE)
label=$1; out=$2; shift 2
best=; bestrss=; all=
for k in 1 2 3; do
  /usr/bin/time -l "$@" > "$out" 2> "$out.time" || { echo "$label: FAILED rc=$? (run $k)"; cat "$out.time"; exit 1; }
  real=$(awk '/real/{print $1}' "$out.time")
  rss=$(awk '/maximum resident set size/{print $1}' "$out.time")
  all="$all $real"
  if [ -z "$best" ] || [ "$(echo "$real < $best" | bc)" = 1 ]; then best=$real; bestrss=$rss; fi
done
echo "$label: best_real=${best}s rss=${bestrss}B runs=[$all]"
