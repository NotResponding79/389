#!/bin/bash

PATH="/bin:/usr/bin:/sbin:/usr/sbin"
\export PATH
\unalias -a
hash -r
umask 077

inifile="$1"

if [ ! -f "${inifile}" ]; then
        echo "Please include the property file.  Ex. $0 rhds.properties"
        exit 1
fi

# ----- import properties file ----- #
. ${inifile}

base="DC=$(echo ${windows_domain} | sed 's/\./,DC=/g')"

echo "Verifying password..."
verify_password=$(ldapsearch -x -LLL -h localhost -p 389 -D "${rootDN}" -y /root/.ldapj -b "${base}" 2>/dev/null)

if [ $? -ne 0 ]; then
        echo "ERROR: The ${rootDN} password provided is incorrect...exiting script"
        exit 255
fi

# ----- Setup up the OU structure --------#
ldapmodify -x -h localhost -p 389 -D "${rootDN}" -y /root/.ldapj -a <<EOF
dn: ou=Accounts,${base}
objectClass: organizationalunit
ou: Accounts
EOF

# Build basic ou structure
#
OU_FILE="Accounts
Accounts,infrastructure
Accounts,infrastructure,disabled
Accounts,infrastructure,personnel
Accounts,infrastructure,security_groups
Accounts,infrastructure,service_accounts
Accounts,tenants
Accounts,tenants,disabled
Accounts,tenants,personnel
Accounts,tenants,security_groups"

for OU in $(echo ${OU_FILE}); do
        OU=$(echo ${OU} | sed 's/\r//')
        IFS="," read -ra ARRAY <<< "${OU}"
        IFS="'"
        LEN=${#ARRAY[@]}
        OUPATH=""

        for (( j=0; j<$LEN; j=$j+1 )); do
                VARIABLE=$(echo ${ARRAY[$j]} | sed 's/-/ /g')
                OUPATH="ou=${VARIABLE},${OUPATH}"
        done

        OUPATH="${OUPATH}${base}"
        NEW_OU=${ARRAY[$LEN-1]}
        ldapmodify -x -h localhost -p 389 -D "${rootDN}" -y /root/.ldapj -a <<EOF
dn: ${OUPATH}
objectClass: organizationalunit
ou: ${NEW_OU}
EOF

done

#---------- Add Service Accounts ----------#

echo "Adding service accounts...."

#---------- LDAP sync ----------#

ldapmodify -x -h localhost -p 389 -D "${rootDN}" -y /root/.ldapj -a <<EOF
dn: CN=${ldapSync},OU=service_accounts,OU=infrastructure,OU=Accounts,${base}
objectClass: top
objectClass: person
objectClass: organizationalperson
objectClass: inetorgperson
givenname: svc
cn: ${ldapSync}
sn: ldapsync
userPassword: ${ldapSync_pwd}
EOF

#---------- AD sync ----------#

ldapmodify -x -h localhost -p 389 -D "${rootDN}" -y /root/.ldapj -a <<EOF
dn: CN=${ad_to_ldap},OU=service_accounts,OU=infrastructure,OU=Accounts,${base}
objectClass: top
objectClass: person
objectClass: organizationalperson
objectClass: inetorgperson
givenname: svc
cn: ${ad_to_ldap}
sn: adsync
userPassword: ${ad_to_ldap_pwd}
EOF

exit 0