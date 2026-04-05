#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Infos: WLAN-Scan"

. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<H2>$TITLE</H2>
<br>
<fieldset class="bubble">
<legend>Access Points (Automatische Aktualisierung)</legend>
<div id="ajax_wlan">
Scanning...
EOM

#/www/admin/ajax-wlan.cgi no-html-header

cat<<EOM
</div>
</fieldset>
<SCRIPT LANGUAGE="JavaScript" TYPE="text/javascript"><!--
ajax_wlan();
//--></SCRIPT>

EOM

. /usr/lib/www/page-post.sh ${0%/*}
