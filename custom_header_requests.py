#!/usr/bin/python3

import requests
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("domains", help="list of domains to make requests to")
args = parser.parse_args()

filename = args.domains
pingback_domain = "mtjecrfr76hpwn1v02836y8j5ab2zr.burpcollaborator.net"

with open(filename, 'r') as domains:
    for domain in domains:
        headers = {'Host': "1."+pingback_domain, 'User-Agent': 'Mozilla/5.0 (Windows NT 6.0; WOW64; rv:24.0) Gecko/20100101 Firefox/24.0'}
        requests.get('http://mtjecrfr76hpwn1v02836y8j5ab2zr.burpcollaborator.net', headers=headers, verify=False)    


