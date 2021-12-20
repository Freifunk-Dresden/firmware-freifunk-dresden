#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

# slash will be removed; keep it sill active if used
if [ "$(uci -q get ddmesh.system.disable_splash)" = "0" ]; then
echo '<tr><td><div class="plugin"><a class="plugin" href="custom.cgi">Custom-Splash</a></div></td></tr>'
fi