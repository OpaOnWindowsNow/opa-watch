#!/bin/bash

# To build from source (opa > 1.0.6):
echo Build
mkdir -p _build
opa opa-watch.opack -o opa-watch.exe

# Then to continuously build opa-watch:
# (avoid the launch it otherwise it will cycle)
# echo Continuous build
# ./opa-watch.exe --src-dir ../opa-watch --command "opa *.opack -o opa-watch.exe" &
