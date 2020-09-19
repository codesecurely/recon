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

#INTERNAL VARIABLES
WORDLIST_DIR="/home/recon/tools/wordlists"

run_large_amass() {
amass enum -passive -o large/amass-out.txt -aw $WORDLIST -bl $BLACKLIST -df $DOMAIN -config config.ini
}

run_amass() {
	echo "AMASS"
	if [ -s "$DOMAIN/hosts-amass-$DOMAIN.txt" ]; then
		return
	fi
	echo "[STARTING AMASS]"
	amass enum -active -brute -src -o $DOMAIN/out-amass-$DOMAIN.txt -aw $WORDLIST -bl $BLACKLIST -d $DOMAIN -config config.ini
	echo "[AMASS DONE]"
	cat $DOMAIN/out-amass-$DOMAIN.txt | cut -d']' -f 2 | awk '{print $1}' | sort -u > $DOMAIN/hosts-amass-$DOMAIN.txt
	sed $SED $WORDLIST > $DOMAIN/hosts-wordlist-$DOMAIN.txt
	cat $DOMAIN/hosts-amass-$DOMAIN.txt $DOMAIN/hosts-wordlist-$DOMAIN.txt > $DOMAIN/hosts-all-$DOMAIN.txt
	if [ -n "$EXISTING_LIST" ]; then
		cat $EXISTING_LIST >> $DOMAIN/hosts-all-$DOMAIN.txt
		cat $DOMAIN/hosts-all-$DOMAIN.txt | sort -u > $DOMAIN/hosts-all-$DOMAIN.txt
	fi	

}

run_ldns_walk() {
	if [ -s "$DOMAIN/hosts-ldnswalk-$DOMAIN.txt" ]; then
		return
	fi
	
	for i in $(echo $DOMAIN | tr "," "\n")
	do
		ldns-walk $i | awk '{print $1}' >> $DOMAIN/hosts-ldnswalk-$DOMAIN.txt
	done
	echo "[APPENDING WORDLIST TO DOMAIN FOR BRUTE FORCE]"
	for i in $(echo $DOMAIN | tr "," "\n")
	do
	sed s/$/.$i/ $WORDLIST >> $DOMAIN/hosts-wordlist-$DOMAIN.txt	
	done
	echo "[LDNS-WALK DONE]"
	cat $DOMAIN/hosts-ldnswalk-$DOMAIN.txt >> $DOMAIN/hosts-all-$DOMAIN.txt

}

run_massdns() {
	if [ -s "$DOMAIN/ips-online-$DOMAIN.txt" ]; then
		return
	fi
	massdns --root -r resolvers.txt -t A -o S -w $DOMAIN/massdns-$DOMAIN.out $DOMAIN/hosts-all-$DOMAIN.txt
	cat $DOMAIN/massdns-$DOMAIN.out | awk '{print $3}' | sort -u | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > $DOMAIN/ips-online-$DOMAIN.txt
}

run_masscan() {
	if [ -s "$DOMAIN/nmap_targets-$DOMAIN.tmp" ]; then
		return
	fi
	masscan -iL $DOMAIN/ips-online-$DOMAIN.txt --rate 1000000 -p1-65535 --open -oX $DOMAIN/masscan-$DOMAIN.xml
	open_ports=$(cat $DOMAIN/masscan-$DOMAIN.xml | grep portid | cut -d "\"" -f 10 | sort -n | uniq | paste -sd,)
	echo $open_ports > $DOMAIN/open-ports-$DOMAIN.txt
	cat $DOMAIN/masscan-$DOMAIN.xml | grep portid | cut -d "\"" -f 4 | sort -V | uniq > $DOMAIN/nmap_targets-$DOMAIN.tmp
}

run_httprobe() {
	if [ ! -s "$DOMAIN/massdns-$DOMAIN.out" ]; then
		echo "no file $DOMAIN/massdns-$DOMAIN.out, exiting"
		return
	fi

	if [ -s "$DOMAIN/webservers-live-domains-$DOMAIN.txt" ]; then
		echo "httprobe already done, skipping"
		return
	fi

	#sort by third unique column (IP), then print first column (domain)
	cat $DOMAIN/massdns-$DOMAIN.out | sort -u -t ' ' -k 3,3 | awk '{print $1}' | sed -r 's/\.$//' | httprobe > $DOMAIN/webservers-live-domains-$DOMAIN.txt
}

run_gospider() {
	if [ ! -s "$DOMAIN/webservers-live-domains-$DOMAIN.txt" ]; then
		return
	fi	
	gospider -S $DOMAIN/webservers-live-domains-$DOMAIN.txt -t 10 -q > $DOMAIN/spidered-content-$DOMAIN.txt
	gospider -S $DOMAIN/gobuster-endpoints-$DOMAIN.txt -t 10 -q >> $DOMAIN/spidered-content-$DOMAIN.txt
}

run_nmap() {
	if [ -s "$DOMAIN/nmap_results-$DOMAIN.xml" ]; then
		return
	fi
	open_ports=$(cat $DOMAIN/masscan-$DOMAIN.xml | grep portid | cut -d "\"" -f 10 | sort -n | uniq | wc -l)
	
	if [ $open_ports -le 100 ]; then
		nmap -Pn -sC -sV -p $(cat $DOMAIN/open-ports-$DOMAIN.txt) -iL $DOMAIN/nmap_targets-$DOMAIN.tmp -oA $DOMAIN/nmap_results-$DOMAIN
	else
		nmap -Pn -sC -sV -p- -v -iL $DOMAIN/nmap_targets-$DOMAIN.tmp -oA $DOMAIN/nmap_results-$DOMAIN
	fi
}

run_aquatone() {
	if [ -d "$DOMAIN/aquatone" ]; then
		return
	fi
	cat $DOMAIN/nmap_results-$DOMAIN.xml | aquatone -scan-timeout 900 -nmap -out $DOMAIN/aquatone/	
}

run_gobuster_recurse() {
	if [ ! -e "$DOMAIN/webservers-live-domains-$DOMAIN.txt" ] || [ -s "$DOMAIN/gobuster-endpoints-$DOMAIN.txt" ]; then
		return
	fi
	#[[ -n $line ]] so it doesn't skip last line if there's no empty newline
	cat $DOMAIN/webservers-live-domains-$DOMAIN.txt | while read line || [[ -n $line ]];
	do
		$(pwd)/gobuster_recurse.sh $line "$WORDLIST_DIR/common.txt" 2 $DOMAIN/gobuster-endpoints-$DOMAIN.txt
	done 
}

run_gobuster_vhosts() {
	if [ ! -e "$DOMAIN/massdns-$DOMAIN.out" ] || [ -s "$DOMAIN/gobuster-vhosts-all.txt" ]; then
		return
	fi
	#[[ -n $line ]] so it doesn't skip last line if there's no empty newline
	cat $DOMAIN/massdns-$DOMAIN.out | awk '{print $1}' | sort -u | sed 's/.$//' | while read line || [[ -n $line ]];
	do
		gobuster vhost -u $line -w "$WORDLIST_DIR/common-vhosts.txt" -o $DOMAIN/gobuster-vhosts.tmp
		cat $DOMAIN/gobuster-vhosts.tmp >> $DOMAIN/gobuster-vhosts-all.txt	
	done
	for i in $(echo $DOMAIN | tr "," "\n")
	do
		gobuster vhost -u $i -w "$WORDLIST_DIR/common-vhosts.txt" -o $DOMAIN/gobuster-vhosts.tmp
		cat $DOMAIN/gobuster-vhosts.tmp >> $DOMAIN/gobuster-vhosts-all.txt		
	done
	rm $DOMAIN/gobuster-vhosts.tmp  
}

run_gobuster_files() {
	for i in $(echo $DOMAIN | tr "," "\n")
	do
		gobuster dir -s 200,204 -u $i -w "$WORDLIST_DIR/raft-large-files-lowercase.txt" -t 10 -o $DOMAIN/gobuster-files.tmp
	
	done
	if [ ! -e "$DOMAIN/gobuster-endpoints-$DOMAIN.txt" ]; then
		return
	fi
	cat $DOMAIN/gobuster-endpoints-$DOMAIN.txt | sort -u | while read line || [[ -n $line ]];
	do
		gobuster dir -u $line -w "$WORDLIST_DIR/raft-large-files-lowercase.txt" -t 10 -o $DOMAIN/gobuster-files-$DOMAIN.txt 
	done
	cat $DOMAIN/gobuster-files.tmp >> $DOMAIN/gobuster-files-$DOMAIN.txt
	rm $DOMAIN/gobuster-files.tmp 	 
}

run_all() {
	run_amass
	run_massdns
	run_masscan
	run_nmap
	run_aquatone
	run_gobuster_recurse
	run_gobuster_files
	run_gobuster_vhosts
}

run_http() {
	run_amass
	run_massdns
	run_httprobe
	run_gobuster_recurse
	run_gospider
}
mkdir $DOMAIN

case "$MODE" in
all)
	run_all
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



