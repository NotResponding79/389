#!/bin/bash
# description: script sets POSIX attributes on users replicated from AD.
# NOTE: do not cut-n-paste this script. It contains a "here-file" for the ldapmodify
# command that requires leading tabs to work correctly.

# History:
# version=1.0c
# work in progress...
# version=1.1
# Added Tenant users for sftponly accounts
verion=1.2
# Fixed for case of mounting home dir by hostname not IP
# Added /etc/skel files to home dir

trap "abort" 1 2 3 6

BANG='!'
defaultLoginShell='/bin/bash'
gidNumberInfra=1000
gidNumberTenant=100
homeBase='/home/mnt'
homeDirPerm=750
ldapAuth='/root/.ldapj'
ldapBindDN='cn=directory manager'
reqMntHome='/home/mnt'
#reqMntHomeValue='[0-9]\.[0-9]*.17:/home/mnt'
scriptName="$(basename $0)"
uidNumberRangeLowInfra=20000
uidNumberRangeHighInfra=21000
uidNumberRangeLowTenant=30000
uidNumberRangeHighTenant=31000

UFC='s70'
ldapHost="$(hostname -f)"
ldapEntrydn='*ou=personnel,ou=infrastructure,ou=Accounts*'
ldapGroup="ou=${UFC}-posix,ou=security_groups,ou=infrastructure,ou=Accounts,dc=${UFC},dc=vmis,dc=nro,dc=mil"

# variables used as commands
ldapMod="ldapmodify -x -ZZ -h ${ldapHost} -D \"${ldapBindDN}\" -y ${ldapAuth} "
ldapModDryRun="printf '\n dryRun -- Command that would run: \n\tldapmodify -x -ZZ -h ${ldapHost} -D \"${ldapBindDN}\" -y ${ldapAuth} \n\t with input:\n'; cat "
makeDir="mkdir"
makeDirDryRun='echo "would create" '

abort() {
# $1 is abort reason text string in a format acceptable to printf

  local abortReason
  abortReason="${1:-"reason unspecified"}"

  printf "ABORTED: ${abortReason}\n"
  logger -s -t ${scriptName} "ABORTED: ${abortReason}"

  exit 99
}

addUserPosix() {
# update the user entry to add posix attributes
# other variables should be global: ${ldapHost}, ${ldapBindDN}, ${ldapAuth}

  local uid uidNumber gidNumber homeDirectory loginShell userDN
  uid=$1
  uidNumber=$2
  gidNumber=$3
  homeDirectory=$4
  loginShell=$5
  userDN="$(ldapsearch -o ldif-wrap=no -x -LLL -ZZ -h ${ldapHost} -D "${ldapBindDN}" -y ${ldapAuth} uid=${uid} dn)"

  [[ "${userDN}" =~ 'ou=service_accounts' ]] && loginShell='/sbin/nologin'

  printf "$(date)  -- " # put date in output log

  eval ${ldapMod} <<-EOEntry
        ${userDN}
        changetype: modify
        add: objectClass
        objectClass: posixAccount
        -
        add: uidNumber
        uidNumber: ${uidNumber}
        -
        add: gidNumber
        gidNumber: ${gidNumber}
        -
        add: homeDirectory
        homeDirectory: ${homeDirectory}
        -
        add: loginShell
        loginShell: ${loginShell}
        -
EOEntry

# check return code from ldapmodify
  returnValue=$?
  if [ "${returnValue}" -gt 0 ]; then
    abort " command: ${ldapMod}\n\t for - ${userDN}...\n got return code of ${returnValue} in $FUNCNAME."
  fi
}

getNeedyInfraUserList() {
# users who need posix attributes
  ldapsearch -o ldif-wrap=no -x -LLL -ZZ -h ${ldapHost} -D "${ldapBindDN}" -y ${ldapAuth} \
    "(&(uid=*)(${BANG}(objectclass=posixaccount)))" uid | grep -i "^uid" | cut -f2- -d" " | sort
}

getNeedySftponlyUserList() {
# sftponly group members who are in the tenent users needing posix attributes
# get list of sftponly members who are tenent users
  ldapsearch -o ldif-wrap=no -x -LLL -ZZ -h ${ldapHost} -D "${ldapBindDN}" -y ${ldapAuth} \
    "(&(cn=sftponly)(objectclass=groupofuniquenames))" | egrep ",ou=tenant_users," | cut -f2- -d" " | \
    while read user; do
#check each user to see if they need posix attributes
      ldapsearch -o ldif-wrap=no -x -LLL -ZZ -h ${ldapHost} -b "${user}" -D "${ldapBindDN}" -y ${ldapAuth} \
        "(${BANG}(objectclass=posixaccount))" uid | grep -i "^uid" | cut -f2 -d" "
    done
}

getOpenUidNumberInfra() {
# just keeping it simple. Get next available number above the highest number in the range
# $1 is the variable name to return the next open uidNumber in

  local returnVarName
  returnVarName=$1
  highUidNumber=$(ldapsearch -o ldif-wrap=no -x -LLL -ZZ -h ${ldapHost} -D "${ldapBindDN}" -y ${ldapAuth} \
    "(&(uidNumber>=${uidNumberRangeLowInfra})(uidNumber<=${uidNumberRangeHighInfra}))" \
    uidnumber | grep -i "uidNumber:" | awk '{print $2}' | sort -rn | head -1)

  nextUidNumber=$((${highUidNumber:-${uidNumberRangeLowInfra}}+1))

echo "nextUidNumber == ${nextUidNumber}"

  if ! [ "${nextUidNumber}" -gt ${uidNumberRangeLowInfra} -a "${nextUidNumber}" -lt ${uidNumberRangeHighInfra} ]; then
# we were not between the low and high uidNumbers allowed
    abort "failed to find an acceptable uidnumber between ${uidNumberRangeLowInfra} and ${uidNumberRangeHighInfra}"
  fi

  export ${returnVarName}=${nextUidNumber}
}

getOpenUidNumberTenant() {
# just keep it simple. Get next available number above the highest number in the range
# $1 is the variable name to return the next open uidNumber in

  local returnVarName
  returnVarName=$1
  highUidNumber=$(ldapsearch -o ldif-wrap=no -x -LLL -ZZ -h ${ldapHost} -D "${ldapBindDN}" -y ${ldapAuth} \
    "(&(uidNumber>=${uidNumberRangeLowTenant}) (uidNumber<=${uidNumberRangeHighTenant}))" \
    uidnumber | grep -i "uidNumber:" | awk '{print $2}' | sort -rn | head -1)

  nextUidNumber=$((${highUidNumber:-${uidNumberRangeLowTenant}}+1))

  if ! [ "${nextUidNumber}" -gt ${uidNumberRangeLowTenant} -a "${nextUidNumber}" -1t ${uidNumberRangeHighTenant} ]; then
# we were not between the low and high uidNumbers allowed
    abort "failed to find an acceptable uidNumber between ${uidNuameRangeLowTenant} and ${uidNumberRangeHighTenant}"
  fi

  export ${returnVarName}=${nextUidNumnber}
}

homeMounted() {
# if the home dir mount is mounted return success, otherwise return fail
#  if [ $(df -h ${reqMntHome} 2> /dev/null | grep -q "${reqMntHomeValue}") ]; then
  if ! [ $(mount | grep -i nfs | grep -q ${reqMntHome}) ]; then
    return 0
  else
    printf "NOTICE: cannot process ${user} at this time, need ${reqMntHome} mounted.\n"
    return 1
  fi
}

makeHome() {
  if homeMounted; then
    if [ -d "${homeBase}/${user}" ]; then
      printf "NOTICE: User's home directory already exists.  (${homeBase}/${user})\n"
    else
      eval ${makeDir} ${homeBase}/${user}
    fi
    if [ -d "${homeBase}/${user}" ]; then
      chmod ${homeDirPerm} ${homeBase}/${user}
      cp -R /etc/skel/.??* ${homeBase}/${user}
    fi
  fi
}

#-------------------------------------------------------------------------------------------------------------
#          MAIN
#-------------------------------------------------------------------------------------------------------------
# other variable should be global: ${uidNumber} $gidNumberInfra ${gidNumberTenant} ${homeDirectory} $defaultLogShell}
# comment next tow lines to run "live" or uncommment to make dry-run
#ldapMod=${ldapModDryRun}
#makeDir=${makeDirDryRun}

# process infranstructer users
for user in $(getNeedyInfraUserList); do
# get next open uidNumber and put it in varible uidNumber
  getOpenUidNumberInfra uidNumber
  homeDirectory="${homeBase}/${user}"

  printf "Adding POSIX Attributes for ${user} uidNumber=${uidNumber} gidNumber=${gidNumberInfra} homeDir=${homeDirectory} loginShell=${defaultLoginShell}\n"

# only if you can create the home directory then add posixx attriutes in ldap...
# this way we will to the job all at once, or not at all
  if makeHome; then
    addUserPosix ${user} ${uidNumber} ${gidNumberInfra} ${homeDirectory} ${defaultLoginShell}
    chown ${user}:1000 ${homeDirectory}
  else
    printf "NOTICE: unable to create users home directory. \n"
  fi
done

# process tenant user in sftponly group (this group will only be on sites with NetBackup and DMF)
# only adding posix attributes are handled in this script...the hone directory needs
# to be created on the DMF host (mfcbckg04 or mfcbckg05)
homeBase='/tier1/home'
defaultLoginShell='/bin/false'
for user in $(getNeedySftponlyUserList); do
# get next open uidNumber and put it in variable uidNumber
  getOpenUidNumberTenant uidNumber
  homeDirectory="${homeBase}/${user}"

 printf "Adding POSIX Attributes for ${user} uidNumber=${uidNumber} gidNumber=${gidNumberTenant} \
                homeDir=${homeDirectory} loginShell=${defaultLoginShell}\n"
  addUserPosix ${user} ${uidNumber} ${gidNumberTenant} ${homeDirectory} ${defaultLoginShell}
done

exit 0
