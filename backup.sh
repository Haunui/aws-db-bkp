#!/usr/bin/bash

DATABASE=$2
TABLES=$3

if [ -z "$DATABASE" ]; then
  echo "Usage: $0 <database> [table1,table2...]"
  exit 1
fi

BKP_SSH_LOGIN="bkp@192.168.0.9"

if ! ssh -o StrictHostKeyChecking=no $BKP_SSH_LOGIN 'cat /volume1/aws-bkp/instance_ip; exit' < /dev/null > instance_ip; then
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

    if [ -z "$(ssh $SSH_OPTS $SSH_LOGIN "sudo mysql -e \"use $DATABASE; show tables\"" | grep $TABLE)" ]; then
      echo "Table '$TABLE' not found in database '$DATABASE'"
      exit 1
    fi

    filename="$tmp_bkp_path/${CURRENT_DATE}_db_${DATABASE}_table_${TABLE}.sql"
    ssh $SSH_OPTS $SSH_LOGIN "sudo mysqldump $DATABASE $TABLE" < /dev/null > $filename

    last_bkp_found=$(ssh $BKP_SSH_LOGIN "ls -t /volume1/aws-bkp | grep table_$TABLE" | head -n1)

    if ! [ -z "$last_bkp_found" ]; then
      echo "Table '$TABLE' backup found"
      rsync -e "ssh -o StrictHostKeyChecking=no" -az $BKP_SSH_LOGIN:/volume1/aws-bkp/$last_bkp_found last_bkp_found.sql

      cp $filename current_table.sql

      head -n -1 current_table.sql > current_table.sql
      head -n -1 last_bkp_found.sql > last_bkp_found.sql

      cat current_table.sql
      echo "______________________________"
      cat last_bkp_found.sql

      c_sum=$(cat current_table.sql | md5sum | cut -d' ' -f1)
      l_sum=$(cat last_bkp_found.sql | md5sum | cut -d' ' -f1)

      rm -f current_table.sql
      rm -f last_bkp_found.sql

      echo "$c_sum == $l_sum"

      if [[ $c_sum == $l_sum ]]; then
        rm -f $filename
        echo "Table '$TABLE' backup in backup folder is up to date"
        echo "Nothing to do for this table"
      else
        echo "Table '$TABLE' backup in backup folder is outdated"
      fi
    fi

    echo "$filename backed up"
  done < <(echo "$TABLES" | tr ',' '\n')
fi

echo "Send files to backup server"
rsync -e "ssh -o StrictHostKeyChecking=no" -az "$tmp_bkp_path/" $BKP_SSH_LOGIN:/volume1/aws-bkp/
rm -rf "$tmp_bkp_path" &> /dev/null
