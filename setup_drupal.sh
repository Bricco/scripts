#!/bin/bash
#
# Drupal install and uninstall script
#
# @author stefan.norman@bricco.se

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
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

function mysql_user_str {
    read -sp "Enter your MySQL password (ENTER for none): " sqlpasswd
    if [ -n "$sqlpasswd" ]; then
      mysql_user_str="-u root -p$sqlpasswd"
    else
      mysql_user_str="-u root"
    fi
}

function install {

    if [ -d $SITE_NAME ]; then
        echo "Dir \"$SITE_NAME\" already exists"
        exit
    fi

    if [ ! -d /var/lib/mysql/$SITE_NAME ]; then
        echo "Creating database $SITE_NAME"
        mysql_user_str=$(mysql_user_str)
        echo $mysql_user_str
        mysqladmin $mysql_user_str create $SITE_NAME
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
    chown -R www-data:www-data $SITE_NAME

    if [ ! -f /etc/apache2/sites-enabled/$SITE_NAME.conf ]; then
      DRUPAL_DIR="`pwd`/$SITE_NAME"
      echo "Adding virtual host to Apache"
      echo "<VirtualHost *:80>
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
      </VirtualHost>" > /etc/apache2/sites-enabled/$SITE_NAME.conf

      echo "Restarting Apache"
      apache2ctl restart
    fi

    if [ $(grep -c "dev.$SITE_NAME.se" /etc/hosts) -eq 0 ]; then
        echo "Adding dev.$SITE_NAME.se to hosts-file"
        echo "127.0.0.1 dev.$SITE_NAME.se" >> /etc/hosts
    fi
}

function uninstall {

    if [ ! -d $SITE_NAME ]; then
        echo "Dir \"$SITE_NAME\" doesn't exists"
        echo "Please change directory"
        exit
    fi
    
    if [ -d /var/lib/mysql/$SITE_NAME ]; then
        echo "Dropping database $SITE_NAME"
        mysql_user_str=$(mysql_user_str)
        echo $mysql_user_str
        mysqladmin $mysql_user_str -f drop $SITE_NAME
    fi
    
    DRUPAL_DIR="`pwd`/$SITE_NAME"
    rm -rf $DRUPAL_DIR
    
    if [ -f /etc/apache2/sites-enabled/$SITE_NAME.conf ]; then
      echo "Removing virtual host from Apache"
      rm -f /etc/apache2/sites-enabled/$SITE_NAME.conf
    fi

    echo "Restarting Apache"
    apache2ctl restart

    if [ $(grep -c "dev.$SITE_NAME.se" /etc/hosts) -gt 0 ]; then
        echo "Removing dev.$SITE_NAME.se from hosts-file"
        grep -v "127.0.0.1 dev.$SITE_NAME.se" /etc/hosts > /tmp/hosts
        mv /tmp/hosts /etc/hosts
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
