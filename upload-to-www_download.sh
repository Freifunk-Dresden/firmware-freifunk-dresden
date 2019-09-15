#!/bin/bash

#get path of this script (upload dir) and change to it
cd $PWD/${0%/*}

if [ -z "$1" ]; then
	echo "Uploads all files in .files"
	echo " use \"$0 <all | json> [upload]\""
	echo "     all - uploads all files"
	echo "     json- uploads only download.json"
	echo ""
	exit 1
fi

echo "Steps:"
echo " 1. rsync files/* to download server"
echo " 2. dann manuell das verzeichniss verlinken"
echo " 3. dann manuell das altes löschen oder verschieben auf server"
echo ""


output_dir="$PWD/final_output"

#the complete output dir is copied to vserver. directories that are deleted are also
#deleted on server

echo "Please login as stephan!"

if [ "$2" = "upload" ]; then
	dryrun=""
else
	dryrun="--dry-run"
fi

if true; then
	HOST="download.freifunk-dresden.de"
	PORT="2202"
else
	HOST="download.lxc"
	PORT="22"
fi

case "$1" in
	"all")
		rsync $dryrun -avz --info=all1 -e "ssh -p $PORT" --delete -EH --progress $output_dir/* stephan@$HOST:/var/www/files/uploaded/
		;;
	"json")
		for d in $(ls -1 $output_dir)
		do
			rsync $dryrun -avz --info=all1 -e "ssh -p $PORT" --delete -EH --progress $output_dir/$d/download.json $output_dir/$d/download.json.js stephan@$HOST:/var/www/files/uploaded/$d/
		done
		;;
	*)	
		echo "invalid arguments"
		;;
esac

