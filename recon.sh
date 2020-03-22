#!/bin/bash

display_usage() { 
	echo -e "Usage:\n ./recon.sh DOMAIN WORDLIST BLACKLIST (pass example.com if none) MODE (active, passive, all) \n\n DOMAIN - comma separated list of domains, WORDLIST - wordlist to be used, BLACKLIST - comma separated list of domains out of scope" 
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
SED=s/$/.$DOMAIN/

passive() {
	amass enum -passive -src -o $DOMAIN/$DOMAIN-out-amass.txt -aw $WORDLIST -bl $BLACKLIST -d $DOMAIN
	echo "[AMASS DONE]"
	cat $DOMAIN/$DOMAIN-out-amass.txt | cut -d']' -f 2 | awk '{print $1}' | sort -u > $DOMAIN/$DOMAIN-hosts-amass.txt
	sed $SED $WORDLIST > $DOMAIN/$DOMAIN-hosts-wordlist.txt	
}

active() {
	amass enum -active -brute -src -o $DOMAIN/$DOMAIN-out-amass.txt -aw $WORDLIST -bl $BLACKLIST -d $DOMAIN
	echo "[AMASS DONE]"
	cat $DOMAIN/$DOMAIN-out-amass.txt | cut -d']' -f 2 | awk '{print $1}' | sort -u > $DOMAIN/$DOMAIN-hosts-amass.txt
	sed $SED $WORDLIST > $DOMAIN/$DOMAIN-hosts-wordlist.txt	
}

all() {
	cat $DOMAIN/$DOMAIN-hosts-amass.txt $DOMAIN/$DOMAIN-hosts-wordlist.txt > $DOMAIN/$DOMAIN-hosts-all.txt
	massdns --root -r resolvers.txt -t A -o S -w $DOMAIN/$DOMAIN-massdns.out $DOMAIN/$DOMAIN-hosts-all.txt
	#altdns -i subdomains.txt -o $DOMAIN-altdns.out -w words.txt -r -s results_output.txt
	cat $DOMAIN/$DOMAIN-massdns.out | awk '{print $3}' | sort -u | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > $DOMAIN/$DOMAIN-ips-online.txt
	masscan -iL $DOMAIN/$DOMAIN-ips-online.txt --rate 1000 -p1-65535 --open -oX $DOMAIN/$DOMAIN-masscan.xml
	open_ports=$(cat $DOMAIN/$DOMAIN-masscan.xml | grep portid | cut -d "\"" -f 10 | sort -n | uniq | paste -sd,)
	echo open_ports > $DOMAIN/$DOMAIN-open-ports.txt
	cat $DOMAIN/$DOMAIN-masscan.xml | grep portid | cut -d "\"" -f 4 | sort -V | uniq > $DOMAIN/$DOMAIN-nmap_targets.tmp
}
mkdir $DOMAIN

case "$4" in
passive)
	passive
	;;
active)
	active
	;;
all)
	active
	all
	;;
esac



