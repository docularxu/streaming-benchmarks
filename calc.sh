# calculated the real latency, supposing a widnow duration of 10 seconds
awk '{print ($1 - 10000)}' data/updated.txt > data/latency.txt

# awk '{ sum += $1 } END { print NR,sum/NR}' <  data/seen.txt
# awk '{ sum += $1 } END { print NR,sum/NR}' <  data/updated.txt
awk '{sum+=$1}END{printf "Count=%d\nAve=%.1f (seen per campaign per second)\n",NR,sum/NR}' data/seen.txt;  
awk '{sum+=$1}END{printf "Count=%d\nAve=%.2f (average last-updated)\n",NR,sum/NR}' data/updated.txt;
awk '{sum+=$1}END{printf "Count=%d\nAve=%.2f (average latency in ms)\n",NR,sum/NR}' data/latency.txt;

echo "Percentile of latency:"



SOURCE_FILE=data/latency.txt

sort -n $SOURCE_FILE |  awk '{all[NR] = $0} END{print \
 all[int(NR*0.01 - 0.5)], \
 all[int(NR*0.03 - 0.5)], \
 all[int(NR*0.05 - 0.5)], \
 all[int(NR*0.1 - 0.5)], \
 all[int(NR*0.2 - 0.5)], \
 all[int(NR*0.3 - 0.5)], \
 all[int(NR*0.4 - 0.5)], \
 all[int(NR*0.5 - 0.5)], \
 all[int(NR*0.6 - 0.5)], \
 all[int(NR*0.7 - 0.5)], \
 all[int(NR*0.8 - 0.5)], \
 all[int(NR*0.9 - 0.5)], \
 all[int(NR*0.95 - 0.5)], \
 all[int(NR*0.97 - 0.5)], \
 all[int(NR*0.99 - 0.5)]}'

