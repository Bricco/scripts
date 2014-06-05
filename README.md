scripts
=======

Nifty shell scripts that helps in everday work

## setup_drupal.sh
A script that is used for a quick install of a vanilla Drupal and some common modules. It has both install and uninstall capability.
What it does:
* Installs latest Drupal
* Installs some common modules
* Creates a drush make file
* Creates MySQL database and user grants
* Creates Apache virtual host
* Adds domain to local hosts file

**Installation**
As root, copy or download setup-drupal.sh to /usr/local/bin/ and chmod +x it.
```
cd /usr/local/bin
sudo wget https://raw.githubusercontent.com/Bricco/scripts/master/setup_drupal.sh
sudo chmod +x setup_drupal.sh
```

**Usage**
```
setup_drupal.sh install mycoolsite
```
