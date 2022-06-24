#!/usr/bin/bash

DATABASE=$2
TABLES=$3

if [ -z "$DATABASE" ]; then
  echo "Usage: $0 <database> [table1,table2...]"
  exit 1
fi

BKP_SSH_LOGIN="bkp@192.168.0.9"

if ! rsync -e "ssh -o StrictHostKeyChecking=no" -az $BKP_SSH_LOGIN:/volume1/aws-bkp/instance_ip instance_ip 2> /dev/null; then
  echo "No instance found"
  exit 1
fi

IP=$(cat instance_ip)

SSH_OPTS="-o StrictHostKeyChecking=no"
SSH_LOGIN="ubuntu@$IP"

tmp_bkp_path="bkp"

mkdir -p "$tmp_bkp_path"

CURRENT_DATE=$(date +%Y-%m-%d_%H-%M)
if [ -z "$TABLES" ]; then
  filename="$tmp_bkp_path/${CURRENT_DATE}_db_${DATABASE}.sql"
  ssh $SSH_OPTS $SSH_LOGIN "sudo mysqldump $DATABASE" > $filename
  echo "$filename backed up"
else
  while IFS= read -r TABLE; do 
    if [ -z "$TABLE" ]; then
      continue
    fi

    filename="$tmp_bkp_path/${CURRENT_DATE}_db_${DATABASE}_table_${TABLE}.sql"
    ssh $SSH_OPTS $SSH_LOGIN "sudo mysqldump $DATABASE $TABLE" < /dev/null > $filename
    echo "$filename backed up"
  done < <(echo "$TABLES" | tr ',' '\n')
fi

echo "Send files to backup server"
rsync -e "ssh -o StrictHostKeyChecking=no" -az "$tmp_bkp_path/" $BKP_SSH_LOGIN:/volume1/aws-bkp/
rm -rf "$tmp_bkp_path" &> /dev/null
