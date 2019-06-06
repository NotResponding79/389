#!/bin/bash

######################################################################################
######################################################################################
# NAME: setup_password_policy.sh
# PURPOSE:This script configures the LDAP security settings relevant to the password
# policy.
########################################################################################
########################################################################################

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

ECHO=''
TEST=0
[ ${TEST} -ne 0 ] && ECHO='/bin/echo'

# ----- import properties file ----- #
source ${inifile}

base="dc=$(echo ${windows_domain} | sed 's/\./,dc=/g')"
service_account_ou="service_accounts,ou=infrastructure,ou=Accounts"

echo "Verifying password...."
verify_password=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj -b "${base}" 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "ERROR: The ${rootDN} password provided is incorrect...exiting script"
  exit 255
fi

# ----- Enable Password Policy ----- #
echo "Setting the global password policy..."

${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj <<EOF

# ----- Set GLOBAL Password Policies ----- #

dn: cn=config
changetype: modify
replace: nsslapd-pwpolicy-local
nsslapd-pwpolicy-local: on
-
replace: passwordChange
passwordChange: on
-
replace: passwordCheckSyntax
passwordCheckSyntax: on
-
replace: passwordExp
passwordExp: on
-
replace: passwordGraceLimit
passwordGraceLimit: 0
-
replace: passwordInHistory
passwordInHistory: 24
-
replace: passwordHistory
passwordHistory: on
-
replace: passwordLockout
passwordLockout: on
-
replace: passwordLockoutDuration
passwordLockoutDuration: 900
-
replace: passwordMaxAge
passwordMaxAge: 180d
-
replace: passwordMaxFailure
passwordMaxFailure: 3
-
replace: passwordMaxRepeats
passwordMaxRepeats: 2
-
replace: passwordMin8bit
passwordMin8bit: 0
-
replace: passwordMinAge
passwordMinAge: 1d
-
replace: passwordMinAlphas
passwordMinAlphas: 2
-
replace: passwordMinCategories
passwordMinCategories: 2
-
replace: passwordMinDigits
passwordMinDigits: 2
-
replace: passwordMinLength
passwordMinLength: 12
-
replace: passwordMinLowers
passwordMinLowers: 2
-
replace: passwordMinSpecials
passwordMinSpecials: 2
-
replace: passwordMinTokenLength
passwordMinTokenLength: 3
-
replace: passwordMinUppers
passwordMinUppers: 2
-
replace: passwordMustChange
passwordMustChange: on
-
replace: passwordResetFailureCount
passwordResetFailureCount: 900
-
replace: passwordStorageScheme
passwordStorageScheme: SSHA512
-
replace: passwordUnlock
passwordUnlock: on
-
replace: passwordWarning
passwordWarning: 14d

# ----- Performance configuration ----- #

#dn: cn=config
#changetype: modify
#replace: nsslapd-idletimeout
#nssladp-idletimeout: 900

EOF

if [[ "$?" != 0 ]]; then
  echo "ERROR: Operation failure"
  exit 255
fi

verify_pwpolicy=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -b ou=${service_account_ou},${base} -y /root/.ldapj cn=nsPwPolicyContainer 2                                                                              >&1)
if [ -z "${verify_pwpolicy}" ]; then
  echo "Creating sub password policy for service accounts..."
  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj <<EOF

# ----- Sub Policy for Service accounts ----- #

dn: cn=nsPwPolicyContainer,ou=${service_account_ou},${base}
changetype: add
objectClass: nsContainer
objectClass: top
cn: nsPwPolicyContainer

EOF
fi

if [[ "$?" != 0 ]]; then
  echo "ERROR: Operation failure"
  exit 255
fi

echo "Checking for password policy for service acounts..."

verify_pwpolicy_settings=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -b "cn=nspwpolicycontainer,ou=${service_account_ou},${base}" -y /ro                                                                              ot/.ldapj "(&(objectclass=ldapsubentry)(objectclass=passwordpolicy))" 2> /dev/null )

# ----- Sub Policy for Service accountys ----- #

if [ -n "${verify_pwpolicy_settings}" ]; then

        echo "UPDATING password policy for service accounts..."
        ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj <<EOF
dn: cn="cn=nsPwPolicyEntry,ou=${service_account_ou},${base}",cn=nsPwPolicyContainer,ou=${service_account_ou},${base}
changetype: modify
replace: passwordMaxRepeats
passwordMaxRepeats: 2
-
replace: passwordMinLength
passwordMinLength: 12
-
replace: passwordMustChange
passwordMustChange: off
-
replace: passwordMinAlphas
passwordminAlphas: 2
-
replace: passwordExp
passwordExp: off
-
replace: passwordMinDigits
passwordMinDigits: 2
-
replace: passwordMinSpecials
passwordMinSpecials: 2
-
replace: passwordMinAge
passwordMinAge: 0
-
replace: passwordMaxAge
passwordMaxAge: 180d
-
replace: passwordWarning
passwordWarning: 14d
-
replace: passwordMinLowers
passwordMinLowers: 2
-
replace: passwordChange
passwordChange: off
-
replace: passwordMinUppers
passwordMinUppers: 2
-
replace: passwordCheckSyntax
passwordCheckSyntax: on
-
replace: passwordStorageScheme
passwordStorageScheme: SSHA512
-
replace: passwordLockout
passwordLockout: off
-
replace: passwordResetFailureCount
passwordResetFailureCount: 600
-
replace: passwordMaxFailure
passwordMaxFailure: 5
-
replace: passwordHistory
passwordHistory: off
-
replace: passwordLockoutDuration
passwordLockoutDuration: 900
-
replace: passwordInHistory
passwordInHistory: 24

EOF

else # verify_pwpolicy_settings

  echo "CREATING password policy..."

  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj <<EOF
dn: cn="cn=nsPwPolicyEntry,ou=${service_account_ou},${base}",cn=nsPwPolicyContainer,ou=${service_account_ou},${base}
changetype: add
objectClass: ldapsubentry
objectClass: passwordpolicy
objectClass: top
cn: "cn=nsPwPolicyEntry,ou=${service_account_out},${base}"
passwordMaxRepeats: 2
passwordMinLength: 12
passwordMustChange: off
passwordMinAlphas: 1
passwordExp: off
passwordMinDigits: 2
passwordMinSpecials: 2
passwordMinAge: 0
passwordMaxAge: 180d
passwordMinLowers:2
passwordChange: off
passwordMinUppers: 2
passwordCheckSyntax: on
passwordStorageScheme: SSHA512
passwordLockout: on
passwordResetFailurecount: 600
passwordMaxFailure: 3
passwordHistory: on
passwordWarning: 14d
passwordLockoutDuration: 900
passwordInHistory: 24

EOF
fi # end if verify_pwpolicy_settings

if [[ "$?" != 0 ]]; then
 echo "ERROR: Operation failure"
 exit 255
fi

echo "Checking for pwtemplate"
#echo "ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D \"${rootDN}\" -b \"cn=nspwpolicycontainer,ou=${service_account_ou},${base}\" -y /root/.ldapj \"(&(o                                                                              bjectclass=ldapsubentry)(objectclass=costemplate))"

verify_pwtemplate=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -b "ou=${service_account_ou},${base}" -y /root/.ldapj "(&(objectclass=ldap                                                                              subentry)(objectclass=costemplate))" 2>/dev/null )

if [ -z "${verify_pwtemplate}" ]; then

  echo "Setting sub password policy template..."
  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj << EOF

dn: cn="cn=nsPwTemplateEntry,ou=${serive_account_ou},${base}",cn=nsPwPolicyContainer,ou=${service_account_ou},${base}
changetype: add
objectClass: extensibleObject
objectClass: costemplate
objectClass: ldapsubentry
objectClass: top
cosPriority: 1
pwdpolicysubentry: cn="cn=nsPwPolicyEntry,ou=${service_account_ou},${base}",cn=nsPwPolicyContainer,ou=${service_account_ou},${base}
cn: "cn=nsPwTemplateEntry,ou=${service_account-ou},${base}"

EOF
fi # end if verify_pwtemplate"

if [[ "$?" != 0 ]]; then
  echo "ERROR: Operation failure"
  exit 255
fi

verif_pwpointer=$(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -b ou=${service_account_ou},${base} -y /root/.ldapj "(&(objectclass=ldapsube                                                                              ntry)(objectclass=cosPointerDefinition))") 2>&1

if [ -z "${verify_pwpointer}" ]; then

  echo "Setting sub password policy pointer..."
  ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj <<EOF

dn: cn=nsPwPolicy_CoS,ou=${service_account_ou},${base}
changetype: add
objectClass: ldapsubentry
objectClass: cosSuperDefinition
objectClass: cosPointerDefinition
objectClass: top
costemplatedn: cn="cn=nsPwTemplateEntry,ou=${service_account_ou},${base}",cn=nsPwPolicyContainer,ou=${service_account_ou},${base}
cosAttribute: pwdpolicysubentry default operational default
cn: nsPwpolicy_CoS

EOF
fi  # end if verify_pwpointer"

if [[ "$?" != 0 ]]; then
  echo "ERROR: Operation failure"
  exit 255
fi

# ---------- Add or set passwordIsGlobalPolicy to   ----------#
# ---------- replicate lockout between ldap servers ----------#

if [ $(ldapsearch -x -ZZ -LLL -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y/root/.ldapj -b cn=config cn=config passwordisglobalpolicy | grep -c passwordisglobal                                                                              policy) -le 1 ]; then
# found passworddisglobalpolicy entry
  actionType=replace
else
  actionType=add
fi

echo "dn: cn=config
changetype:modify
${actionType}: passwordIsGlobalPolicy
passwordIsGlobalPolicy: on" | ${ECHO} ldapmodify -x -ZZ -h ${supplier_fqdn} -p 389 -D "${rootDN}" -y /root/.ldapj

if [[ ! "$?" == 0 ]]; then
  echo "ERROR: operation failed"
  exit 255
fi

exit 0
