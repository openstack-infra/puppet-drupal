# Copyright 2013  OpenStack Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
# == Class: drupal
#
# A wrapper class to support drupal project integration based on LAMP
# environment.
#
# Actions:
# - Prepare apache vhost and create mysql database (optional)
# - Install Drush tool with Drush-dsd extension
# - Fetch distribution tarball from remote repository
# - Deploy dist tarball and setup Drupal from scratch or
#   upgrade an existing site.
#
# Site parameters:
# - site_name: name of the site (FQDN for example)
# - site_admin_password: password of drupal admin
# - site_docroot: root directory of drupal site
# - site_vhost_root: root directory of virtual hosts
# - site_create_database: if true, create a new database (default: false)
# - site_alias: drush site alias name
# - site_profile: installation profile to deploy
#
# SSL configuration:
# - site_ssl_enabled: true if ssl is enabled (default: false)
# - site_ssl_cert_file_contents: x509 certificate of vhost in pem format
# - site_ssl_key_file_contents: rsa key of x509 certificate in pem format
# - site_ssl_chain_file_contents: root ca's of site ssl cert
# - site_ssl_cert_file: file path of x509 certificate
# - site_ssl_key_file: file path of certificate rsa key
# - site_ssl_chain_file: file path of certificate chain
#
# Mysql connection:
# - mysql_user: mysql user of drupal site
# - mysql_password: password of site user
# - mysql_database: site database name
# - mysql_host: host of mysql server (default: localhost)
#
# Drupal configuration variables:
# - conf: contains the key-value pairs of settings.php
#
# Remarks:
# - the site lives in /srv/vhosts/{hostname}/slot0 or slot1 directory
# - the /srv/vhosts/{hostname}/w symlinks to slot0 or slot1 and
#   points to actual site root. The upgrade process will begin in
#   inactive slot so we can avoid typical WSOD issues with Drupal.
# - for temporary package/tarball download it is using the
#   /srv/downloads directory.
#

class drupal (
  $site_name = $::fqdn,
  $site_vhost_root = '/srv/vhosts',
  $site_root = undef,
  $site_docroot = undef,
  $site_mysql_host = 'localhost',
  $site_mysql_user = 'drupal',
  $site_mysql_password = undef,
  $site_mysql_database = 'drupal',
  $site_profile = 'standard',
  $site_admin_password = undef,
  $site_alias = undef,
  $site_create_database = false,
  $site_base_url = false,
  $site_file_owner = 'root',
  $site_ssl_enabled = false,
  $site_ssl_cert_file_contents = undef,
  $site_ssl_key_file_contents = undef,
  $site_ssl_chain_file_contents = undef,
  $site_ssl_cert_file = undef,
  $site_ssl_key_file = undef,
  $site_ssl_chain_file = undef,
  $package_repository = undef,
  $package_branch = undef,
  $conf = undef,
  $conf_markdown_directory = undef,
  $conf_ga_account = undef,
  $conf_openid_provider = undef,
) {
  include ::httpd
  include ::pear

  if $site_root == undef {
    $_site_root = "${site_vhost_root}/${site_name}"
  } else {
    $_site_root = $site_root
  }

  if $site_docroot == undef {
    $_site_docroot = "${_site_root}/w"
  } else {
    $_site_docroot = $site_docroot
  }

  # ssl certificates
  if $site_ssl_enabled == true {

    include ::httpd::ssl

    # site x509 certificate
    if $site_ssl_cert_file_contents != undef {
      file { $site_ssl_cert_file:
        owner   => 'root',
        group   => 'root',
        mode    => '0640',
        content => $site_ssl_cert_file_contents,
        before  => Httpd::Vhost[$site_name],
      }
    }

    # site ssl key
    if $site_ssl_key_file_contents != undef {
      file { $site_ssl_key_file:
        owner   => 'root',
        group   => 'root',
        mode    => '0640',
        content => $site_ssl_key_file_contents,
        before  => Httpd::Vhost[$site_name],
      }
    }

    # site ca certificates file
    if $site_ssl_chain_file_contents != undef {
      file { $site_ssl_chain_file:
        owner   => 'root',
        group   => 'root',
        mode    => '0640',
        content => $site_ssl_chain_file_contents,
        before  => Httpd::Vhost[$site_name],
      }
    }
  }

  # setup apache and virtualhosts, enable mod rewrite
  file { $site_vhost_root:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  ::httpd::vhost { $site_name:
    port     => 80,
    priority => '50',
    docroot  => $_site_docroot,
    require  => Exec['init-slot-dirs'],
    template => 'drupal/drupal.vhost.erb',
  }

  file { $_site_root:
    ensure  => directory,
    owner   => 'root',
    group   => 'www-data',
    mode    => '0755',
    require => Package['httpd'],
  }

  # Create initial symlink here to allow apache vhost creation
  # so drush dsd can flip this symlink between slot0/slot1
  # (won't be recreated until the symlink exists)
  exec { 'init-slot-dirs':
    command   => "/bin/ln -s ${_site_root}/slot1 ${_site_docroot}",
    unless    => "/usr/bin/test -L ${_site_docroot}",
    logoutput => 'on_failure',
    require   => File[$_site_root],
  }

  httpd_mod { 'rewrite':
    ensure => present,
  }

  # php packages
  $drupal_related_packages = [ 'unzip', 'php5-mysql', 'php5-gd', 'php5-cli',
    'libapache2-mod-php5' ]

  package { $drupal_related_packages:
    ensure  => 'installed',
    require => Package['httpd'],
    notify  => Service['httpd'],
  }

  # This directory is used to download and cache tarball releases
  # without proper upstream packages
  file { '/srv/downloads':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # setup drush and drush-dsd extension
  drush { 'drush':
    require => File['/srv/downloads'],
  }

  # site mysql database
  if $site_create_database == true {
    if $site_mysql_password == undef {
      fail('You must set $site_mysql_password when $site_create_database is true.')
    }
    mysql::db { $site_mysql_database:
      user     => $site_mysql_user,
      password => $site_mysql_password,
      host     => $site_mysql_host,
      grant    => ['all'],
    }
  }

  # drush site-alias definition

  file { '/etc/drush':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/etc/drush/aliases.drushrc.php':
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0400',
    content => template('drupal/aliases.drushrc.php.erb'),
    replace => true,
    require => [ File['/etc/drush'], Drush['drush'] ],
  }

  # site custom configuration

  file { "${_site_root}/etc":
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => File[$_site_root],
  }

  file { "${_site_root}/etc/settings.php":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0400',
    content => template('drupal/settings.php.erb'),
    replace => true,
    require => File["${_site_root}/etc"],
  }

  # deploy a site from scratch when site status is 'NOT INSTALLED'
  exec { "sitedeploy-${site_name}":
    command   => "/usr/bin/drush dsd-init @${site_alias}",
    logoutput => true,
    timeout   => 600,
    onlyif    => "/usr/bin/drush dsd-status @${site_alias} | /bin/grep -c 'NOT INSTALLED'",
    require   => [
      File['/etc/drush/aliases.drushrc.php'],
      ]
  }

  # update the site into a new slot when a remote update available
  exec { "siteupdate-${site_name}":
    command   => "/usr/bin/drush dsd-update @${site_alias}",
    logoutput => true,
    timeout   => 600,
    onlyif    => "/usr/bin/drush dsd-status @${site_alias} | /bin/grep -c 'UPDATE'",
    require   => [
      File['/etc/drush/aliases.drushrc.php'],
      Exec["sitedeploy-${site_name}"],
      ]
  }

  # setup cron job

  if $site_base_url != false and is_hash($conf) {
    cron { $site_name:
      name    => "${site_name}.cron",
      command => "wget -O /dev/null -q -t 1 ${$site_base_url}/cron.php?cron_key=${$conf['cron_key']}",
      user    => root,
      minute  => '*/5',
      require => [
        Exec["sitedeploy-${site_name}"],
        ]
    }
  }

}
