#!/bin/bash

#####
#
# NAME:         setup-replica.sh
# PURPOSE:      This script configures the replication of data from AD to LDAP
#                 and from LDAP to LDAP
#
####

PATH='/bin:/usr/bin:/sbin:/usr/sbin'
\export PATH
\unalias -a
hash -r
umask 077

TEST=0
ECHO=''
[ ${TEST} -ne 0 ] && ECHO='/bin/echo'

inifile="$1"

if [ ! -f "${inifile}" ]; then
  echo "Please include the property file. Ex. $0 rhds.properties"
  exit
fi

source ${inifile}

service_account_ou="service_accounts,ou=infrastructure,ou=Accounts"
base="dc=$(echo ${windows_domain} | sed 's/\./,dc=/g')"

echo "Verifying the password..."
verify_password=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -b "${base}" 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "ERROR:  The ${rootDN} password provided is incorrect for ${base}. Exiting script."
  exit 255
fi

replicadn=$(ldapsearch -x -ZZ -LLL -o ldif-wrap=no -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -b 'cn=config' "(&(objectClass=nsMappingTree)(cn=*${unc}*))" dn)
replicadn=$(/bin/sed -e "s%dn: %cn=replica,%" <<< ${replicadn})

hostShort=$(hostname -s)
supplierShort=$(/bin/echo ${supplier_fqdn} | cut -d\. -f1)
consumerShort=$(/bin/echo ${consumer_fqdn} | cut -d\. -f1)
windowsShort=$(/bin/echo ${dc_fqdn} | cut -d\. -f1)

firstEth=$(ifconfig | grep 'UP' | grep -v 'LOOPBACK' | awk -F\: '{print $1}')
replicaID=$(ip addr show ${firstEth} | grep inet | awk '{print $2}' | cut -d/ -f1 | cut -d\. -f4)
instance_name=$(/bin/ls /etc/dirsrv | grep slapd | cut -d/ -f3 | grep -v removed)

echo "Checking for Changelog..."
verify_changelog=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -b 'cn=config' "(&(cn=changelog5)(nsslapd-changelogdir=/var/lib/dirsrv/${instance_name}/changelogdb))")

echo "verify_changelog == ${verify_changelog}"

if [ -n "${verify_changelog}" ]; then
  echo "Changelog is already enabled. Setting the Database directory..."
  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -c <<EOF

# ------ Enable the changelog ------ #
dn: cn=changelog5,cn=config
changetype: modify
replace: nsslapd-changelogdir
nsslapd-changelogdir: /var/lib/dirsrv/${instance_name}/changelogdb

EOF

else
  echo 'Need to enable the changelog...'
  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -c <<EOF

# ------ Enable the changelog ------ #
dn: cn=changelog5,cn=config
changetype: add
objectclass: top
objectclass: extensibleObject
cn: changelog5
nsslapd-changelogdir: /var/lib/dirsrv/${instance_name}/changelogdb

EOF
fi

echo "Checking for replica..."
verify_replica=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -b 'cn=config' objectclass=nsds5replica)
echo "verify_replica == ${verify_replica}"

if [ -n "${verify_replica}" ]; then
  echo 'Replica is already defined. Ensure replica is up to date.'
  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -c <<EOF

dn: ${replicadn}
changetype: modify
replace: nsds5replicaid
nsds5replicaid: ${replicaID}
-
replace: nsds5flags
nsds5flags: 1
-
replace: nsds5ReplicaPurgeDelay
nsds5ReplicaPurgeDelay: 604800
-
replace: nsds5replicatype
nsds5replicatype: 3

EOF

else
  echo "Creating replica ID ${replicaID}..."
  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -c <<EOF
# ----- Create Supplier Replica ----- #

dn: ${replicadn}
changetype: add
objectclass: top
objectclass: nsds5replica
objectclass: extensibleObject
cn: replica
nsds5replicaroot: ${base}
nsds5replicaid: ${replicaID}
nsds5replicatype: 3
nsds5flags: 1
nsds5ReplicaPurgeDelay: 604800

EOF
fi

#
# Place the ${ldapSync} account in the Directory Administrators group
# to grant the account the right to modify/add/delete data during
# replication
#

echo "Adding ${ldapSync} account to Directory Administrators"
${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -c <<EOF
dn: cn=Directory Administrators,${base}
changetype: modify
add: uniquemember
uniquemember: cn=${ldapSync},ou=${service_account_ou},${base}

EOF

# ----- If this is LDAP1, then we must setup the WinSync agreement ----- #

echo 'Checking for a WinSync agreement...'

if [[ "$(hostname -s)" =~ "ldp001" ]]; then
  echo 'Setting up a WinSync agreement...'

  verify_adsync=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -b 'cn=config' objectclass=nsDSWindowsReplicationAgreement)


  echo "Enabling and configuring Active Directory sync for ${dc_fqdn}..."

  if [ -n "${verify_adsync}" ]; then
    echo 'AD Sync is already defined. Updating policy...'
    ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -c <<EOF

# ----- Enable AD Sync Agreement ----- #

dn: cn=${windowsShort},${replicadn}
changetype: modify
replace: description
description: Synchronization agreement with Primary AD Server
-
replace: nsds7WindowsReplicaSubtree
nsds7WindowsReplicaSubtree: ${base}
-
replace: nsds7DirectoryReplicaSubtree
nsds7DirectoryReplicaSubtree: ${base}
-
replace: nsds7NewWinUserSyncEnabled
nsds7NewWinUserSyncEnabled: on
-
replace: nsds7NewWinGroupSyncEnabled
nsds7NewWinGroupSyncEnabled: on
-
replace: nsds7WindowsDomain
nsds7WindowsDomain: ${windows_domain}
-
replace: nsds5ReplicaRoot
nsds5ReplicaRoot: ${base}
-
replace: nsds5ReplicaHost
nsds5ReplicaHost: ${dc_fqdn}
-
replace: nsds5ReplicaPort
nsds5ReplicaPort: 389
-
replace: nsds5ReplicaBindDN
nsds5ReplicaBindDN: cn=${ad_to_ldap},ou=${service_account_ou},${base}
-
replace: nsds5ReplicaTransportInfo
nsds5ReplicaTransportInfo: TLS
-
replace: nsds5ReplicaBindMethod
nsds5ReplicaBindMethod: SIMPLE
-
replace: nsds5ReplicaCredentials
nsds5ReplicaCredentials: ${ad_to_ldap_pwd}

EOF

  else
    echo "Creating WinSync agreement."
    ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -c <<EOF

# ----- Enable AD Sync Agreement ----- #

dn: cn=${windowsShort},${replicadn}
changetype: add
objectClass: top
objectClass: nsdsWindowsReplicationAgreement
description: Synchronization agreement with Primary AD Server
nsds7WindowsReplicaSubtree: ${base}
nsds7DirectoryReplicaSubtree: ${base}
nsds7NewWinUserSyncEnabled: on
nsds7NewWinGroupSyncEnabled: on
nsds7WindowsDomain: ${windows_domain}
nsds5ReplicaRoot: ${base}
nsds5ReplicaHost: ${dc_fqdn}
nsds5ReplicaPort: 389
nsds5ReplicaBindDN: cn=${ad_to_ldap},ou=${service_account_ou},${base}
nsds5ReplicaTransportInfo: TLS
nsds5ReplicaBindMethod: SIMPLE
nsds5ReplicaCredentials: ${ad_to_ldap_pwd}

EOF
  fi
fi

echo "Determine if agreement for ${supplierShort} (supplier) to ${consumerShort} (consumer) is active."

verify_consync=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -b "cn=${consumerShort},${replicadn}")

if [ -n "${verify_consync}" ]; then
  echo "Replica for ${supplierShort} to ${consumerShort} is active. Reconfiguring..."
  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -c <<EOF

# ----- Modify Replication Agreement ----- #
dn: cn=${consumerShort},${replicadn}
changetype: modify
replace: description
description: Replication agreement with ${consumerShort}
-
replace: nsds5ReplicaPort
nsds5ReplicaPort: 389
-
replace: nsds5ReplicaTransportInfo
nsds5ReplicaTransportInfo: TLS
-
replace: nsds5ReplicaBindMethod
nsds5ReplicaBindMethod: SIMPLE
-
replace: nsds5ReplicaBindDN
nsds5ReplicaBindDN: cn=${ldapSync},ou=${service_account_ou},${base}
-
replace: nsds5ReplicaCredentials
nsds5ReplicaCredentials: ${ldapSync_pwd}

EOF

else
  echo "Replication agreement for ${supplierShort} to ${consumerShort} is NOT active..."
  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -c <<EOF

# ----- Create Replication Agreement ----- #
dn: cn=${consumerShort},${replicadn}
changetype: add
objectClass: top
objectClass: nsds5ReplicationAgreement
description: Replication agreement with ${consumerShort}
cn: ${consumerShort}
nsds5ReplicaRoot: ${base}
nsds5ReplicaHost: ${consumer_fqdn}
nsds5ReplicaPort: 389
nsds5ReplicaTransportInfo: TLS
nsds5ReplicaBindMethod: SIMPLE
nsds5ReplicaBindDN: cn=${ldapSync},ou=${service_account_ou},${base}
nsds5ReplicaCredentials: ${ldapSync_pwd}

EOF

fi

exit $?
