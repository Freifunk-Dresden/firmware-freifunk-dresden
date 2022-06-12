# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

function getnode(ip)
{
 split(ip,a,".");
 f1=a[3]*255;f2=a[4]-1;
 return f1+f2;
}
function color_interface(ifname)
{
 ifcolor="#000000"
 style=""
 if ( ifname ~ /tbb_wg.*/)	{ifcolor="#a23c1a";}
 if ( ifname ~ /tbb_fastd/)	{ifcolor="#a23c1a";}
 if ( ifname ~ /br-mesh.*/)	{ifcolor="#404c08";style="font-weight: bolder;";}
 if ( ifname ~ /mesh-adhoc/)	{ifcolor="#5030a1";}
 if ( ifname ~ /mesh..-802.*/)	{ifcolor="#417067";}
 return "<div style=\"color:"ifcolor";"style"\">"ifname"</div>";
}

# array must be indexed by number based on 0
function arraysort(array)
{
  # count
  len=0; for(i in array) {len=len+1}
  # bubble sort
  for(end=len-1; len > 1 && end>0;end--)
  {
    for(i=0; i<end;i++)
    {
      if(array[i]>array[i+1])
      {a=array[i+1];array[i+1]=array[i];array[i]=a;}
    }
  }
}
