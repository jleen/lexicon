#!/bin/sh

python lexiconGrapher.py > $1.dot
dot -Tpng $1.dot > $1.png
echo '<img border="0" src="lexgraph.png" usemap="#lexicon">' > $1.html
dot -Tcmapx $1.dot >> $1.html
