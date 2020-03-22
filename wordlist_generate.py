#!/usr/bin/python3

import argparse
import sys

def get_options(args=sys.argv[1:]):
    parser = argparse.ArgumentParser(description="Parses command.")
    parser.add_argument("-w", "--wordlist", help="Path to wordlist file to be used.", required=True)
    parser.add_argument("-d", "--domain", help="Domain name.", required=True)
    options = parser.parse_args(args)
    return options

options = get_options(sys.argv[1:])
scope = options.domain

def generate_domains():
    try:
        with open(options.wordlist, 'r') as w:
            wordlist = w.readlines()
    except OSError:
        print ("Could not open/read file: ", options.wordlist)
        sys.exit()

    for word in wordlist:
        print('{}.{}'.format(word.strip(), scope))
