#!/bin/bash

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
SED=s/$/.$DOMAIN/

passive() {
	amass enum -passive -src -o $DOMAIN/out-amass-$DOMAIN.txt -aw $WORDLIST -bl $BLACKLIST -d $DOMAIN
	echo "[AMASS DONE]"
	cat $DOMAIN/out-amass-$DOMAIN.txt | cut -d']' -f 2 | awk '{print $1}' | sort -u > $DOMAIN/hosts-amass-$DOMAIN.txt
	for i in $(echo $DOMAIN | tr "," "\n")
	do
		ldns-walk $i | awk '{print $1}' >> $DOMAIN/hosts-ldnswalk-$DOMAIN.txt
	done
	echo "[APPENDING WORDLIST TO DOMAIN FOR BRUTE FORCE]"
	for i in $(echo $DOMAIN | tr "," "\n")
	do
	sed s/$/.$i/ $WORDLIST >> $DOMAIN/hosts-wordlist-$DOMAIN.txt	
	done
	echo "[DONE]"
}

active() {
	amass enum -active -brute -src -o $DOMAIN/out-amass-$DOMAIN.txt -aw $WORDLIST -bl $BLACKLIST -d $DOMAIN
	echo "[AMASS DONE]"
	cat $DOMAIN/out-amass-$DOMAIN.txt | cut -d']' -f 2 | awk '{print $1}' | sort -u > $DOMAIN/hosts-amass-$DOMAIN.txt
	sed $SED $WORDLIST > $DOMAIN/hosts-wordlist-$DOMAIN.txt	
}

all() {
	cat $DOMAIN/hosts-amass-$DOMAIN.txt $DOMAIN/hosts-wordlist-$DOMAIN.txt $DOMAIN/hosts-ldnswalk-$DOMAIN.txt > $DOMAIN/hosts-all-$DOMAIN.txt
	if [ -n "$5"]; then
		cat $5 >> $DOMAIN/hosts-all-$DOMAIN.txt
		cat $DOMAIN/hosts-all-$DOMAIN.txt | sort -u > $DOMAIN/hosts-all-$DOMAIN.txt
	fi
	massdns --root -r resolvers.txt -t A -o S -w $DOMAIN/massdns-$DOMAIN.out $DOMAIN/hosts-all-$DOMAIN.txt
	#altdns -i subdomains.txt -o $DOMAIN-altdns.out -w words.txt -r -s results_output.txt
	cat $DOMAIN/massdns-$DOMAIN.out | awk '{print $3}' | sort -u | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > $DOMAIN/ips-online-$DOMAIN.txt
	masscan -iL $DOMAIN/ips-online-$DOMAIN.txt --rate 10000000 -p1-65535 --open -oX $DOMAIN/masscan-$DOMAIN.xml
	open_ports=$(cat $DOMAIN/masscan-$DOMAIN.xml | grep portid | cut -d "\"" -f 10 | sort -n | uniq | paste -sd,)
	echo $open_ports > $DOMAIN/open-ports-$DOMAIN.txt
	cat $DOMAIN/masscan-$DOMAIN.xml | grep portid | cut -d "\"" -f 4 | sort -V | uniq > $DOMAIN/nmap_targets-$DOMAIN.tmp
	nmap -Pn -sC -sV -p $(cat $DOMAIN/open-ports-$DOMAIN.txt) -iL $DOMAIN/nmap_targets-$DOMAIN.tmp -oA $DOMAIN/nmap_results-$DOMAIN
	cat $DOMAIN/nmap_results-$DOMAIN.xml aquatone -scan-timeout 3000 -nmap -out $DOMAIN/aquatone/ 
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
massdns)
	passive
	all
	;;
esac



