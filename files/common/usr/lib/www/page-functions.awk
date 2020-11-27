function getnode(ip)
{
        split(ip,a,".");
        f1=a[3]*255;f2=a[4]-1;
        return f1+f2;
}
function color_interface(ifname)
{
 ifcolor="#000000"
 if ( ifname ~ /tbb_wg.*/)	{ifcolor="#d1a90f";}
 if ( ifname ~ /tbb_fastd/)	{ifcolor="#807754";}
 if ( ifname ~ /br-mesh.*/)	{ifcolor="#278f2e";}
 if ( ifname ~ /mesh-adhoc/)	{ifcolor="#8e6aad";}
 if ( ifname ~ /mesh-802.*/)	{ifcolor="#90839c";}
 return "<div style=\"color:"ifcolor";\">"ifname"</div>";
}

