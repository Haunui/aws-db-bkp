#!/usr/bin/bash

DATABASE=$2
TABLES=$3

SSH_OPTS="-o StrictHostKeyChecking=no"

if [ -z "$DATABASE" ]; then
  echo "Usage: $0 <database> [table1,table2...]"
  exit 1
fi

if ! ssh $SSH_OPTS $BKP_SSH_LOGIN "cat $BKP_PATH/instance_ip" < /dev/null > instance_ip; then
  echo "No instance found"
  exit 1
fi

IP=$(cat instance_ip)

SSH_LOGIN="$SSH_USER@$IP"

tmp_bkp_path="bkp"

mkdir -p "$tmp_bkp_path"

if [ -z "$(ssh $SSH_OPTS $SSH_LOGIN "sudo mysql -e \"show databases\"" | grep $DATABASE)" ]; then
  echo "Database '$DATABASE' not found"
  exit 1
fi

CURRENT_DATE=$(date +%Y-%m-%d_%H-%M)
if [ -z "$TABLES" ]; then
  filename="$tmp_bkp_path/${CURRENT_DATE}_db_${DATABASE}.sql"
  ssh $SSH_OPTS $SSH_LOGIN "sudo mysqldump $DATABASE" > $filename

  last_bkp_found=$(ssh $BKP_SSH_LOGIN "ls -t $BKP_PATH | grep db_$DATABASE" | head -n1)

  if ! [ -z "$last_bkp_found" ]; then
    echo "Database '$DATABASE' backup found"
    rsync -e "ssh $SSH_OPTS" -az $BKP_SSH_LOGIN:/$BKP_PATH/$last_bkp_found last_bkp_found.sql

    cp $filename dated_current_table.sql
    mv last_bkp_found.sql dated_last_bkp_found.sql

    head -n -1 dated_current_table.sql > current_table.sql
    head -n -1 dated_last_bkp_found.sql > last_bkp_found.sql

    c_sum=$(cat current_table.sql | md5sum | cut -d' ' -f1)
    l_sum=$(cat last_bkp_found.sql | md5sum | cut -d' ' -f1)

    rm -f current_table.sql
    rm -f last_bkp_found.sql

    echo "[[ $c_sum == $l_sum ]]"

    if [[ $c_sum == $l_sum ]]; then
      rm -f $filename
      echo "Database '$DATABASE' backup in backup folder is up to date"
      echo "Nothing to do for this database"
    else
      echo "Database '$DATABASE' backup in backup folder is outdated"
    fi
  fi

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
    ssh $SSH_OPTS $SSH_LOGIN "sudo mysqldump $DATABASE $TABLE" > $filename

    last_bkp_found=$(ssh $BKP_SSH_LOGIN "ls -t $BKP_PATH | grep table_$TABLE" | head -n1)

    if ! [ -z "$last_bkp_found" ]; then
      echo "Table '$TABLE' backup found"
      rsync -e "ssh $SSH_OPTS" -az $BKP_SSH_LOGIN:$BKP_PATH/$last_bkp_found last_bkp_found.sql

      cp $filename dated_current_table.sql
      mv last_bkp_found.sql dated_last_bkp_found.sql

      head -n -1 dated_current_table.sql > current_table.sql
      head -n -1 dated_last_bkp_found.sql > last_bkp_found.sql

      c_sum=$(cat current_table.sql | md5sum | cut -d' ' -f1)
      l_sum=$(cat last_bkp_found.sql | md5sum | cut -d' ' -f1)

      rm -f current_table.sql
      rm -f last_bkp_found.sql

      echo "[[ $c_sum == $l_sum ]]"

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
rsync -e "ssh $SSH_OPTS" -az "$tmp_bkp_path/" $BKP_SSH_LOGIN:$BKP_PATH
rm -rf "$tmp_bkp_path" &> /dev/null
