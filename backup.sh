#!/usr/bin/bash

IP=$1
DATABASE=$2
TABLES=$3

if [ -z "$IP" ] || [ -z "$DATABASE" ]; then
  echo "Usage: $0 <ip> <database> [table1,table2...]"
  exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no"
SSH_LOGIN="ubuntu@$IP"
BKP_SSH_LOGIN="bkp@192.168.0.9"

tmp_bkp_path="bkp"

mkdir -p "$tmp_bkp_path"

CURRENT_DATE=$(date +%Y-%m-%d_%H-%M)
if [ -z "$TABLES" ]; then
  filename="$tmp_bkp_path/${CURRENT_DATE}_db_${DATABASE}.sql"
  ssh $SSH_OPTS $SSH_LOGIN "sudo mysqldump $DATABASE" > $filename
else
  while IFS= read -r TABLE; do 
    filename="$tmp_bkp_path/${CURRENT_DATE}_table_${TABLE}.sql"
    ssh $SSH_OPTS $SSH_LOGIN "sudo mysqldump $DATABASE $TABLE" > $filename
  done < <(echo "$TABLES" | tr ',' '\n')
fi


rsync -az "$tmp_bkp_path/*" $BKP_SSH_LOGIN:/volume1/aws-bkp/
rm -rf "$tmp_bkp_path" &> /dev/null
