#!/bin/sh

python lexiconGrapher.py > "$1.dot"
neato -Tpng -Gsplines=true -Gstart=self -Gepsilon=.00000001 -Goverlap=orthoyx "$1.dot" > "$1.png"
echo "<img border=\"0\" src=\"$1.png\" usemap=\"#lexicon\">" > "$1.html"
neato -Tcmapx -Gsplines=true -Gstart=self -Goverlap=orthoyx -Gepsilon=.00000001 "$1.dot" >> "$1.html"
