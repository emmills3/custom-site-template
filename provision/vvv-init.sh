Skip to content
Search or jump to…

Pull requests
Issues
Marketplace
Explore
 
@emmills3 
0
0121emmills3/custom-site-template
forked from 0aveRyan/custom-site-template
 Code Pull requests 0 Projects 0 Security Insights Settings
custom-site-template/provision/vvv-init.sh
@emmills3 emmills3 Update vvv-init.sh
0aaad7c 10 minutes ago
@emmills3@LoreleiAurora@tomjn@widoz
106 lines (86 sloc)  3.8 KB
  
#!/usr/bin/env bash
# Provision WordPress Stable

# Declare our default vars
WP_REPO=`get_config_value 'wp_repo' ''`
PARENT_THEME_REPO=`get_config_value 'parent_theme_repo' ''`
CHILD_THEME_REPO=`get_config_value 'child_theme_repo' ''`
CHILD_THEME_NAME=`get_config_value 'child_theme_name' 'child-theme'`

echo "BK1"
echo "${WP_REPO}"
echo "${PARENT_THEME_REPO}"
echo "${CHILD_THEME_REPO}"
echo "BK2"

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
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

# MY INTERRUPT
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then

  if [ ${WP_REPO} ]; then
    echo "Downloading Custom WordPress..."
    git clone ${WP_REPO} ${VVV_PATH_TO_SITE}/public_html

    if [ ${PARENT_THEME_REPO} ]; then
      echo "Downloading Parent Theme..."
      git clone ${PARENT_THEME_REPO} ${VVV_PATH_TO_SITE}/public_html/wp-content/
    fi

    if [ ${CHILD_THEME_REPO} ]; then
      echo "Downloading Child Theme..."
      git clone ${CHILD_THEME_REPO} ${VVV_PATH_TO_SITE}/public_html/wp-content/themes/${CHILD_THEME_NAME}
    fi

  else 
    echo "Downloading WordPress..."
    noroot wp core download --version="${WP_VERSION}"  
  fi

fi

# Install and configure the latest stable version of WordPress
# if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then
#     echo "Downloading WordPress..."
#     # noroot wp core download --version="${WP_VERSION}"
#     noroot wp core download --version="${WP_VERSION}"
# fi

if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-config.php" ]]; then
  echo "Configuring WordPress Stable..."
  noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
define( 'SCRIPT_DEBUG', true );
PHP
fi

if ! $(noroot wp core is-installed); then
  echo "Installing WordPress Stable..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.test" --admin_password="password"

else
  echo "Updating WordPress Stable..."
  cd ${VVV_PATH_TO_SITE}/public_html
  noroot wp core update --version="${WP_VERSION}"
fi

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

if [ -n "$(type -t is_utility_installed)" ] && [ "$(type -t is_utility_installed)" = function ] && `is_utility_installed core tls-ca`; then
    sed -i "s#{{TLS_CERT}}#ssl_certificate /vagrant/certificates/${VVV_SITE_NAME}/dev.crt;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}#ssl_certificate_key /vagrant/certificates/${VVV_SITE_NAME}/dev.key;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
    sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi
