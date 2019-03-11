# awk '{ sum += $1 } END { print NR,sum/NR}' <  data/seen.txt
# awk '{ sum += $1 } END { print NR,sum/NR}' <  data/updated.txt
awk '{sum+=$1}END{printf "Count=%d\nAve=%.1f (seen per campaign per second)\n",NR,sum/NR}' data/seen.txt;  
awk '{sum+=$1}END{printf "Count=%d\nAve=%.2f (latency in ms)\n",NR,sum/NR}' data/updated.txt;

echo "Percentile of updated.txt:"

SOURCE_FILE=data/updated.txt

sort -n $SOURCE_FILE |  awk '{all[NR] = $0} END{print all[int(NR*0.05 - 0.5)], \
 all[int(NR*0.1 - 0.5)], \
 all[int(NR*0.2 - 0.5)], \
 all[int(NR*0.3 - 0.5)], \
 all[int(NR*0.4 - 0.5)], \
 all[int(NR*0.5 - 0.5)], \
 all[int(NR*0.6 - 0.5)], \
 all[int(NR*0.7 - 0.5)], \
 all[int(NR*0.8 - 0.5)], \
 all[int(NR*0.9 - 0.5)], \
 all[int(NR*0.95 - 0.5)]}'

