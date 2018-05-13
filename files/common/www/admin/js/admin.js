var timer_dhcp=null;
var timer_wlan=null;
var timer_register=null;
var lock_dhcp=0
var lock_wlan=0
var lock_register=0
var lock_geoloc=0


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
	if(timer_wlan=="undefined"||timer_wlan==null)timer_wlan = window.setInterval("ajax_wlan()", 5000);
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
function geoloc_callback(data)
{
	try {
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
	var request = $.ajax({url:"/admin/ajax-geoloc.cgi", dataType:"json", dummy:t});
	request.done(geoloc_callback)
	lock_geoloc=0;
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

