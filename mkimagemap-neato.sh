#!/bin/sh

python lexiconGrapher.py > "$1.dot"
neato -Tpng -Gepsilon=.00001 -Gsplines=true -Gmaxiter=30000 -Gpack=true -Gsep=.1 -Goverlap=false "$1.dot" > "$1.png"
echo "<img border=\"0\" src=\"$1.png\" usemap=\"#lexicon\">" > "$1.html"
neato -Tcmapx -Gepsilon=.00001 -Gsplines=true -Gmaxiter=30000 -Gpack=true -Gsep=.1 -Goverlap=false "$1.dot" >> "$1.html"
