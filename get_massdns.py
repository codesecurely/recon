#!/usr/bin/python3

import json
import subprocess
import argparse
import sys


def get_options(args=sys.argv[1:]):
        parser = argparse.ArgumentParser(description="Parses command.")
        parser.add_argument("-r", "--resolvers", help="Path to resolver list file to be used.", required=True)
        parser.add_argument("-d", "--domains", help="Domains list.", required=True)
        parser.add_argument("-w", "--wordlist", help="Path to wordlist file to be used.", required=True)
        options = parser.parse_args(args)
        return options

options = get_options(sys.argv[1:])
resolvers = options.resolvers
domains_file = options.domains
wordlist_file = options.wordlist

massdns_cmd_json = [
        'massdns',
        '-s', '15000',
        '-t', 'A',
        '-o', 'J',
        '-r', resolvers,
        '--flush'
    ]

massdns_cmd_simple = [
        'massdns',
        '-s', '15000',
        '-t', 'A',
        '-o', 'S',
        '-w', 'massdns.out',
        '-r', resolvers,
        '--flush'
    ]    
domains_list = [line.rstrip('\n') for line in open(domains_file)]
wordlist = [line.rstrip('\n') for line in open(wordlist_file)]

def _decode_massdns(output):
    return [j.decode('utf-8').strip() for j in output.splitlines() if j != b'\n']

#spawn a subprocess for massdns
def _exec_and_get_output(cmd, arg):
    arg_str = bytes('\n'.join(arg), 'ascii')
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.PIPE)
    stdout, stderr = proc.communicate(input=arg_str)
    return stdout


def get_massdns_json(domains):
    processed = []

    for line in _decode_massdns(_exec_and_get_output(massdns_cmd_json, domains)):
        if not line:
            continue
        processed.append(json.loads(line.strip()))

    return processed


def save_massdns_simple(domains):
    _exec_and_get_output(massdns_cmd_simple, domains)


def save_active_ips(active):
    for ip in active:
        if active_domain['resp_type'] == "A":
            print(active_domain['data'])


def save_active_domains(active):
    f=open("active_domains.txt", "w+")
    for domain in active:
        if domain['resp_type'] == "A":
            f.write(str(domain['resp_name'])+"\n")
    f.close()

#active_domains = get_massdns(domains_list)
#save_active_domains(active_domains)

save_massdns_simple(domains_list)