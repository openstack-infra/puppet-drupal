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
# == Define: drush
#
# define to add drush and custom dsd extension
#
# Drush parameters:
# - drushdsdtar: drush dsd release tarball
# - basedrushdsdtar: drush dsd tar local filename
# - download_dir: download directory, local copy of release tarball lives here

define drupal::drush (
  $basedrushdsdtar = 'drush-dsd-0.10.tar.gz',
  $download_dir    = '/srv/downloads',
  $drushdsdtar     = 'https://github.com/mkissam/drush-dsd/archive/v0.10.tar.gz',
) {

  # Fix the resource ordering in the drush::git::drush class
  Drush::Git['https://github.com/drush-ops/drush.git'] -> Exec['Install composer']

  class {'::drush::git::drush':
    git_branch => '6.x',
    git_tag    => '6.x',
  }

  file { '/usr/share/drush/commands/dsd':
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => Class['::drush::git::drush'],
  }

  # If we don't already have the specified dsd tar, download it.
  exec { "download:${drushdsdtar}":
    command => "/usr/bin/wget ${drushdsdtar} -O ${download_dir}/${basedrushdsdtar}",
    creates => "${download_dir}/${basedrushdsdtar}",
    require => File[$download_dir],
  }

  # If drush-dsd.tar.gz isn't the same as $basedrushdsdtar, install it.
  file { "${download_dir}/drush-dsd.tar.gz":
    ensure  => present,
    source  => "file://${download_dir}/${basedrushdsdtar}",
    require => Exec["download:${drushdsdtar}"],
    replace => true,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  # If drush-dsd just created extract to /etc/drush
  exec { 'drush-dsd-initial-init':
    user        => 'root',
    command     => "/bin/tar -C /usr/share/drush/commands/dsd --strip 1 -xzvf ${download_dir}/drush-dsd.tar.gz;/usr/bin/drush cc all",
    subscribe   => File["${download_dir}/drush-dsd.tar.gz"],
    refreshonly => true,
    logoutput   => true,
    require     => File['/usr/share/drush/commands/dsd'],
  }

}
