#!/bin/sh

export TITLE="Verwaltung > Wartung > Remote-Syslog"
. /usr/lib/www/page-pre.sh ${0%/*}


if [ -n "$form_syslog_submit" ]; then
	uci set system.@system[0].log_ip="$form_syslog_ip"
	uci set system.@system[0].log_port="$form_syslog_port"
	uci_commit.sh
	/etc/init.d/log restart
	notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind sofort aktiv."
fi

cat<<EOM
<form name="form_wshaper" action="syslog.cgi" method="POST">
<fieldset class="bubble">
<legend>Remote-Syslog</legend>
<table>
	<tr><td colspan="2">
	Der Syslog kann via Netzwerk an einen Syslog-Server gesendet werden.<br/><br/>
	Beispiel-Config-File f&uuml;r <b>rsyslogd</b>: /etc/rsyslog.d/10-freifunk.conf<br/>
	Dieses File erzeugt f&uuml;r jeden Knoten ein eigenes Logfile unter /var/log/freifunk-router/<br/>
<pre>
template(name="myfile" type="string" string="/var/log/freifunk-router/node.%syslogtag:R,ERE,1,FIELD:([0-9]+):--end%")
:syslogtag, startswith, "freifunk." /var/log/freifunk-router/all.log
:syslogtag, startswith, "freifunk." { action(type="omfile" DynaFile="myfile") stop }
</pre>
	</td></tr>

	<tr>
	<th width="120">Syslog-Server-IP</th>
	<td class="nowrap"><input name="form_syslog_ip" size="15" type="text" value="$(uci get system.@system[0].log_ip)"></td></tr>
	<tr>
	<th >Syslog-Server-Port (UDP)</th>
	<td class="nowrap"><input name="form_syslog_port" size="5"  type="text" value="$(uci get system.@system[0].log_port)"></td></tr>
	<tr><td colspan="2">&nbsp;</td></tr>
	<tr>
	<td colspan="2" class="nowrap"><input name="form_syslog_submit" title="Einstellungen &uuml;bernehmen." type="SUBMIT" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_syslog_abort" title="Abbrechen und &Auml;nderungen verwerfen." type="submit" value="Abbrechen"></td> </tr>
</table>
</fieldset>
</form>
EOM

. /usr/lib/www/page-post.sh ${0%/*}
