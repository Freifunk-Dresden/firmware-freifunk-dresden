#!/bin/sh

export TITLE="Verwaltung > Expert > DynDNS"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -z "$QUERY_STRING" ]; then

cat<<EOM
<form name="form_ddns" action="ddns.cgi" class="form" method="POST">
<fieldset class="bubble">
<legend>DynDNS-Einstellungen</legend>
<table>

<tr><th>Aktiviere DynDNS:</th><td><INPUT NAME="form_ddns_enabled" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddns.dyndns.enabled)" = "1" ];then echo ' checked="checked"';fi)></td></tr>

<tr><th>DynDNS-Dienst:</th>
<td><select name="form_ddns_service_name" size="1">
<option value=""> - manuelle DynDNS-URL</option>
EOM
export service=$(uci -q get ddns.dyndns.service_name)
cat /etc/ddns/services | awk '
	{
		value=$1
		service=ENVIRON["service"]
		gsub(/"/,"",value)
		if(value == service)
		{
			sel="selected";
		}
		else
		{
			sel="";
		}
		printf("<option %s value=\"%s\">%s</option>",sel,value,value)
	}'

cat<<EOM
</select> </td>
</tr>

<tr><th>Update-URL:</th>
<td><INPUT NAME="form_ddns_use_https" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddns.dyndns.use_https)" = "1" ];then echo ' checked="checked"';fi)<input name="form_ddns_update_url" size="32" type="text" value="$(uci get ddns.dyndns.update_url)">Zu verwendende URL, wenn DynDNS-Dienst auf <i>manuelle DynDNS-URL</i> gestellt ist. Siehe <a href="https://openwrt.org/docs/guide-user/base-system/ddns">openwrt.org: ddns</a></td>
</tr>

<tr><th>Domain:</th>
<td><input name="form_ddns_domain" size="32" type="text" value="$(uci get ddns.dyndns.domain)"></td>
</tr>

<tr><th>Username:</th>
<td><input name="form_ddns_username" size="32" type="text" value="$(uci get ddns.dyndns.username)"></td>
</tr>

<tr><th>Passwort:</th>
<td><input name="form_ddns_password" size="32" type="text" value="$(uci get ddns.dyndns.password)"></td>
</tr>

<tr><th>IP-Check-Intervall:</th>
<td><input name="form_ddns_check_interval" size="32" type="text" value="$(uci get ddns.dyndns.check_interval)"> min</td>
</tr>

<tr><th>Zwangsaktualisierungs-Intervall:</th>
<td><input name="form_ddns_force_interval" size="32" type="text" value="$(uci get ddns.dyndns.force_interval)"> days</td>
</tr>

<tr><td colspan="2">&nbsp;</td></tr>
<tr>
<td colspan="2"><input name="form_ddns_submit" title="Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." type="submit" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_ddns_abort" title="Abbrechen und &Auml;nderungen verwerfen." type="submit" value="Abbrechen"></td>
</tr>
</table>
</fieldset>
</form>
<br>

EOM

else #query string

	if [ -n "$form_ddns_submit" ]; then
		uci set ddns.dyndns.enabled="$form_ddns_enabled"
		uci set ddns.dyndns.service_name="$form_ddns_service_name"
		if [ -n "$form_ddns_service_name" ]; then
			uci -q delete ddns.dyndns.update_url
			uci -q delete ddns.dyndns.use_https
		else
			# https to http (see openwrt ddns doc)
			form_ddns_update_url="${form_ddns_update_url/https:/http}"
			uci set ddns.dyndns.use_https="$form_ddns_use_https"
			uci set ddns.dyndns.update_url="$form_ddns_update_url"
		fi
		uci set ddns.dyndns.username="$form_ddns_username"
		uci set ddns.dyndns.password="$form_ddns_password"

		#minutes
		if [ "$form_ddns_check_interval" -lt 10 ]; then
			$form_ddns_check_interval=10
		fi
		uci set ddns.dyndns.check_interval="$form_ddns_check_interval"

		#days
		if [ "$form_ddns_force_interval" -lt 1 ]; then
			$form_ddns_force_interval=1
		fi
		uci set ddns.dyndns.force_interval="$form_ddns_force_interval"

		uci set ddns.dyndns.domain="$form_ddns_domain"

		uci set ddmesh.boot.boot_step=2
		uci_commit.sh
		notebox "Die Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst nach dem n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv."
	else #submit
		notebox "Es wurden keine Einstellungen ge&auml;ndert."

	fi #submit
fi #query string

. /usr/lib/www/page-post.sh ${0%/*}
