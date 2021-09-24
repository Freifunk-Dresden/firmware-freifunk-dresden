// Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
// GNU General Public License Version 3
$(document).ready(main);

function main()
{
	if (document.all)
	{
		document.onkeydown = help;
		document.onhelp = function(){return false;}
	}
	else
	{
		document.onkeypress = help;
	}
}

function help(e)
{
	if (!e) e = event;
	// (virt)KeyVal is Konqueror, charCode is Moz/Firefox, else MSIE, Netscape, Opera
	if (26 == e.virtKeyVal || !e.keyVal && !e.charCode && 112 == (e.which || e.keyCode))
	{
		var o = null;
		if (e.preventDefault)
		{
			if (e.cancelable) e.preventDefault();
			o = e.target;
		}
		else
		{
			e.cancelBubble = true;
			o = e.srcElement;
		}
		while(o && '' == o.title) o = o.parentNode;
		if (o) alert(o.title);
	}
}
