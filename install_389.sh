#!/bin/bash

SITEPW='PASSWORD'


##Colors##
Yellow='\e[0;33m'
BGreen='\e[1;32m'       # Green
BCyan='\e[1;36m'        # Cyan
NC="\e[m"               # Color Reset

HNs=$(hostname -s)

case "$HNs" in
        *pxe*)
        IPADDR=$(ip addr show dev eth0 | grep 'inet' | awk '{print $2}' | cut -d\/ -f1)
        ;;

        *ldp*)
        IPADDR=$(hostname -I)
        ;;

esac

PREFIX=$(echo "${IPADDR}" | awk -F\. '{print $1 "." $2 "." $3}')

case "${PREFIX}" in
        '10.17.232')
        UNC='b02'
        LOC='cmc'
        Code='ADF-C'
        InfraPrefix='10.17.232'
        Site='3'
        HostPrefix='svcpgc'
        BASEDN="dc=${UNC},dc=vmis,dc=nro,dc=gov"
        SUFFIX="vmis.nro.gov"
        DOMAIN='${UNC}.${SUFFIX}'
        ;;

esac

##cmd to remove 389 ##
#remove-ds-admin.pl -a -y -f

##Installing required packages ##
yum -y install 389-ds 389-ds-base 389-ds-console 389-admin 389-admin-console dos2unix xorg-x11-xauth java-1.8.0-openjdk
echo -e "${Yellow}Check for any errors and then press ${BCyan}Enter${NC} Key or ${Yellow}Ctrl+C${NC} to cancel script.${NC}"
read

## Setting up password file ##
echo -n "${SITEPW}" > /root/.ldapj
chmod 600 /root/.ldapj

## Setting up 389 admin ##
/usr/sbin/setup-ds-admin.pl -s -f /root/dirsrv_data/setup-ds-response.ini
echo -e "${Yellow}Check for any errors and then press ${BCyan}Enter${NC} Key or ${Yellow}Ctrl+C${NC} to cancel script.${NC}"
read

## Creating the password files ##
echo "Internal (Software) Token:${SITEPW}" > /etc/dirsrv/slapd-${HNs}/pin.txt
chmod 0400 /etc/dirsrv/slapd-${HNs}/pin.txt
chown nobody:nobody /etc/dirsrv/slapd-${HNs}/pin.txt
echo "internal:${SITEPW}" > /etc/dirsrv/admin-serv/password.conf
chmod 0400 /etc/dirsrv/admin-serv/password.conf
chown nobody:nobody /etc/dirsrv/admin-serv/password.conf
sed -i 's#^NSSPassPhraseDialog .*$#NSSPassPhraseDialog file://etc/dirsrv/admin-serv/password.conf#' /etc/dirsrv/admin-serv/nss.conf
chown -R nobody:nobody /etc/dirsrv
systemctl enable dirsrv.target
systemctl enable dirsrv-admin
systemctl enable dirsrv@$(hostname -s)

## Creating the default OU's ##
/root/dirsrv_data/setup-ou-structure.sh /root/dirsrv_data/rhds.properties

echo -e "${Yellow}Check for any errors and then press ${BCyan}Enter${NC} Key or ${Yellow}Ctrl+C${NC} to cancel script.${NC}"
read

## Creating the replications ##
/root/dirsrv_data/setup-replica.sh /root/dirsrv_data/rhds.properties
echo -e "${Yellow}Check for any errors and then press ${BCyan}Enter${NC} Key or ${Yellow}Ctrl+C${NC} to cancel script.${NC}"
read

echo -e "${BGreen}All done${NC}"