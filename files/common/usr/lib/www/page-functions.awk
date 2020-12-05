function getnode(ip)
{
        split(ip,a,".");
        f1=a[3]*255;f2=a[4]-1;
        return f1+f2;
}
function color_interface(ifname)
{
 ifcolor="#000000"
 if ( ifname ~ /tbb_wg.*/)	{ifcolor="#328f4a";}
 if ( ifname ~ /tbb_fastd/)	{ifcolor="#328f4a";}
 if ( ifname ~ /br-mesh.*/)	{ifcolor="#009c08";}
 if ( ifname ~ /mesh-adhoc/)	{ifcolor="#5030a1";}
 if ( ifname ~ /mesh-802.*/)	{ifcolor="#a13067";}
 return "<div style=\"color:"ifcolor";\">"ifname"</div>";
}

