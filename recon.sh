#!/bin/bash

set -x

display_usage() { 
	echo -e "Usage:\n ./recon.sh DOMAIN WORDLIST BLACKLIST (pass example.com if none) MODE (active, passive, all) EXISTING_LIST \n\n DOMAIN - comma separated list of domains, WORDLIST - wordlist to be used, BLACKLIST - comma separated list of domains out of scope" 
	} 


# if less than two arguments supplied, display usage 
	if [  $# -le 3 ] 
	then 
		display_usage
		exit 1
	fi 
 
# check whether user had supplied -h or --help . If yes display usage 
	if [[ ( $# == "--help") ||  $# == "-h" ]] 
	then 
		display_usage
		exit 0
	fi

DOMAIN=$1
WORDLIST=$2
BLACKLIST=$3
MODE=$4
EXISTING_LIST=$5

SED=s/$/.$DOMAIN/

#array for referencing input domains
DOMAINS=($(echo $DOMAIN | tr ',' ' '))

#INTERNAL VARIABLES
WORDLIST_DIR="/home/recon/tools/wordlists"

#download latest resolvers
wget https://raw.githubusercontent.com/janmasarik/resolvers/master/resolvers.txt -O resolvers.txt

run_large_amass() {
	amass enum -passive -o large/amass-out.txt -aw $WORDLIST -bl $BLACKLIST -df $DOMAIN -config config.ini
}

run_amass() {
	echo "AMASS"
	if [ -s "$DOMAIN/hosts-amass.txt" ]; then
		return
	fi
	echo "[STARTING AMASS]"
	amass enum -active -brute -src -o $DOMAIN/out-amass.txt -rf resolvers.txt -aw $WORDLIST -bl $BLACKLIST -d $DOMAIN -config config.ini
	echo "[AMASS DONE]"
	cat $DOMAIN/out-amass.txt | cut -d']' -f 2 | awk '{print $1}' | sort -u > $DOMAIN/hosts-amass.txt
	sed $SED $WORDLIST > $DOMAIN/hosts-wordlist.txt
	cat $DOMAIN/hosts-amass.txt $DOMAIN/hosts-wordlist.txt > $DOMAIN/hosts-all.txt
	if [ -n "$EXISTING_LIST" ]; then
		cat $EXISTING_LIST >> $DOMAIN/hosts-all.txt
		cat $DOMAIN/hosts-all.txt | sort -u > $DOMAIN/hosts-all.txt
	fi	

}

run_ldns_walk() {
	if [ -s "$DOMAIN/hosts-ldnswalk.txt" ]; then
		return
	fi
	
	for i in $(echo $DOMAIN | tr "," "\n")
	do
		ldns-walk $i | awk '{print $1}' >> $DOMAIN/hosts-ldnswalk.txt
	done
	echo "[APPENDING WORDLIST TO DOMAIN FOR BRUTE FORCE]"
	for i in $(echo $DOMAIN | tr "," "\n")
	do
	sed s/$/.$i/ $WORDLIST >> $DOMAIN/hosts-wordlist.txt	
	done
	echo "[LDNS-WALK DONE]"
	cat $DOMAIN/hosts-ldnswalk.txt >> $DOMAIN/hosts-all.txt

}

run_massdns() {
	if [ -s "$DOMAIN/ips-online.txt" ]; then
		return
	fi
	massdns --root -q -r resolvers.txt -t A -o S -w $DOMAIN/massdns.txt $DOMAIN/hosts-all.txt
	cat $DOMAIN/massdns.txt | awk '{print $3}' | sort -u | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > $DOMAIN/ips-online.txt
}

run_masscan() {
	if [ $EUID != 0 ]; then
		echo "[!] This script must be launched as root."
		exit 1
	fi
	if [ -s "$DOMAIN/nmap_targets.tmp" ]; then
		return
	fi
	masscan -iL $DOMAIN/ips-online.txt --rate 1000000 -p1-65535 --open -oX $DOMAIN/masscan.xml
	open_ports=$(cat $DOMAIN/masscan.xml | grep portid | cut -d "\"" -f 10 | sort -n | uniq | paste -sd,)
	echo $open_ports > $DOMAIN/open-ports.txt
	cat $DOMAIN/masscan.xml | grep portid | cut -d "\"" -f 4 | sort -V | uniq > $DOMAIN/nmap_targets.tmp
}

run_httpx() {
	if [ ! -s "$DOMAIN/massdns.txt" ]; then
		echo "no file $DOMAIN/massdns.txt, exiting"
		return
	fi

	if [ -s "$DOMAIN/webservers-live.txt" ]; then
		echo "httpx already done, skipping"
		return
	fi

	#sort by third unique column (IP), then print first column (domain)
	cat $DOMAIN/massdns.txt | sort -u -t ' ' -k 3,3 | awk '{print $1}' | sed -r 's/\.$//' | httpx -ports 80,81,443,591,2082,2087,2095,2096,3000,8000,8001,8008,8080,8083,8443,8834,8888  > $DOMAIN/webservers-live.txt
}

run_gau() {
	for i in $(echo $DOMAIN | tr "," "\n")
	do
	gau -providers wayback,otx,commoncrawl $i | grep -v -E "(jpg|jpeg|gif|css|tif|tiff|png|ttf|woff|woff2|ico|svg)" >> $DOMAIN/spidered-content.tmp 
	done 
}

run_gospider() {
	if [ ! -s "$DOMAIN/webservers-live.txt" ]; then
		return
	fi
	#quiet, threads=2, concurrent=5, depth=3	
	gospider -S $DOMAIN/webservers-live.txt -q -t 2 -c 5 -d 3 --blacklist jpg,jpeg,gif,css,tif,tiff,png,ttf,woff,woff2,ico,svg > $DOMAIN/spidered-content.tmp
	if [ -s "$DOMAIN/gobuster-endpoints.txt" ]; then
		gospider -S $DOMAIN/gobuster-endpoints.txt -q -t 2 -c 5 -d 3 --blacklist jpg,jpeg,gif,css,tif,tiff,png,ttf,woff,woff2,ico,svg >> $DOMAIN/spidered-content.tmp
	fi
	run_gau
	cat $DOMAIN/spidered-content.tmp | grep -o -E "(([a-zA-Z][a-zA-Z0-9+-.]*\:\/\/)|mailto|data\:)([a-zA-Z0-9\.\&\/\?\:@\+-\_=#%;,])*" | sort -u | qsreplace -a > $DOMAIN/spidered-content.txt
}

run_nmap() {
	if [ $EUID != 0 ]; then
		echo "[!] This script must be launched as root."
		exit 1
	fi
	if [ -s "$DOMAIN/nmap_results.xml" ]; then
		return
	fi
	open_ports=$(cat $DOMAIN/masscan.xml | grep portid | cut -d "\"" -f 10 | sort -n | uniq | wc -l)
	
	if [ $open_ports -le 100 ]; then
		nmap -Pn -sC -sV -p $(cat $DOMAIN/open-ports.txt) --open -iL $DOMAIN/nmap_targets.tmp -oA $DOMAIN/nmap_results
	else
		nmap -Pn -sC -sV -p- -v --open -iL $DOMAIN/nmap_targets.tmp -oA $DOMAIN/nmap_results
	fi
}

run_aquatone() {
	if [ -d "$DOMAIN/aquatone" ]; then
		return
	fi
	cat $DOMAIN/nmap_results.xml | aquatone -scan-timeout 900 -nmap -out $DOMAIN/aquatone/	
}

run_gobuster_recurse() {
	LEVEL=$1
	if [ ! -e "$DOMAIN/webservers-live.txt" ] || [ -s "$DOMAIN/gobuster-endpoints.txt" ]; then
		return
	fi
	#[[ -n $line ]] so it doesn't skip last line if there's no empty newline
	cat $DOMAIN/webservers-live.txt | while read line || [[ -n $line ]];
	do
		$(pwd)/gobuster_recurse.sh $line "$WORDLIST_DIR/common.txt" $LEVEL $DOMAIN/gobuster-endpoints.txt
	done 
}

run_gobuster_vhosts() {
	if [ ! -e "$DOMAIN/webservers-live.txt" ] || [ -s "$DOMAIN/gobuster-vhosts-all.txt" ]; then
		return
	fi
	cat $DOMAIN/webservers-live.txt | while read line || [[ -n $line ]];
	do
		gobuster vhost -u $line -w "$WORDLIST_DIR/common-vhosts.txt" -o $DOMAIN/gobuster-vhosts.tmp
		cat $DOMAIN/gobuster-vhosts.tmp >> $DOMAIN/gobuster-vhosts-all.txt		
	done
	rm $DOMAIN/gobuster-vhosts.tmp  
}

run_gobuster_files() {
	cat $DOMAIN/webservers-live.txt | while read line || [[ -n $line ]];
	do
		gobuster dir -s 200,204 -u $line -w "$WORDLIST_DIR/raft-large-files.txt" -t 10 -o $DOMAIN/gobuster-files.tmp
		cat $DOMAIN/gobuster-files.tmp >> $DOMAIN/gobuster-files.txt
	done
	if [ -e "$DOMAIN/gobuster-endpoints.txt" ]; then
		cat $DOMAIN/gobuster-endpoints.txt | sort -u | while read line || [[ -n $line ]];
		do
			gobuster dir -u $line -w "$WORDLIST_DIR/raft-large-files.txt" -t 10 -o $DOMAIN/gobuster-files.tmp
			cat $DOMAIN/gobuster-files.tmp >> $DOMAIN/gobuster-files.txt 
		done
	fi
	cat $DOMAIN/gobuster-files.txt | sort -u > $DOMAIN/gobuster-files.txt
	rm $DOMAIN/gobuster-files.tmp
}

run_http() {
	run_httpx
	#run_gobuster_recurse 2
	#run_gobuster_files
	run_gospider
}

run_recon() {
	run_amass
	run_massdns
	run_masscan
	run_nmap
}

run_domain_harvest() {
	run_amass
	run_massdns
}
mkdir $DOMAIN

case "$MODE" in
harvest)
	run_domain_harvest
	;;
recon)
	run_recon
	;;
http)
	run_http
	;;
large)
	run_large_amass
	;;		
reset)
	rm -rf $DOMAIN/
	run_all
	;;
esac

# cleanup
rm resolvers.txt
chown -R recon:recon $DOMAIN/

