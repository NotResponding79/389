#!/bin/bash
## Version 2.0
## BJJ fixed issues with lookup and verify portion of script

check_for_error=$(ldapsearch -x -ZZ -LLL -h $(hostname -f) -D 'cn=directory manager' -y /root/.ldapj -b o=netscaperoot | grep nsServerAddress | awk '{print $2}')

if [[ "${check_for_error}" =~ $(hostname -I | awk '{print $1}') ]]; then
        ldapmodify -x -ZZ -D 'cn=directory manager' -h $(hostname -f) -y /root/.ldapj -cv -a << EOFix
dn: cn=configuration,cn=admin-serv-$(hostname -s),cn=389 Administration Server,cn=Server Group,cn=$(hostname -f),ou=$(hostname -d),o=NetscapeRoot
changetype: modify
replace: nsServerAddress
nsServerAddress: $(hostname -f)
EOFix
        stop-ds-admin ; stop-dirsrv ; start-dirsrv ; start-ds-admin
else
        echo "Console SSL issue resolved"
fi

exit $?