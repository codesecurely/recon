#/bin/bash

COLLAB_DOMAIN=$2

for i in $(cat $1)
do
ID=$(basename $i)
curl -k $i -H "Host: $ID.$COLLAB_DOMAIN"
done
