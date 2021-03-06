#!/bin/bash
#
# Drupal install and uninstall script
#
# @author stefan.norman@bricco.se

# Make sure no root user running
if [[ $EUID -eq 0 ]]; then
   echo "This script must should NOT be run as root" 1>&2
   exit 1
fi

function usage {
    echo "Usage: $0 install|uninstall sitename"
    exit 1
}

if [[ ${#@} -ne 2 &&  "$1" != "upgrade" ]]; then
  usage;
fi



MODE=$1
SITE_NAME=$2
MODULE_LIST="ctools features strongarm field_group field_collection pathauto views admin_menu devel module_filter"
MODULE_DISABLE="toolbar"
MODULE_ENABLE="admin_menu_toolbar views_ui"

MYSQL_DIR=/var/lib/mysql
APACHE_CMD=apache2ctl
APACHE_VHOSTS_DIR=/etc/apache2/sites-enabled
if [ -f /etc/apache2/envvars ]; then
  APACHE_USER=$(grep APACHE_RUN_USER /etc/apache2/envvars | sed -e "s/export APACHE_RUN_USER=//g")
  APACHE_GROUP=$(grep APACHE_RUN_GROUP /etc/apache2/envvars | sed -e "s/export APACHE_RUN_GROUP=//g")
else
  APACHE_USER=$(grep ^User /etc/apache2/httpd.conf | sed -e "s/User //g")
  APACHE_GROUP=$(grep ^Group /etc/apache2/httpd.conf | sed -e "s/Group //g")
fi

if [ "$(uname)" == "Darwin" ]; then
  MYSQL_DIR=/usr/local/mysql/data
  APACHE_CMD=apachectl
  APACHE_VHOSTS_DIR=/etc/apache2/other
fi

function mysql_user_str {
    read -sp "Enter your MySQL password (ENTER for none): " mysqlRootPassword
    while ! mysql -u root --password="$mysqlRootPassword"  -e ";" ; do
      read -p "Can't connect, please retry: " mysqlRootPassword
    done
    echo $mysqlRootPassword
}

function install {

    if [ -d $SITE_NAME ]; then
        echo "Dir \"$SITE_NAME\" already exists"
        exit
    fi

    if [ ! -d $MYSQL_DIR/$SITE_NAME ]; then
        echo "Creating database $SITE_NAME"
        mysql_user_str=$(mysql_user_str)
        mysql -u root --password="$mysql_user_str" -e "create database $SITE_NAME character set utf8 collate utf8_swedish_ci"
        mysql -u root --password="$mysql_user_str" -e "grant all on $SITE_NAME.* to '$SITE_NAME'@'localhost' identified by 'secret'"
    fi

    echo "Downloading Drupal..."
    drush dl drupal-7.x
    mv drupal-7.x-dev $SITE_NAME
    cd $SITE_NAME

    echo "Installing Drupal..."
    drush site-install standard --account-name=admin --account-pass=admin --db-url=mysql://$SITE_NAME:secret@localhost/$SITE_NAME --site-name=$SITE_NAME -y

    for MODULE in $MODULE_LIST
    do
        echo "Installing module $MODULE..."
        drush dl $MODULE
        drush en $MODULE -y
    done
    
    for MODULE in $MODULE_ENABLE
    do
        echo "Installing module $MODULE..."
        drush en $MODULE -y
    done
    
    for MODULE in $MODULE_DISABLE
    do
        echo "Disable module $MODULE..."
        drush dis $MODULE -y
    done
    
    echo "Generating make file $SITE_NAME.make"
    drush generate-makefile > $SITE_NAME.make
    
    cd ..
    chmod -R g+w $SITE_NAME
    sudo chown -R $APACHE_USER:$APACHE_GROUP $SITE_NAME

    if [ ! -f $APACHE_VHOSTS_DIR/$SITE_NAME.conf ]; then
      DRUPAL_DIR="`pwd`/$SITE_NAME"
      echo "Adding virtual host to Apache"
      echo -e "<VirtualHost *:80>
      ServerName dev.$SITE_NAME.se

      DocumentRoot $DRUPAL_DIR
      <Directory />
        Options FollowSymLinks
        AllowOverride All
      </Directory>
      <Directory $DRUPAL_DIR>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order allow,deny
        allow from all
      </Directory>
      </VirtualHost>" | sudo tee $APACHE_VHOSTS_DIR/$SITE_NAME.conf

      echo "Restarting Apache"
      sudo $APACHE_CMD restart
    fi

    if [ $(grep -c "dev.$SITE_NAME.se" /etc/hosts) -eq 0 ]; then
        echo "Adding dev.$SITE_NAME.se to hosts-file"
        echo -e "127.0.0.1 dev.$SITE_NAME.se" | sudo tee -a /etc/hosts
    fi
}

function uninstall {

    if [ ! -d $SITE_NAME ]; then
        echo "Dir \"$SITE_NAME\" doesn't exists"
        echo "Please change directory"
        exit
    fi
    
    if [ -d $MYSQL_DIR/$SITE_NAME ]; then
        echo "Dropping database $SITE_NAME"
        mysql_user_str=$(mysql_user_str)
        mysql -u root --password="$mysql_user_str" -e "drop database $SITE_NAME"
    fi
    
    DRUPAL_DIR="`pwd`/$SITE_NAME"
    sudo rm -rf $DRUPAL_DIR
    
    if [ -f $APACHE_VHOSTS_DIR/$SITE_NAME.conf ]; then
      echo "Removing virtual host from Apache"
      sudo rm -f $APACHE_VHOSTS_DIR/$SITE_NAME.conf
    fi

    echo "Restarting Apache"
    sudo $APACHE_CMD restart

    if [ $(grep -c "dev.$SITE_NAME.se" /etc/hosts) -gt 0 ]; then
        echo "Removing dev.$SITE_NAME.se from hosts-file"
        grep -v "127.0.0.1 dev.$SITE_NAME.se" /etc/hosts > /tmp/hosts
        sudo mv /tmp/hosts /etc/hosts
    fi
}

function upgrade {

        BASEDIR=$(dirname $0)

        echo "Upgrading $BASEDIR/setup_drupal.sh to the latest version..."
        cd /tmp
        sudo wget -q https://raw.githubusercontent.com/Bricco/scripts/master/setup_drupal.sh
        sudo mv /tmp/setup_drupal.sh $BASEDIR
        sudo chmod +x $BASEDIR/setup_drupal.sh
        cd -
}

# main program switch
case "$MODE" in
    install) install
    ;;
    uninstall) uninstall
    ;;
    upgrade) upgrade
    ;;

    *) usage
    ;;
esac
