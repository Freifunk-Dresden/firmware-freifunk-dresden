// Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
// GNU General Public License Version 3

var timer_dhcp=null;
var timer_wlan=null;
var timer_register=null;
var lock_dhcp=0
var lock_wlan=0
var lock_register=0
var lock_geoloc=0
var lock_regwg=0
var lock_swupdate=0


function ajax_dhcp(data)
{
	if(lock_dhcp)return;
	lock_dhcp=1;
	t=Math.random();
	$("#ajax_dhcp").load("/admin/ajax-dhcp.cgi", {dummy:t});
	if(timer_dhcp=="undefined"||timer_dhcp==null)timer_dhcp = window.setInterval("ajax_dhcp()", 3000);
	lock_dhcp=0;
}
function ajax_wlan(data)
{
	if(lock_wlan)return;
	lock_wlan=1;
	t=Math.random();
	$("#ajax_wlan").load("/admin/ajax-wlan.cgi", {dummy:t});
	if(timer_wlan=="undefined"||timer_wlan==null)timer_wlan = window.setInterval("ajax_wlan()", 10000);
	lock_wlan=0;
}
function ajax_register(data)
{
	if(lock_register)return;
	lock_register=1;
	t=Math.random();
	$("#ajax_register").load("/admin/ajax-register.cgi", {dummy:t});
	if(timer_register=="undefined"||timer_register==null)timer_register = window.setInterval("ajax_register()", 5000);
	lock_register=0;
}

function onMarkerMove(event)
{
	lat=event.target.getLatLng().lat.toFixed(5)
	lng=event.target.getLatLng().lng.toFixed(5)
	$("#geoloc_lat").val(lat);
	$("#geoloc_lng").val(lng);
//	var icon = L.icon({iconUrl:"https://leafletjs.com/examples/custom-icons/leaf-red.png", iconSize: [20, 20], iconAnchor: [10, 20]});
//	marker.setIcon(icon);
	marker.bindPopup('Neue Koordinaten:<br/> <div style="color: #ff0000;">' + lat + ',' + lng + '</div>').openPopup()
}

function onMapClick(event)
{
        lat=event.latlng.lat.toFixed(5)
        lng=event.latlng.lng.toFixed(5)
        $("#geoloc_lat").val(lat);
        $("#geoloc_lng").val(lng);
        marker.setLatLng([lat, lng]);
//      var icon = L.icon({iconUrl:"https://leafletjs.com/examples/custom-icons/l
//      marker.setIcon(icon);
	marker.bindPopup('Neue Koordinaten:<br/> <div style="color: #ff0000;">' + lat + ',' + lng + '</div>').openPopup()
}

function geoloc_callback(data)
{
	try {
		$("#progress").html("");
		lat=data.location.lat.toFixed(5)
		lng=data.location.lng.toFixed(5)
		$("#geoloc_lat").val(lat);
		$("#geoloc_lng").val(lng);
		marker.bindPopup('Neue Koordinaten:<br/> <div style="color: #ff0000;">' + lat + ',' + lng + '</div>').openPopup()
		marker.setLatLng([lat, lng]);
	} catch (e) {}
}
function ajax_geoloc(data)
{
	if(lock_geoloc)return;
	lock_geoloc=1;
	t=Math.random();
	$("#progress").html("Lade Informationen....");
	var request = $.ajax({url:"/admin/ajax-geoloc.cgi", dataType:"json", dummy:t});
	request.done(geoloc_callback)
	lock_geoloc=0;
}

function regwg_callback(data)
{
	try {
		if(data.status=="RequestAccepted" || data.status=="RequestAlreadyRegistered")
		{
			$("#wgcheck_key").val(data.server.key);
			$("#wgcheck_node").val(data.server.node);
			$("#wgcheck_port").val(data.server.port);
		}
		else
		{
			if(data.status=="Restricted") $("#wgcheck_key").val("Kein Zugang");
			else $("#wgcheck_key").val("Fehler");
		}
	} catch (e) {}
}
function ajax_regwg(host)
{
	if(lock_regwg)return;
	if(host == "")return;
	lock_regwg=1;
	t=Math.random();
	$("#wgcheck_key").val("Lade Informationen....");
	var request = $.ajax({url:"/admin/ajax-regwg.cgi", dataType:"json",method:"POST",data:{host: host}, dummy:t});
	request.done(regwg_callback)
	lock_regwg=0;
}

function swupdate_callback(data)
{
	try {
		$("#progress").html("");
		$("#firmware_release_version").val(data.firmware_release_version);
		$("#firmware_release_url").val(data.firmware_release_url);
		$("#firmware_release_url_info").val(data.firmware_release_url);
		$("#firmware_release_md5sum").val(data.firmware_release_md5sum);

		$("#firmware_testing_version").val(data.firmware_testing_version);
		$("#firmware_testing_url").val(data.firmware_testing_url);
		$("#firmware_testing_url_info").val(data.firmware_testing_url);
		$("#firmware_testing_md5sum").val(data.firmware_testing_md5sum);
		$("#firmware_testing_filename").val(data.firmware_testing_filename);

		expected_filename = data.firmware_release_filename;
		if(expected_filename=="")
		{ expected_filename = data.firmware_testing_filename;}
		$("#firmware_expected_filename").html(expected_filename);

		comment = data.firmware_release_comment;
		if(comment=="")
		{ comment = data.firmware_testing_comment;}
		$("#firmware_comment").html(comment);

		// enable buttons
		$("#ajax_swupdate_latest").val("Download: 'latest'-Version " + (data.firmware_release_version));
		if(data.firmware_release_enable_button == "1")
		{	$("#ajax_swupdate_latest").prop("disabled", false); }
		else
		{	$("#ajax_swupdate_latest").prop("disabled", true); }

		$("#ajax_swupdate_testing").val("Download: 'testing'-Version " + (data.firmware_testing_version));
		if(data.firmware_testing_enable_button == "1")
		{	$("#ajax_swupdate_testing").prop("disabled", false); }
		else
		{	$("#ajax_swupdate_testing").prop("disabled", true); }

	} catch (e) {}
}
function ajax_swupdate(data)
{
	if(lock_swupdate)return;
	lock_swupdate=1;
	t=Math.random();
	$("#progress").html("Lade Informationen....");
	var request = $.ajax({url:"/admin/ajax-swupdate.cgi", dataType:"json", dummy:t});
	request.done(swupdate_callback)
	lock_swupdate=0;
}


function checknumber (v)
{
	var re = new RegExp("^[0-9]+$");
	return ! re.test(v);
}

function fold(id)
{
	obj = document.getElementById(id);
	obj.style.display = ('block'!=obj.style.display?'block':'none');
	return false;
}

function isNumberKey(evt)
{
 var charCode = (evt.which) ? evt.which : event.keyCode
 if (charCode > 31 && (charCode < 48 || charCode > 57)) return false;
 return true;
}

function isWifiKey(evt)
{
 var charCode = (evt.which) ? evt.which : event.keyCode
 if (charCode < 32 || charCode > 127) return false;
 return true;
}
function checkWifiKey(key)
{
 for(var i=0; i<key.length; i++)
 {
  charCode = key.charCodeAt(i);
  if (charCode < 32 || charCode > 127) return false;
 }
 return true;
}
