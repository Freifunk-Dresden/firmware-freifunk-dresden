#!/bin/sh

export ALLOW_PAGE=1
export NOMENU=1
export HTTP_ALLOW_GET_REQUEST=1
export TITLE="Licenses"
. /usr/lib/www/page-pre.sh

display_title() {
 file=/usr/lib/license/$1-${LANG}.txt
 title="$(cat $file | sed -n '1,1{s#[ 	]*\[[ 	]*\(.*\)\].*#\1#p}')"
 echo "$title"
}

display_text() {
 file=/usr/lib/license/$1-${LANG}.txt
 title="$(cat $file | sed -n '1,1{s#[ 	]*\[[ 	]*\(.*\)\].*#\1#p}')"
 cat<<EOM
 <fieldset class="bubble">
 <legend>$title</legend>
 <div>
$(cat $file | sed 's#ä#\&auml;#g;s#Ä#\&Auml;#g;s#ö#\&ouml;#g;s#Ö#\&Ouml;#g;s#ü#\&uuml;#g;s#Ü#\&Uuml;#g;s#ß#\&szlig;#g;s#$#<br/>#g;s#----*#<hr size="1" idth="90%">#g')
 </div>
 </fieldset>
EOM
}

case "$license" in
	1) display_text agreement ;;
	2) display_text pico ;;
	3) display_text gpl ;;
	4) display_text lgpl ;;
 	*)
 cat<<EOM
 <fieldset class="bubble">
 <legend>License/Copyrights</legend>
 Freifunk Dresden Firmware is free software, provided AS-IS and without any warranty.<br/>
 Copyright 2014 Freifunk Dresden

 <p>
 If not otherwise stated in the source files, all parts of the firmware developed by Freifunk Dresden is provided under the terms of the GNU Less General Public License Version 3.
 The exact GPL license text can be found here: <a href="/license.cgi?license=4">LICENSE</a>.
 </p>
 <p>
 The <a href="http://downloads.openwrt.org/">OpenWrt distribution</a> (precompiled images etc.) bundles a lot of third party applications and modules which are available under various other Open Source licenses or Public Domain. The sources for those packages can be found on the  <a href="http://downloads.openwrt.org/sources/">OpenWrt mirror</a>. Please refer to these source packages to find out which license applies to them.
 </p>
<p>
If not otherwise stated in the source files, the OpenWrt build environment is provided under the terms of the GNU General Public License Version 2. The exact GPLv2 license text can be found in the file LICENSE in the source repository at openwrt.org .
</p>
<p>
The freifunk dresden firmware build system it self is currently closed source.
The freifunk server (vserver) are closed source.
</p>
</fieldset>
<br/>
<fieldset class="bubble">
<ul>
<li><a href="/license.cgi?license=1">$(display_title agreement)</a></li>                                        
<li><a href="/license.cgi?license=2">$(display_title pico)</a></li>                                            
<li><a href="/license.cgi?license=3">$(display_title gpl)</a></li>                                            
<li><a href="/license.cgi?license=4">$(display_title lgpl)</a></li>                                            
</ul>
</fieldset>


EOM
	;;
esac

. /usr/lib/www/page-post.sh

fi #autosetup


