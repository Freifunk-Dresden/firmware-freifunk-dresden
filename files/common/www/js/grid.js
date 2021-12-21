// Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
// GNU General Public License Version 3

//var b = new GridField("progress", "myProgress", 10, 50, 10, 5, "#aaaaaa", "#0000ff");
//b.setGridValue( 5 );

//create object via constructor function
function GridField( parent, id, nBars, nFields, cellWidth, cellHeight, colorClear, colorSelected)
{
	this.parent = parent;
	this.id = id;
	this.nBars = nBars;
	this.nFields = nFields;
	this.cellWidth = cellWidth;
	this.cellHeight = cellHeight;
 	this.colorClear = colorClear;
	this.colorSelected = colorSelected;
	this.drawGrid = function()
	{

		var div=document.getElementById(this.parent);
		var table=document.createElement("table");

		div.appendChild(table);

		for(var bar = 0; bar < this.nBars; bar++)
		{
			var row=document.createElement("tr");
			row.id="progressBar_" + bar;
			table.appendChild(row);

			for(var cell = 0; cell < this.nFields; cell++)
			{
				var c=document.createElement("td");
				c.id="progessBar_" + bar + "_cell_" + cell;
				c.style="background: " + colorClear + "; width: " + this.cellWidth + "px; height:"+ this.cellHeight +"px";
				row.appendChild(c);
			}
		}
	};
	this.setGridCell = function( bar, cell, flag)
	{
		var cell = document.getElementById("progessBar_" + bar + "_cell_" + cell);
		var color = flag ? this.colorSelected : this.colorClear;
		cell.style="background: " + color + "; width: " + this.cellWidth + "px; height:"+ this.cellHeight +"px";
	};
	this.setGridRow = function( bar, flag)
	{
		for(var cell = 0; cell < this.nFields; cell++)
		{
			this.setGridCell( bar, cell, flag);
		}
	};
	this.setGrid = function( flag)
	{
		for(var bar = 0; bar < this.nBars; bar++)
		{
			this.setGridRow( bar, flag);
		}
	};
	this.setGridRandom = function( count )
	{
		if( count === undefined )
			count = this.nFields * this.nBars / 2;

		for( var i = 0; i < count; i++)
		{
			var x = Math.floor(Math.random() * this.nFields);
			var y = Math.floor(Math.random() * this.nBars);
			var flag = Math.floor(Math.random() + 0.5);
			this.setGridCell(y,x,flag);
		}
	};
	this.setGridValue = function( value )
	{
		if( value > this.nFields * this.nBars  )
			value = this.nFields * this.nBars;
		if( value < 0 )
			value = 0;

		//get full bars
		var nb = Math.floor(value / this.nFields );
		var nf = value % this.nFields;

		// full rows
		for(var b = 0; b < this.nBars; b++)
		{
			if(b < nb)
				this.setGridRow(b, true);
			else
				this.setGridRow(b, false);
		}

		// partial row
		for(var f = 0; f < nf; f++)
		{
			this.setGridCell(nb, f, true);
		}
	};
	this.autoCounter = function(intervalMs, maxValue)
	{
		var count=0;
		var timer= setInterval( function( myThis )
		{
			count++;
			if(count > maxValue)
				clearInterval(timer);
			else
				myThis.setGridValue(count);
		}, intervalMs, this); // pass this to timer function
	};

	//create and display bars
	this.drawGrid();
}
