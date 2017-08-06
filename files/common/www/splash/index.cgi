#!/bin/sh

export TITLE="Freifunk Dresden"
export HTTP_ALLOW_GET_REQUEST=1
remote_ip=${REMOTE_ADDR#*=}
remote_mac=$(/usr/lib/ddmesh/ddmesh-splash.sh getmac $remote_ip)

if [ -z $remote_mac ]; then
	export REDIRECT=0
	. /usr/lib/www/splash-pre.sh
        cat <<EOM
        <font color="red" size="+1">Ihre IP Addresse ($remote_ip) wurde nicht per DHCP von diesem Knoten vergeben.</font><br><br>
        Normalerweise wird per DHCP die IP Adresse vergeben. Wurde eine feste IP verwendet, so kann keine
        MAC bestimmt werden.
EOM
	. /usr/lib/www/splash-post.sh
        exit
fi

export REDIRECT=1

. /usr/lib/www/splash-pre.sh

if [ -z "$form_submit_accept" -a -z "$form_submit_abort" ]; then

cat<<EOM
<fieldset class="bubble">
Dies ist ein Freifunk WLAN-Access-Point.<br/>
Informationen &uuml;ber das Freifunk-Projekt finden sich im Internet unter <A HREF="http://$FFDD/">http://$FFDD/</A><br/>
Es gelten die folgenden <a href="license.cgi?license=1">Nutzungsbedingungen</a> und das <a href="license.cgi?license=2">Pico Agreement</a>, welche akzeptiert werden m&uuml;ssen!
Der Zugang ist kostenlos. Es besteht kein Anspruch oder Garantie auf eine Internetverbindung.<br />
<h2>Wenn Sie die Nutzungsbedingungen nicht akzeptieren, beenden Sie die Verbindung zum Netzwerk!</h2>
<br/>
<form class="splash" action="/index.cgi" method="POST">
<input type="hidden" name="form_host" value="$host">
<input type="hidden" name="form_uri" value="$uri">
<!-- <input type="submit" name="form_submit_abort" value="Nein, Akzeptiere Bedingungen nicht"> -->
<input type="checkbox" name="form_check" value="1">
<input type="submit" name="form_submit_accept" value="Ja, Akzeptiere Bedingungen">
</form>
<br/>
Folgende Daten werden speichert:<br/>
<b>Ihre IP:</b> $remote_ip<br />
<b>Ihre MAC:</b> $remote_mac<br />
</fieldset>
EOM

echo "<div>"
if [ -f /www/custom/custom.url ]; then
	url="$(cat /www/custom/custom.url | sed '1,1{s#[`$()]##}')"
	uclient-fetch -O - "$url"
else
	cat /www/custom/custom.html
fi
echo "</div>"

else
	if [ -n "$form_check" ]
        then
                /usr/lib/ddmesh/ddmesh-splash.sh addmac $remote_mac
                #remove http://host/ from uri if any and add it if missing
                form_uri="http://$form_host/$(uhttpd -d $form_uri | sed 's#^http://[^/]\+/##;s#^/##')"
cat <<EOM
                Sie haben die Nutzungsbedingungen akzeptiert.<br />
                <b>MAC:</b>$remote_mac<br />
                <b>Aktuelle IP:</b>$remote_ip <br />
                Weiter zu: <a href="$form_uri">$form_host</a>
EOM
        else
cat <<EOM
                Sie haben die Nutzungsbedingungen nicht akzeptiert. Ihnen ist es nicht erlaubt das Freifunk-Netz zu nutzen.<br />
                Trennen Sie die Verbindung zum Netzwerk!
EOM
        fi
fi



. /usr/lib/www/splash-post.sh

