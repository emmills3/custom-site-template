#!/usr/bin/env bash
# Provision WordPress Stable

echo "Custom provisioner for AF sites"

# Declare our default vars
WP_REPO=`get_config_value 'wp_repo' ''`
PARENT_THEME_REPO=`get_config_value 'parent_theme_repo' ''`
CHILD_THEME_REPO=`get_config_value 'child_theme_repo' ''`
CHILD_THEME_NAME=`get_config_value 'child_theme_name' 'child-theme'`

# Fetch the first host as the primary domain. If none is available, generate a default using the site name
DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WP_TYPE=`get_config_value 'wp_type' "single"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}

# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
echo -e "\nGranting the wp user priviledges to the '${DB_NAME}' database"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

echo "Setting up the log subfolder for Nginx logs"
noroot mkdir -p ${VVV_PATH_TO_SITE}/log
noroot touch ${VVV_PATH_TO_SITE}/log/nginx-error.log
noroot touch ${VVV_PATH_TO_SITE}/log/nginx-access.log

if [ "${WP_TYPE}" != "none" ]; then

  # Install and configure the AF forked WP, else latest stable version of WordPress
  if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then

    if [ ${WP_REPO} ]; then
      echo "Downloading Custom WordPress..."
      noroot git clone ${WP_REPO} ${VVV_PATH_TO_SITE}/public_html

      if [ ${PARENT_THEME_REPO} ]; then
        echo "Downloading Parent Theme..."
        noroot git clone ${PARENT_THEME_REPO} ${VVV_PATH_TO_SITE}/public_html/wp-content/
      fi

      if [ ${CHILD_THEME_REPO} ]; then
        echo "Downloading Child Theme..."
        noroot git clone ${CHILD_THEME_REPO} ${VVV_PATH_TO_SITE}/public_html/wp-content/themes/${CHILD_THEME_NAME}
      fi

    else 
      echo "Downloading WordPress..."
      noroot wp core download --version="${WP_VERSION}"  
    fi
  fi

  if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-config.php" ]]; then
    echo "Configuring WordPress Stable..."
    noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet
  fi

  if ! $(noroot wp core is-installed); then
    echo "Installing WordPress Stable..."

    if [ "${WP_TYPE}" = "subdomain" ]; then
      echo "Using multisite subdomain type install"
      INSTALL_COMMAND="multisite-install --subdomains"
    elif [ "${WP_TYPE}" = "subdirectory" ]; then
      echo "Using a multisite install"
      INSTALL_COMMAND="multisite-install"
    else
      echo "Using a single site install"
      INSTALL_COMMAND="install"
    fi

    noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.test" --admin_password="password"
    echo "WordPress was installed, with the username 'admin', and the password 'password' at admin@local.test"
    
    DELETE_DEFAULT_PLUGINS=`get_config_value 'delete_default_plugins' ''`
    if [ ! -z "${DELETE_DEFAULT_PLUGINS}" ]; then
        noroot wp plugin delete akismet
        noroot wp plugin delete hello
    fi
  else
    echo "Updating WordPress Stable..."
    cd ${VVV_PATH_TO_SITE}/public_html
    noroot wp core update --version="${WP_VERSION}"
  fi
else
  echo "wp_type was set to none, provisioning WP was skipped, moving to Nginx configs"
fi

echo "Copying the sites Nginx config template ( fork this site template to customise the template )"
cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

if [ -n "$(type -t is_utility_installed)" ] && [ "$(type -t is_utility_installed)" = function ] && `is_utility_installed core tls-ca`; then
  echo "Inserting the SSL key locations into the sites Nginx config"
  VVV_CERT_DIR="/srv/certificates"
  # On VVV 2.x we don't have a /srv/certificates mount, so switch to /vagrant/certificates
  codename=$(lsb_release --codename | cut -f2)
  if [[ $codename == "trusty" ]]; then # VVV 2 uses Ubuntu 14 LTS trusty
    VVV_CERT_DIR="/vagrant/certificates"
  fi
  sed -i "s#{{TLS_CERT}}#ssl_certificate ${VVV_CERT_DIR}/${VVV_SITE_NAME}/dev.crt;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  sed -i "s#{{TLS_KEY}}#ssl_certificate_key ${VVV_CERT_DIR}/${VVV_SITE_NAME}/dev.key;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
    sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi

noroot wp config set WP_SITEURL "https://${DOMAIN}"
noroot wp config set WP_HOME "https://${DOMAIN}"
noroot wp config set WP_DEBUG true --raw
noroot wp config set FS_METHOD "direct"
noroot wp config set FS_CHMOD_DIR 0775 --raw
noroot wp config set FS_CHMOD_FILE 0664 --raw

# Below not working as expected
get_config_value 'wpconfig_constants' |
echo "constants2"
  while IFS='' read -r -d '' key &&
        IFS='' read -r -d '' value; do
      echo "${key}"
      echo "${value}"
      noroot wp config set "${key}" "${value}" --raw
  done
  
WP_PLUGINS=`get_config_value 'install_plugins' ''`
if [ ! -z "${WP_PLUGINS}" ]; then
    for plugin in ${WP_PLUGINS//- /$'\n'}; do 
        noroot wp plugin install "${plugin}" --activate
    done
fi

WP_LOCALE=`get_config_value 'locale' ''`
if [ ! -z "${WP_LOCALE}" ]; then
    noroot wp language core install "${WP_LOCALE}" 2>/dev/null 
    noroot wp site switch-language "${WP_LOCALE}" 2>/dev/null 
fi

echo "Site Template provisioner script completed"
