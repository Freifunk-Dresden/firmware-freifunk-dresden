#!/bin/bash

if [ -z "$1" ]; then
cat <<EOM
# filtert nur die config schalter raus und sort diese.
# Alle enabled modules werden auf 'n' gestellt. menuconfig wird die notwendigen schalter wieder enablen
# das resultat kann dann nach buildroot/.config kopiert werden.
# make menuconfig erzeugt wieder ein strukturiertes .config was die gleichen schalter aber gesetzt hat.
# angewendt auf *.ddmesh und *.original kann man dann mit "meld" gut die freifunk anpassungen sehen
#    und auf andere configs anwenden.
# usage: $0 <config>
#  	gibt nach stdout aus
EOM
exit
fi

cat $1 | sed -n '/CONFIG_/p;/#[ ]*CONFIG_/p' | sed 's#=m#=n#' | sort -u
