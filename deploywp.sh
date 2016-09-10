#!/bin/bash

# ================================================================================
# deploywp.sh
#
# Deploys WordPress on a subdomain on a standard cPanel account.
#
# Author:      James M. Joyce, Flashpoint CS <james@flashpointcs.net>
# Author URI:  http://www.flashpointcs.net
# Github:      https://github.com/FPCSJames/deploywp
# Version:     1.0
#
# Copyright (c) 2016 Flashpoint Computer Services, LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# ================================================================================

# Config

basedir="/"
cpaneluser="someacct"
#cpanelpass="somepass"
cpanelurl="https://127.0.0.1:2083"
rootdomain="example.com"
#nobanner=1

# WP prefs

filestoremove="readme.html
license.txt
wp-content/plugins/akismet
wp-content/plugins/hello.php"

pluginstoadd="better-wp-security
imsanity
ewww-image-optimizer
authy-two-factor-authentication
wordpress-seo
so-clean-up-wp-seo
wp-security-audit-log"

themetokeep="twentysixteen"

# WP-CLI

havewpcli=1
adminemail="example@example.com"
timezone="America/Chicago"
commentstatus="closed"
pingstatus="closed"
permalinks="/%year%/%monthnum%/%postname%/"

# Custom functions

customplugins() {
   wget --quiet https://github.com/szepeviktor/fix-w3tc/archive/master.zip >/dev/null 2>&1
   unzip master.zip
   rm master.zip
   mv fix-w3tc-master w3-total-cache
   wget --quiet https://github.com/FPCSJames/wp-anti-detritus/archive/master.zip >/dev/null 2>&1
   unzip master.zip
   rm master.zip
   mv wp-anti-detritus-master wp-anti-detritus
   rm master.zip.1
}

#### Stop editing here unless you know what you're doing ####

# Action functions

deleteunwanted() {
   for filename in $filestoremove; do
      rm -rf $filename
   done
}

getplugins() {
   cd wp-content/plugins
   for pluginName in $pluginstoadd; do
      wget --quiet https://downloads.wordpress.org/plugin/$pluginName.zip >/dev/null 2>&1
      unzip $pluginName.zip
      rm $pluginName.zip
   done
   cd .. && mkdir -p mu-plugins && cd mu-plugins
   wget --quiet https://raw.githubusercontent.com/roots/wp-password-bcrypt/master/wp-password-bcrypt.php >/dev/null 2>&1
   cd ../plugins
   customplugins
   cd ../..
}

removethemes() {
   cd wp-content/themes
   find . -maxdepth 1 -type d  -not -name "$themetokeep" -not -name "." -not -name ".." | xargs rm -r
   cd ../..
}

setperms() {
   find . -type d -exec chmod 0755 {} \;
   find . -type f -exec chmod 0644 {} \;
}

setupconfig() {
   local prefix="$(cat /dev/urandom | tr -dc 'a-z' | fold -w 7 | head -n 1)_"
   local salt=$(curl -L https://api.wordpress.org/secret-key/1.1/salt/)
   local replace="put your unique phrase here" # do not change this, it's what we're replacing in wp-config.php
   mv wp-config-sample.php wp-config.php
   sed -i "s/database_name_here/"$cpaneluser"_"$dbname"/" wp-config.php
   sed -i "s/username_here/"$cpaneluser"_"$dbuser"/" wp-config.php
   sed -i "s/password_here/$dbpass/" wp-config.php
   sed -i "s/wp_/$prefix/" wp-config.php
   printf '%s\n' "g/$replace/d" a "$salt" . w | ed -s wp-config.php
}

wpclear() {
   # Thanks http://lowermedia.net/petes-evergrowing-wp-cli-reference-cheat-sheet/
   wp post delete $(wp post list --post_type='page' --format=ids)
   wp post delete $(wp post list --post_type='post' --format=ids)
   wp widget delete $(wp widget list sidebar-1 --format=ids);
}

wpoptions() {
   wp option update blogdescription ""
   wp option update start_of_week 0
   wp option update default_comment_status $commentstatus
   wp option update default_ping_status $pingstatus
   wp option update use_trackback 0
   wp option update timezone_string $timezone
   wp rewrite structure $permalinks --hard
}

# Utility functions

getvalue() {
   local val
   while [[ -z "$val" ]]; do
      read $2 -p "$1" val
   done
   echo $val
}

spinner() {
   local i=1
   local sp="/-\|"
   local result
   echo -ne $1
   echo -n '  '
   set +e
   while sleep 0.05; do
       printf "\b${sp:i++%${#sp}:1}"
   done &
   $(eval $2 &>/dev/null)
   result=$?
   kill -13 $!
   set -e
   if [ $result -eq 0 ]; then
      echo -ne "\bDone!\n"
   else
      echo -ne "\bFailed! Aborting.\n"
      return 1
   fi
}

# Initalization and banner display

curr=`pwd`
dwpdir="$( cd "$(dirname "$0")" ; pwd -P )" # See http://goo.gl/U4VXCF
cd $curr
set -e
set -o pipefail
clear

if [ -z "$nobanner" ]; then
   echo "=================================================="
   echo "                   deploywp.sh                    "
   echo "    by James M. Joyce <james@flashpointcs.net>    "
   echo "        Flashpoint Computer Services, LLC         "
   echo -e "==================================================\n"
fi

if [ -z "$cpanelpass" ]; then
   cpanelpass=`getvalue "Enter cPanel password: " -s`
fi

subdomain=`getvalue "Enter subdomain name: "`
dbname=`getvalue "Enter DB name: "`
dbuser=`getvalue "Enter DB username: "`
dbpass=`getvalue "Enter DB password: " -s`

echo -e "\n"

spinner "Creating subdomain..." "php $dwpdir/cpanel.php 'sub' $cpanelurl $cpaneluser $cpanelpass $rootdomain $subdomain"
spinner "Creating database..." "php $dwpdir/cpanel.php 'db' $cpanelurl $cpaneluser $cpanelpass $dbname"
spinner "Creating DB user..." "php $dwpdir/cpanel.php 'dbuser' $cpanelurl $cpaneluser $cpanelpass $dbuser $dbpass"
spinner "Associating user with DB..." "php $dwpdir/cpanel.php 'dbperms' $cpanelurl $cpaneluser $cpanelpass $dbuser $dbname"

echo ""

cd ~/"$subdomain.$rootdomain"
spinner "Downloading WordPress..." "curl -s -f https://wordpress.org/latest.tar.gz | tar -xz --strip-components=1"
spinner "Removing unwanted files/directories..." "deleteunwanted"
spinner "Downloading and unpacking plugins..." "getplugins"
spinner "Setting wp-config.php values..." "setupconfig"
spinner "Removing stock themes..." "removethemes"
spinner "Setting permissions..." "setperms"

if [ "$havewpcli" -eq "1" ]; then
   echo -ne "\n"
   adminuser=`getvalue "Enter initial user's username: "`
   adminpass=`getvalue "Enter intiial user's password: " -s`
   echo ""
   if [ -z "$adminemail" ]; then
      adminemail=`getvalue "Enter initial user's email: "`
   fi
   sitetitle=`getvalue "Enter site title: "`

   echo ""

   spinner "Running WP installer..." "wp core install --url=$subdomain.$rootdomain --title=$sitetitle --admin_user=$adminuser --admin_password=$adminpass --admin_email=$adminemail --skip-email"
   spinner "Setting WP options..." "wpoptions"
   spinner "Removing default WP content..." "wpclear"

   echo ""
fi

echo "**** Complete! Go set up SSL in cPanel. ****"
echo ""