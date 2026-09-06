#!/bin/bash
# static facts: deployed artefact size (script or binary), source lines, the interpreter/runtime binary and its size, linked libraries
cd "$(dirname "$0")"
NODE=$(command -v node); PY=python3; RB=ruby; PHP=php
for s in node-single:node/single.js node-cluster:node/cluster.js rust-axum:axum/src/main.rs+axum/Cargo.toml py-stdlib:py/stdlib.py py-uvicorn:py/asgi.py rb-webrick:rb/webrick.rb rb-puma:rb/config.ru php-builtin:php/index.php; do
  n=${s%%:*}; src=${s#*:}
  lines=0; size=0; for f in ${src//+/ }; do lines=$((lines + $(wc -l < $f))); size=$((size + $(stat -f %z $f))); done
  case $n in
    node-*)      rt=$NODE ;;
    rust-axum)   rt=bin/axum; size=$(stat -f %z bin/axum) ;;
    py-*)        rt=$PY ;;
    rb-*)        rt=$RB ;;
    php-builtin) rt=$PHP ;;
  esac
  rtreal=$(readlink -f $rt 2>/dev/null || echo $rt)
  rtsize=$(stat -f %z $rtreal)
  libs=$(otool -L $rtreal 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')
  echo "$n|$src|$lines|$size|$rtreal|$rtsize|$libs"
done
