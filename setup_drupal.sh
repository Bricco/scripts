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

if [ ${#@} -ne 2 ]; then
  usage;
fi

MODE=$1
SITE_NAME=$2
MODULE_LIST="ctools features field_group field_collection pathauto views"

MYSQL_DIR=/var/lib/mysql
APACHE_CREDENTIALS="www-data:www-data"
APACHE_CMD=apache2ctl
APACHE_VHOSTS_DIR=/etc/apache2/sites-enabled

if [ "$(uname)" == "Darwin" ]; then
  MYSQL_DIR=/usr/local/mysql/data
  APACHE_CREDENTIALS="_www:_www"
  APACHE_CMD=apachectl
  APACHE_VHOSTS_DIR=/etc/apache2/other
fi

function mysql_user_str {
    read -sp "Enter your MySQL password (ENTER for none): " mysqlRootPassword
    if [ -n "$mysqlRootPassword" ]; then
      while ! mysql -u root -p$mysqlRootPassword  -e ";" ; do
        read -p "Can't connect, please retry: " mysqlRootPassword
      done
      echo "-u root -p$mysqlRootPassword"
    else
      echo "-u root"
    fi
}

function install {

    if [ -d $SITE_NAME ]; then
        echo "Dir \"$SITE_NAME\" already exists"
        exit
    fi

    if [ ! -d $MYSQL_DIR/$SITE_NAME ]; then
        echo "Creating database $SITE_NAME"
        mysql_user_str=$(mysql_user_str)
        echo $mysql_user_str
        mysql $mysql_user_str -e "create database $SITE_NAME character set utf8 collate utf8_swedish_ci"
        mysql $mysql_user_str -e "grant all on $SITE_NAME.* to '$SITE_NAME'@'localhost' identified by 'secret'"
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
    echo "Generating make file $SITE_NAME.make"
    drush generate-makefile > $SITE_NAME.make
    
    cd ..
    chmod -R g+w $SITE_NAME
    sudo chown -R $APACHE_CREDENTIALS $SITE_NAME

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
        echo $mysql_user_str
        mysqladmin $mysql_user_str -f drop $SITE_NAME
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

# main program switch
case "$MODE" in
    install) install
    ;;
    uninstall) uninstall
    ;;
    *) usage
    ;;
esac


exit
