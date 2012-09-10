#!/bin/bash

# To build from source (opa > 1.0.6):
echo Build
mkdir -p _build
opa opa-dynamic.opack -o opa-dynamic.exe

# Then to continuously build opa-dynamic:
# (avoid the launch it otherwise it will cycle)
# echo Continuous build
# ./opa-dynamic.exe --src-dir ../opa-dynamic --command "opa *.opack -o opa-dynamic.exe" &
