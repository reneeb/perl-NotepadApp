#!/bin/sh

DBNAME=notepad.db

# make a backup of existing DB
if [ -e notepad.db ]; then mv $DBNAME ${DBNAME}_$(date +%s); fi

# create DB with tables
sqlite3 $DBNAME 'CREATE TABLE articles ( id char(8), uuid char(30), notepad_passwd varchar(255), comment varchar(255), title varchar(255) )'
sqlite3 $DBNAME 'CREATE TABLE sessions ( notepad_id char(8), session_id char(30), start integer, ip varchar(15) )'

