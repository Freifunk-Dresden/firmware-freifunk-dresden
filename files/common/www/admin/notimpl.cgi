#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Allgemein: Kennwort"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>
<fieldset class="bubble">
<legend>Info</legend>
	Die Firmware ist eine Testversion. Daher sind noch unwichtige Funktionen nicht implementiert.<br>
	Diese Funktionen werden nach und nach eingebaut.
</fieldset>
EOM

. /usr/lib/www/page-post.sh
