#!/bin/bash

set -x

display_usage() { 
	echo -e "Usage:\n\n
	-t - single target as a domain name (example.com)\n
	-T - list of target domain names as a file\n
	-w - path to initial wordlist for domain enumeration\n
	-W - path to directory with helper wordlists\n
	-o - output directory (default: pwd/loot)\n
	-m - work mode (passive, harvest, recon, http)\n
	-e - existing list of known subdomains (only works with single target option)\n
	-b - black list for out of scope domains (comma-separated)\n
	-h - display this message"	

	} 

run_passive_amass() {
	amass enum -passive -o $WORKDIR/$DOMAIN/out-amass-passive.txt -aw $WORDLIST -bl $BLACKLIST -d $DOMAIN -config config.ini
}

run_amass() {
	echo "AMASS"
	# test if previous output exists
	if [ -s "$WORKDIR/$DOMAIN/hosts-amass.txt" ]; then
		mv "$WORKDIR/$DOMAIN/hosts-amass.txt" "$WORKDIR/$DOMAIN/hosts-amass.txt.$(date "+%Y-%m-%d")"
	fi
	echo "[STARTING AMASS]"
	amass enum -active -brute -src -o $WORKDIR/$DOMAIN/out-amass.txt -rf resolvers.txt -aw $WORDLIST -bl $BLACKLIST -d $DOMAIN -config config.ini
	echo "[AMASS DONE]"
	cat $WORKDIR/$DOMAIN/out-amass.txt | cut -d']' -f 2 | awk '{print $1}' | sort -u > $WORKDIR/$WORKDIR/$DOMAIN/hosts-all.txt
	if [ -n "$EXISTING_LIST" ]; then
		cat $EXISTING_LIST >> $WORKDIR/$DOMAIN/hosts-all.txt
		cat $WORKDIR/$DOMAIN/hosts-all.txt | sort -u > $WORKDIR/$DOMAIN/hosts-all.txt
	fi	

}

run_ldns_walk() {
	if [ -s "$WORKDIR/$DOMAIN/hosts-ldnswalk.txt" ]; then
		mv "$WORKDIR/$DOMAIN/hosts-ldnswalk.txt" "$WORKDIR/$DOMAIN/hosts-ldnswalk.txt.$(date "+%Y-%m-%d")"
	fi
	ldns-walk $DOMAIN | awk '{print $1}' >> $WORKDIR/$DOMAIN/hosts-ldnswalk.txt
	echo "[LDNS-WALK DONE]"
	cat $WORKDIR/$DOMAIN/hosts-all.txt $WORKDIR/$DOMAIN/hosts-ldnswalk.txt | sort -u > $WORKDIR/$DOMAIN/hosts-all.txt

}

run_massdns() {
	if [ -s "$WORKDIR/$DOMAIN/ips-online.txt" ]; then
		mv "$WORKDIR/$DOMAIN/ips-online.txt" "$WORKDIR/$DOMAIN/ips-online.txt.$(date "+%Y-%m-%d")"
	fi
	massdns --root -q -r resolvers.txt -t A -o S -w $WORKDIR/$DOMAIN/massdns.txt $WORKDIR/$DOMAIN/hosts-all.txt
	cat $WORKDIR/$DOMAIN/massdns.txt | awk '{print $3}' | sort -u | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > $WORKDIR/$DOMAIN/ips-online.txt
}

run_masscan() {
	if [ $EUID != 0 ]; then
		echo "[!] This script must be launched as root."
		exit 1
	fi
	if [ -s "$WORKDIR/$DOMAIN/nmap_targets.tmp" ]; then
		return
	fi
	masscan -iL $WORKDIR/$DOMAIN/ips-online.txt --rate 1000000 -p1-65535 --open -oX $WORKDIR/$DOMAIN/masscan.xml
	open_ports=$(cat $WORKDIR/$DOMAIN/masscan.xml | grep portid | cut -d "\"" -f 10 | sort -n | uniq | paste -sd,)
	echo $open_ports > $WORKDIR/$DOMAIN/open-ports.txt
	cat $WORKDIR/$DOMAIN/masscan.xml | grep portid | cut -d "\"" -f 4 | sort -V | uniq > $WORKDIR/$DOMAIN/nmap_targets.tmp
}

run_httpx() {
	if [ ! -s "$WORKDIR/$DOMAIN/massdns.txt" ]; then
		echo "no file $WORKDIR/$DOMAIN/massdns.txt, exiting"
		return
	fi

	if [ -s "$WORKDIR/$DOMAIN/webservers-live.txt" ]; then
		mv "$WORKDIR/$DOMAIN/webservers-live.txt" "$WORKDIR/$DOMAIN/webservers-live.txt.$(date "+%Y-%m-%d")"
	fi

	#sort by third unique column (IP), then print first column (domain)
	cat $WORKDIR/$DOMAIN/massdns.txt | sort -u -t ' ' -k 3,3 | awk '{print $1}' | sed -r 's/\.$//' | httpx -ports 80,81,443,591,2082,2087,2095,2096,3000,8000,8001,8008,8080,8083,8443,8834,8888  > $WORKDIR/$DOMAIN/webservers-live.txt
}

run_gau() {
	if [ ! -s "$WORKDIR/$DOMAIN/webservers-live.txt" ]; then
		return
	fi
	cat "$WORKDIR/$DOMAIN/webservers-live.txt" | gau --providers wayback,otx,commoncrawl --blacklist jpg,jpeg,gif,css,tif,tiff,png,ttf,woff,woff2,ico,svg >> $WORKDIR/$DOMAIN/spidered-content.tmp 
}

run_gospider() {
	if [ ! -s "$WORKDIR/$DOMAIN/webservers-live.txt" ]; then
		return
	fi
	#quiet, threads=2, concurrent=5, depth=3	
	gospider -S $WORKDIR/$DOMAIN/webservers-live.txt -q -t 2 -c 5 -d 3 --blacklist jpg,jpeg,gif,css,tif,tiff,png,ttf,woff,woff2,ico,svg > $WORKDIR/$DOMAIN/spidered-content.tmp
	if [ -s "$WORKDIR/$DOMAIN/gobuster-endpoints.txt" ]; then
		gospider -S $WORKDIR/$DOMAIN/gobuster-endpoints.txt -q -t 2 -c 5 -d 3 --blacklist jpg,jpeg,gif,css,tif,tiff,png,ttf,woff,woff2,ico,svg >> $WORKDIR/$DOMAIN/spidered-content.tmp
	fi
	run_gau
	cat $WORKDIR/$DOMAIN/spidered-content.tmp | grep -o -E "(([a-zA-Z][a-zA-Z0-9+-.]*\:\/\/)|mailto|data\:)([a-zA-Z0-9\.\&\/\?\:@\+-\_=#%;,])*" | sort -u | qsreplace -a > $WORKDIR/$DOMAIN/spidered-content.txt
}

run_nmap() {
	if [ $EUID != 0 ]; then
		echo "[!] This script must be launched as root."
		exit 1
	fi
	if [ -s "$WORKDIR/$DOMAIN/nmap_results.xml" ]; then
		return
	fi
	open_ports=$(cat $WORKDIR/$DOMAIN/masscan.xml | grep portid | cut -d "\"" -f 10 | sort -n | uniq | wc -l)
	
	if [ $open_ports -le 100 ]; then
		nmap -Pn -sC -sV -p $(cat $WORKDIR/$DOMAIN/open-ports.txt) --open -iL $WORKDIR/$DOMAIN/nmap_targets.tmp -oA $WORKDIR/$DOMAIN/nmap_results
	else
		nmap -Pn -sC -sV -p- -v --open -iL $WORKDIR/$DOMAIN/nmap_targets.tmp -oA $WORKDIR/$DOMAIN/nmap_results
	fi
}

run_aquatone() {
	if [ -d "$WORKDIR/$DOMAIN/aquatone" ]; then
		return
	fi
	cat $WORKDIR/$DOMAIN/nmap_results.xml | aquatone -scan-timeout 900 -nmap -out $WORKDIR/$DOMAIN/aquatone/	
}

run_gobuster_recurse() {
	LEVEL=$1
	if [ ! -e "$WORKDIR/$DOMAIN/webservers-live.txt" ] || [ -s "$WORKDIR/$DOMAIN/gobuster-endpoints.txt" ]; then
		return
	fi
	#[[ -n $line ]] so it doesn't skip last line if there's no empty newline
	cat $WORKDIR/$DOMAIN/webservers-live.txt | while read line || [[ -n $line ]];
	do
		$(pwd)/gobuster_recurse.sh $line "$WORDLIST_DIR/common.txt" $LEVEL $WORKDIR/$DOMAIN/gobuster-endpoints.txt
	done 
}

run_gobuster_vhosts() {
	if [ ! -e "$WORKDIR/$DOMAIN/webservers-live.txt" ] || [ -s "$WORKDIR/$DOMAIN/gobuster-vhosts-all.txt" ]; then
		return
	fi
	cat $WORKDIR/$DOMAIN/webservers-live.txt | while read line || [[ -n $line ]];
	do
		gobuster vhost -u $line -w "$WORDLIST_DIR/common-vhosts.txt" -o $WORKDIR/$DOMAIN/gobuster-vhosts.tmp
		cat $WORKDIR/$DOMAIN/gobuster-vhosts.tmp >> $WORKDIR/$DOMAIN/gobuster-vhosts-all.txt		
	done
	rm $WORKDIR/$DOMAIN/gobuster-vhosts.tmp  
}

run_gobuster_files() {
	cat $WORKDIR/$DOMAIN/webservers-live.txt | while read line || [[ -n $line ]];
	do
		gobuster dir -s 200,204 -u $line -w "$WORDLIST_DIR/raft-large-files.txt" -t 10 -o $WORKDIR/$DOMAIN/gobuster-files.tmp
		cat $WORKDIR/$DOMAIN/gobuster-files.tmp >> $WORKDIR/$DOMAIN/gobuster-files.txt
	done
	if [ -e "$WORKDIR/$DOMAIN/gobuster-endpoints.txt" ]; then
		cat $WORKDIR/$DOMAIN/gobuster-endpoints.txt | sort -u | while read line || [[ -n $line ]];
		do
			gobuster dir -u $line -w "$WORDLIST_DIR/raft-large-files.txt" -t 10 -o $WORKDIR/$DOMAIN/gobuster-files.tmp
			cat $WORKDIR/$DOMAIN/gobuster-files.tmp >> $WORKDIR/$DOMAIN/gobuster-files.txt 
		done
	fi
	cat $WORKDIR/$DOMAIN/gobuster-files.txt | sort -u > $WORKDIR/$DOMAIN/gobuster-files.txt
	rm $WORKDIR/$DOMAIN/gobuster-files.tmp
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

run() {
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
		passive)
			run_passive_amass
			;;		
	esac
}

#INTERNAL VARIABLES
BLACKLIST="example.com"
WORKDIR="$(pwd)/loot"
WORDLIST_DIR="/home/$USER/tools/wordlists"

# Get the options
while getopts ":h:w:W:m:e:o:t:T:b:" option; do
	case $option in
		h) # display Help
			display_usage
			exit 0
			;;
		w) # wordlist path
			WORDLIST=$OPTARG
			;;
		W) # wordlist dir
			WORDLIST_DIR=$OPTARG
			;;
		m) # enter mode
			MODE=$OPTARG
			;;
		e) # enter path to existing list of domains
			EXISTING_LIST=$OPTARG
			;;
		o) # enter path to output directory
			WORKDIR=$OPTARG
			;;
		t) # enter domain name
			DOMAIN=$OPTARG
			;;
		T) # enter domain files path
			declare -a DOMAINS
			i=0
			for domain in $(cat $OPTARG); do
				DOMAINS[i]=$domain
				i=$i+1
			done
			;;
		b) # enter blacklist domain name
			BLACKLIST=$OPTARG
			;;					
		\?) # Invalid option
			echo "Error: Invalid option"
			exit 1
			;;
	esac
done

mkdir -p $WORKDIR
#download latest resolvers
if [ ! -e "resolvers.txt" ]; then
	wget https://raw.githubusercontent.com/janmasarik/resolvers/master/resolvers.txt -O resolvers.txt
fi

i=0

for i in "${DOMAINS[@]}"
do
	echo "in loop"
	DOMAIN=$i
	mkdir -p $WORKDIR/$DOMAIN
	run
	DOMAIN=""
done

if [ ! -z $DOMAIN ]; then
	mkdir -p $WORKDIR/$DOMAIN
	run
fi