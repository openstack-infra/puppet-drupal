# == Class: drupal::params
#
# Centralized configuration management for the drupal module.
#
class drupal::params() {
  case $::osfamily {
    'Debian': {
      if $::operatingsystem == 'Ubuntu' and versioncmp($::operatingsystemrelease, '13.10') >= 0 {
        $apache_version = '2.4'
      } else {
        $apache_version = '2.2'
      }
    }
    default: {
      fail("Unsupported osfamily: ${::osfamily} The 'storyboard' module only supports osfamily Debian.")
    }
  }
}
