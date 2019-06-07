#!/bin/bash

################################################################################                                                                                             ######
################################################################################                                                                                             ######
# NAME: 389-backup.sh
# PURPOSE:This script backups the 389 Directory Server Database and takes and LD                                                                                             IF
# export of the DS.
# It stores these backups in /var/dirsrv/backups/ldap.<TIMESTAMP>/
# When run, it removes directories whose TIMESTAMP is greater than the ARCHIVE_P                                                                                             ERIOD set.
################################################################################                                                                                             ########
################################################################################                                                                                             #########


PATH='/bin:/usr/bin:/sbin:/usr/sbin'
\export PATH
\unalias -a
hash -r
umask 027

#
# If TEST is any value expect 0, only display what whould be done
#
TEST=0
ECHO=''
[ ${TEST} -ne 0 ] && ECHO='/bin/echo'

HOST=$(hostname -s)
TIMESTAMP=$(date +%Y%b%d_%H%M)
ARCHIVE_PERIOD=7;
BACKUP_DIR='/var/dirsrv/backups'
BINDDN='cn=directory manager'

# Import contents
#ldif2db -n <backend-instance> -i <file>
# Restore from database
#bak2db /dir/to/backup

# Create a directory for the LDAP backup.
[ ! -d "${BACKUP_DIR}/ldap.${TIMESTAMP}" ] && ${ECHO} mkdir -m 0750 -p ${BACKUP_                                                                                             DIR}/ldap.${TIMESTAMP}
${ECHO} chmod -R 750 ${BACKUP_DIR}
${ECHO} chown -R nobody:nobody ${BACKUP_DIR}

# Extract an LDIF from the current LDAP configuration.
${ECHO} /usr/sbin/db2ldif -Z ${HOST} -n userRoot -a ${BACKUP_DIR}/ldap.${TIMESTA                                                                                             MP}/userRoot.ldif -U

# Create a backup of the LDAP database.
${ECHO} /usr/sbin/db2bak.pl -Z ${HOST} -A ${BACKUP_DIR}/ldap.${TIMESTAMP}/db -D                                                                                              "${BINDDN}" -j /root/.ldapj -P STARTTLS

# Clean /remove backups older than $ARCHIVE_PERIOD days.
ARCHIVE=$(( ${ARCHIVE_PERIOD} - 1))

${ECHO} sleep 60

#DIRECTORIES=$(find ${BACKUP_DIR} -type d -name ldap.* -mtime +${ARCHIVE_PERIOD}                                                                                              )

for DIR in $(find ${BACKUP_DIR} -type d -name "*ldap.*" -mtime +${ARCHIVE_PERIOD                                                                                             } ); do
  ${ECHO} rm -rf ${DIR}
done

for DIR in $(find /var/lib/dirsrv/slapd-${HOST}/bak -type d -name "${HOST}-*" -m                                                                                             time +${ARCHIVE_PERIOD} ); do
  ${ECHO} rm -rf ${DIR}
done

exit 0
