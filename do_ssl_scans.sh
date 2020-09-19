#!/bin/bash

help() { 
	echo -e "Usage:\n ./do_ssl_scans.sh MODE (--all, --sslscan, --testssl)\n\nneeds gnmap output in pwd to run\n\noutput in sslscan/ and testssl/ dirs" 
} 

if [ $# -ne 1 ]; then 
	help
	exit 1
fi 

MODE=$1
#proper path for tools here
TESTSSL=testssl
SSLSCAN=sslscan

GNMAP=$(find . -maxdepth 1 -iname "*.gnmap")
if [[ -z "$GNMAP" ]]; then
 echo "[-] No gnmap files, exiting"
 exit 2
fi


run_sslscan() {
    if [ ! -d $(pwd)/sslscan ]; then
        mkdir sslscan
    fi
    for ssl in $(pwd)/*.ssl; do
        cat $ssl | while read line || [[ -n $line ]];
        do
                $SSLSCAN --no-colour $line > sslscan/$line.sslcan
                cat sslscan/$line.sslcan | sed -n '/Supported Server Cipher(s):$/,/Server Key Exchange Group(s):$/p' | sed -e '1d' -e '$d' | head -n -1 | awk '{print $2, $5}' > sslscan/$line.report.sslscan.out
                echo "[+] Done sslscan for $line"
        done
    done 
}

run_testssl() {
    if [ ! -d $(pwd)/testssl ]; then
        mkdir testssl
    fi
    for ssl in $(pwd)/*.ssl; do
        cat $ssl | while read line || [[ -n $line ]];
        do
                $TESTSSL --full --logfile testssl/$line.testssl $line 
                echo "[+] Done testssl.sh for $line"
        done
    done 
}

while getopts ":h" option; do
   case $option in
      h) 
         help
         exit;;  
   esac
done

for gnmap in $(pwd)/*.gnmap; do
    cat $gnmap | awk '{for(i=1;i<=NF;i++){if ($i ~ /ssl/){print $2":"$i}}}' | awk -F "/" '{print $1}' > $(basename $gnmap).ssl
done

case "$MODE" in
--all)
	run_sslscan
    run_testssl
	break;;
--sslscan)
	run_sslscan
	break;;
--testssl)
	run_testssl
	break;;
*) 
    echo "Error: Invalid option"
    exit;;    		
esac
