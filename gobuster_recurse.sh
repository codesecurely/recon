#!/bin/bash

TARGET="$1"
WORDLIST="$2"
LEVELS="$3"
FILENAME="$4"

TMP_FILE_PREFIX="/tmp/gobuster_$$"
USER_AGENT='Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
BACKUP_WORDLIST="/usr/local/wordlists/custom/rw-common-dirs.txt"
RESPONSE_CODES="200,301,307,401,403"
THREADS="10"

print_help() {
        echo "Usage: $(basename $0) <url> <wordlist> <levels>"
}


if [ -z "$TARGET" ]; then
    echo "Error: Provide me with a URL"
    echo
    print_help
    exit 1
fi

if [ -z "$WORDLIST" ]; then
    echo "Error: You did not provide me with a wordlist."
    echo
    WORDLIST="${BACKUP_WORDLIST}"
    echo "Using ${WORDLIST}, instead."
    #print_help
    exit 2
fi

if [ ! -e "$WORDLIST" ]; then
    echo "Error: Wordlist file doesn't exist."
    echo
    print_help
    #exit 3
fi

if [ -z "$LEVELS" ]; then
    echo "Error: Provide me with a number of levels to recurse"
    echo
    print_help
    exit 4
elif [[ ! "$LEVELS" =~ ^[0-9]+$ ]]; then
    echo "Error: Provide me with an integer"
    echo
    print_help
    exit 5
fi

if [ ! -e "$FILENAME" ]; then
    FILENAME="gobuster_output.txt"
fi

run_gobuster() {
    local TARGET=$1
    local LEVEL=$2
    local NEXT_LEVEL=$((LEVEL + 1))

    #echo "[-] Level = $LEVEL"
    #echo "[+] Busting $TARGET"

    if [ "${LEVEL}" -lt "${LEVELS}" ]; then
        #echo gobuster -f -q -e -k -r -t ${THREADS} -m dir -w "${WORDLIST}" -s "${RESPONSE_CODES}" -u ${TARGET} -a "${USER_AGENT}" 
        gobuster dir -f -q -e -k -r -t ${THREADS} -w "${WORDLIST}" -s "${RESPONSE_CODES}" -u ${TARGET} -a "${USER_AGENT}" | grep 'http.*Status: [234]' | sed 's/ (Status.*//' | while read HIT; do
            echo "[+] Found $HIT"
            echo $HIT >> $FILENAME
            run_gobuster ${HIT} ${NEXT_LEVEL}
        done
    fi
}

STATUS=$(curl -k -o /dev/null --silent --head --write-out '%{http_code}\n' "$TARGET")

if [ "$STATUS" -ge "100" -a "$STATUS" -lt "500" ]; then
    echo "[+] Found $TARGET"
    run_gobuster $TARGET 0
fi
