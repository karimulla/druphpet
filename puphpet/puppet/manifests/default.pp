## Begin Server manifest

if $server_values == undef {
  $server_values = hiera('server', false)
}

if $vagrant_values == undef {
  $vagrant_values = hiera('vagrantfile-local', false)
}

# Ensure the time is accurate, reducing the possibilities of apt repositories
# failing for invalid certificates
include '::ntp'

Exec { path => [ '/bin/', '/sbin/', '/usr/bin/', '/usr/sbin/' ] }
File { owner => 0, group => 0, mode => 0644 }

group { 'puppet': ensure => present }
group { 'www-data': ensure => present }

user { $::ssh_username:
  shell  => '/bin/bash',
  home   => "/home/${::ssh_username}",
  ensure => present
}

user { ['apache', 'nginx', 'httpd', 'www-data']:
  shell  => '/bin/bash',
  ensure => present,
  groups => 'www-data',
  require => Group['www-data']
}

file { "/home/${::ssh_username}":
    ensure => directory,
    owner  => $::ssh_username,
}

# copy dot files to ssh user's home directory
exec { 'dotfiles':
  cwd     => "/home/${::ssh_username}",
  command => "cp -r /vagrant/puphpet/files/dot/.[a-zA-Z0-9]* /home/${::ssh_username}/ \
              && chown -R ${::ssh_username} /home/${::ssh_username}/.[a-zA-Z0-9]* \
              && cp -r /vagrant/puphpet/files/dot/.[a-zA-Z0-9]* /root/",
  onlyif  => 'test -d /vagrant/puphpet/files/dot',
  returns => [0, 1],
  require => User[$::ssh_username]
}

case $::osfamily {
  # debian, ubuntu
  'debian': {
    class { 'apt': }

    Class['::apt::update'] -> Package <|
        title != 'python-software-properties'
    and title != 'software-properties-common'
    |>

    ensure_packages( ['augeas-tools'] )
  }
  # redhat, centos
  'redhat': {
    class { 'yum': extrarepo => ['epel'] }

    class { 'yum::repo::rpmforge': }
    class { 'yum::repo::repoforgeextras': }

    Class['::yum'] -> Yum::Managed_yumrepo <| |> -> Package <| |>

    if defined(Package['git']) == false {
      package { 'git':
        ensure  => latest,
        require => Class['yum::repo::repoforgeextras']
      }
    }

    exec { 'bash_git':
      cwd     => "/home/${::ssh_username}",
      command => "curl https://raw.github.com/git/git/master/contrib/completion/git-prompt.sh > /home/${::ssh_username}/.bash_git",
      creates => "/home/${::ssh_username}/.bash_git"
    }

    exec { 'bash_git for root':
      cwd     => '/root',
      command => "cp /home/${::ssh_username}/.bash_git /root/.bash_git",
      creates => '/root/.bash_git',
      require => Exec['bash_git']
    }

    file_line { 'link ~/.bash_git':
      ensure  => present,
      line    => 'if [ -f ~/.bash_git ] ; then source ~/.bash_git; fi',
      path    => "/home/${::ssh_username}/.bash_profile",
      require => [
        Exec['dotfiles'],
        Exec['bash_git'],
      ]
    }

    file_line { 'link ~/.bash_git for root':
      ensure  => present,
      line    => 'if [ -f ~/.bash_git ] ; then source ~/.bash_git; fi',
      path    => '/root/.bashrc',
      require => [
        Exec['dotfiles'],
        Exec['bash_git'],
      ]
    }

    file_line { 'link ~/.bash_aliases':
      ensure  => present,
      line    => 'if [ -f ~/.bash_aliases ] ; then source ~/.bash_aliases; fi',
      path    => "/home/${::ssh_username}/.bash_profile",
      require => File_line['link ~/.bash_git']
    }

    file_line { 'link ~/.bash_aliases for root':
      ensure  => present,
      line    => 'if [ -f ~/.bash_aliases ] ; then source ~/.bash_aliases; fi',
      path    => '/root/.bashrc',
      require => File_line['link ~/.bash_git for root']
    }

    ensure_packages( ['augeas'] )
  }
}

if $php_values == undef {
  $php_values = hiera('php', false)
}

case $::operatingsystem {
  'debian': {
    include apt::backports

    add_dotdeb { 'packages.dotdeb.org': release => $lsbdistcodename }

    if is_hash($php_values) {
      # Debian Squeeze 6.0 can do PHP 5.3 (default) and 5.4
      if $lsbdistcodename == 'squeeze' and $php_values['version'] == '54' {
        add_dotdeb { 'packages.dotdeb.org-php54': release => 'squeeze-php54' }
      }
      # Debian Wheezy 7.0 can do PHP 5.4 (default) and 5.5
      elsif $lsbdistcodename == 'wheezy' and $php_values['version'] == '55' {
        add_dotdeb { 'packages.dotdeb.org-php55': release => 'wheezy-php55' }
      }
    }

    $server_lsbdistcodename = downcase($lsbdistcodename)

    apt::force { 'git':
      release => "${server_lsbdistcodename}-backports",
      timeout => 60
    }
  }
  'ubuntu': {
    apt::key { '4F4EA0AAE5267A6C':
      key_server => 'hkp://keyserver.ubuntu.com:80'
    }
    apt::key { '4CBEDD5A':
      key_server => 'hkp://keyserver.ubuntu.com:80'
    }

    apt::ppa { 'ppa:pdoes/ppa': require => Apt::Key['4CBEDD5A'] }

    if is_hash($php_values) {
      # Ubuntu Lucid 10.04, Precise 12.04, Quantal 12.10 and Raring 13.04 can do PHP 5.3 (default <= 12.10) and 5.4 (default <= 13.04)
      if $lsbdistcodename in ['lucid', 'precise', 'quantal', 'raring'] and $php_values['version'] == '54' {
        if $lsbdistcodename == 'lucid' {
          apt::ppa { 'ppa:ondrej/php5-oldstable': require => Apt::Key['4F4EA0AAE5267A6C'], options => '' }
        } else {
          apt::ppa { 'ppa:ondrej/php5-oldstable': require => Apt::Key['4F4EA0AAE5267A6C'] }
        }
      }
      # Ubuntu Precise 12.04, Quantal 12.10 and Raring 13.04 can do PHP 5.5
      elsif $lsbdistcodename in ['precise', 'quantal', 'raring'] and $php_values['version'] == '55' {
        apt::ppa { 'ppa:ondrej/php5': require => Apt::Key['4F4EA0AAE5267A6C'] }
      }
      elsif $lsbdistcodename in ['lucid'] and $php_values['version'] == '55' {
        err('You have chosen to install PHP 5.5 on Ubuntu 10.04 Lucid. This will probably not work!')
      }
    }
  }
  'redhat', 'centos': {
    if is_hash($php_values) {
      if $php_values['version'] == '54' {
        class { 'yum::repo::remi': }
      }
      # remi_php55 requires the remi repo as well
      elsif $php_values['version'] == '55' {
        class { 'yum::repo::remi': }
        class { 'yum::repo::remi_php55': }
      }
    }
  }
}

if !empty($server_values['packages']) {
  ensure_packages( $server_values['packages'] )
}

define add_dotdeb ($release){
   apt::source { $name:
    location          => 'http://packages.dotdeb.org',
    release           => $release,
    repos             => 'all',
    required_packages => 'debian-keyring debian-archive-keyring',
    key               => '89DF5277',
    key_server        => 'keys.gnupg.net',
    include_src       => true
  }
}

## Begin Apache manifest

if $yaml_values == undef {
  $yaml_values = loadyaml('/vagrant/puphpet/config.yaml')
}

if $apache_values == undef {
  $apache_values = $yaml_values['apache']
}

include puphpet::params

$webroot_location = $puphpet::params::apache_webroot_location

exec { "exec mkdir -p ${webroot_location}":
  command => "mkdir -p ${webroot_location}",
  creates => $webroot_location,
}

if ! defined(File[$webroot_location]) {
  file { $webroot_location:
    ensure  => directory,
    group   => 'www-data',
    mode    => 0777,
    require => [
      Exec["exec mkdir -p ${webroot_location}"],
      Group['www-data']
    ]
  }
}

class { 'apache':
  user          => $apache_values['user'],
  group         => $apache_values['group'],
  default_vhost => $apache_values['default_vhost'],
  mpm_module    => $apache_values['mpm_module'],
  manage_user   => false,
  manage_group  => false,
  apache_version => '2.4'
}

if $::osfamily == 'debian' {
  case $apache_values['mpm_module'] {
    'prefork': { ensure_packages( ['apache2-mpm-prefork'] ) }
    'worker':  { ensure_packages( ['apache2-mpm-worker'] ) }
    'event':   { ensure_packages( ['apache2-mpm-event'] ) }
  }
} elsif $::osfamily == 'redhat' and ! defined(Iptables::Allow['tcp/80']) {
  iptables::allow { 'tcp/80':
    port     => '80',
    protocol => 'tcp'
  }
}

if has_key($apache_values, 'mod_pagespeed') and $apache_values['mod_pagespeed'] == 1 {
  class { 'puphpet::apache::modpagespeed': }
}

if has_key($apache_values, 'mod_spdy') and $apache_values['mod_spdy'] == 1 {
  class { 'puphpet::apache::modspdy': }
}

create_resources(apache::vhost, $apache_values['vhosts'])

define apache_mod {
  if ! defined(Class["apache::mod::${name}"]) {
    class { "apache::mod::${name}": }
  }
}

if count($apache_values['modules']) > 0 {
  apache_mod { $apache_values['modules']: }
}

## Begin PHP manifest

if $php_values == undef {
  $php_values = hiera('php', false)
}

if $apache_values == undef {
  $apache_values = hiera('apache', false)
}

if $nginx_values == undef {
  $nginx_values = hiera('nginx', false)
}

Class['Php'] -> Class['Php::Devel'] -> Php::Module <| |> -> Php::Pear::Module <| |> -> Php::Pecl::Module <| |>

if $php_prefix == undef {
  $php_prefix = $::operatingsystem ? {
    /(?i:Ubuntu|Debian|Mint|SLES|OpenSuSE)/ => 'php5-',
    default                                 => 'php-',
  }
}

if $php_fpm_ini == undef {
  $php_fpm_ini = $::operatingsystem ? {
    /(?i:Ubuntu|Debian|Mint|SLES|OpenSuSE)/ => '/etc/php5/fpm/php.ini',
    default                                 => '/etc/php.ini',
  }
}

if is_hash($apache_values) {
  include apache::params

  if has_key($apache_values, 'mod_spdy') and $apache_values['mod_spdy'] == 1 {
    $php_webserver_service_ini = 'cgi'
  } else {
    $php_webserver_service_ini = 'httpd'
  }

  $php_webserver_service = 'httpd'
  $php_webserver_user    = $apache::params::user
  $php_webserver_restart = true

  class { 'php':
    service => $php_webserver_service
  }
} elsif is_hash($nginx_values) {
  include nginx::params

  $php_webserver_service     = "${php_prefix}fpm"
  $php_webserver_service_ini = $php_webserver_service
  $php_webserver_user        = $nginx::params::nx_daemon_user
  $php_webserver_restart     = true

  class { 'php':
    package             => $php_webserver_service,
    service             => $php_webserver_service,
    service_autorestart => false,
    config_file         => $php_fpm_ini,
  }

  service { $php_webserver_service:
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
    require    => Package[$php_webserver_service]
  }
} else {
  $php_webserver_service     = undef
  $php_webserver_service_ini = undef
  $php_webserver_restart     = false

  class { 'php':
    package             => "${php_prefix}cli",
    service             => $php_webserver_service,
    service_autorestart => false,
  }
}

class { 'php::devel': }

if count($php_values['modules']['php']) > 0 {
  php_mod { $php_values['modules']['php']:; }
}
if count($php_values['modules']['pear']) > 0 {
  php_pear_mod { $php_values['modules']['pear']:; }
}
if count($php_values['modules']['pecl']) > 0 {
  php_pecl_mod { $php_values['modules']['pecl']:; }
}
if count($php_values['ini']) > 0 {
  each( $php_values['ini'] ) |$key, $value| {
    if is_array($value) {
      each( $php_values['ini'][$key] ) |$innerkey, $innervalue| {
        puphpet::ini { "${key}_${innerkey}":
          entry       => "CUSTOM_${innerkey}/${key}",
          value       => $innervalue,
          php_version => $php_values['version'],
          webserver   => $php_webserver_service_ini
        }
      }
    } else {
      puphpet::ini { $key:
        entry       => "CUSTOM/${key}",
        value       => $value,
        php_version => $php_values['version'],
        webserver   => $php_webserver_service_ini
      }
    }
  }

  if $php_values['ini']['session.save_path'] != undef {
    exec {"mkdir -p ${php_values['ini']['session.save_path']}":
      onlyif  => "test ! -d ${php_values['ini']['session.save_path']}",
    }

    file { $php_values['ini']['session.save_path']:
      ensure  => directory,
      group   => 'www-data',
      mode    => 0777,
      require => Exec["mkdir -p ${php_values['ini']['session.save_path']}"]
    }
  }
}

puphpet::ini { $key:
  entry       => 'CUSTOM/date.timezone',
  value       => $php_values['timezone'],
  php_version => $php_values['version'],
  webserver   => $php_webserver_service_ini
}

define php_mod {
  php::module { $name:
    service_autorestart => $php_webserver_restart,
  }
}
define php_pear_mod {
  php::pear::module { $name:
    use_package         => false,
    service_autorestart => $php_webserver_restart,
  }
}
define php_pecl_mod {
  php::pecl::module { $name:
    use_package         => false,
    service_autorestart => $php_webserver_restart,
    preferred_state     => 'beta',
  }
}

if $php_values['composer'] == 1 {
  class { 'composer':
    target_dir      => '/usr/local/bin',
    composer_file   => 'composer',
    download_method => 'curl',
    logoutput       => false,
    tmp_path        => '/tmp',
    php_package     => "${php::params::module_prefix}cli",
    curl_package    => 'curl',
    suhosin_enabled => false,
  }
}

## Begin Xdebug manifest

if $xdebug_values == undef {
  $xdebug_values = hiera('xdebug', false)
}

if is_hash($apache_values) {
  $xdebug_webserver_service = 'httpd'
} elsif is_hash($nginx_values) {
  $xdebug_webserver_service = 'nginx'
} else {
  $xdebug_webserver_service = undef
}

if $xdebug_values['install'] != undef and $xdebug_values['install'] == 1 {
  class { 'puphpet::xdebug':
    webserver => $xdebug_webserver_service
  }

  if is_hash($xdebug_values['settings']) and count($xdebug_values['settings']) > 0 {
    each( $xdebug_values['settings'] ) |$key, $value| {
      puphpet::ini { $key:
        entry       => "XDEBUG/${key}",
        value       => $value,
        php_version => $php_values['version'],
        webserver   => $xdebug_webserver_service
      }
    }
  }
}

## Begin Drush manifest

if $drush_values == undef {
  $drush_values = hiera('drush', false)
}

if $drush_values['install'] != undef and $drush_values['install'] == 1 {
  if ($drush_values['settings']['drush.tag_branch'] != undef) {
    $drush_tag_branch = $drush_values['settings']['drush.tag_branch']
  } else {
    $drush_tag_branch = ''
  }

  ## @see https://drupal.org/node/2165015
  include drush::git::drush

  ## class { 'drush::git::drush':
  ##   git_branch => $drush_tag_branch,
  ##   update     => true,
  ## }
}

## End Drush manifest

## Begin MySQL manifest

if $mysql_values == undef {
  $mysql_values = hiera('mysql', false)
}

if $php_values == undef {
  $php_values = hiera('php', false)
}

if $apache_values == undef {
  $apache_values = hiera('apache', false)
}

if $nginx_values == undef {
  $nginx_values = hiera('nginx', false)
}

if is_hash($apache_values) or is_hash($nginx_values) {
  $mysql_webserver_restart = true
} else {
  $mysql_webserver_restart = false
}

if $mysql_values['root_password'] {
  class { 'mysql::server':
    root_password => $mysql_values['root_password'],
    override_options => {
      'mysqld' => {
        'bind-address' => '0.0.0.0',
      }
    }
  }

  if is_hash($mysql_values['databases']) and count($mysql_values['databases']) > 0 {
    create_resources(mysql_db, $mysql_values['databases'])
  }

  if is_hash($php_values) {
    if $::osfamily == 'redhat' and $php_values['version'] == '53' and ! defined(Php::Module['mysql']) {
      php::module { 'mysql':
        service_autorestart => $mysql_webserver_restart,
      }
    } elsif ! defined(Php::Module['mysqlnd']) {
      php::module { 'mysqlnd':
        service_autorestart => $mysql_webserver_restart,
      }
    }
  }
}

define mysql_db (
  $user,
  $password,
  $host,
  $grant    = [],
  $sql_file = false
) {
  if $name == '' or $password == '' or $host == '' {
    fail( 'MySQL DB requires that name, password and host be set. Please check your settings!' )
  }

  mysql::db { $name:
    user     => $user,
    password => $password,
    host     => $host,
    grant    => $grant,
    sql      => $sql_file,
  }
}

if hash_key_equals($mysql_values, 'phpmyadmin', 1) {
  if hash_key_equals($apache_values, 'install', 1) {
    $mysql_pma_webroot_location = $puphpet::params::apache_webroot_location
  } elsif hash_key_equals($nginx_values, 'install', 1) {
    $mysql_pma_webroot_location = $puphpet::params::nginx_webroot_location

    mysql_nginx_default_conf { 'override_default_conf':
      webroot => $mysql_pma_webroot_location
    }
  } else {
    $mysql_pma_webroot_location = '/var/www'
  }

  class { 'puphpet::phpmyadmin':
    dbms             => 'mysql::server',
    webroot_location => $mysql_pma_webroot_location,
  }
}

if hash_key_equals($mysql_values, 'adminer', 1) {
  if hash_key_equals($apache_values, 'install', 1) {
    $mysql_adminer_webroot_location = $puphpet::params::apache_webroot_location
  } elsif hash_key_equals($nginx_values, 'install', 1) {
    $mysql_adminer_webroot_location = $puphpet::params::nginx_webroot_location
  } else {
    $mysql_adminer_webroot_location = $puphpet::params::apache_webroot_location
  }

  class { 'puphpet::adminer':
    location    => "${mysql_adminer_webroot_location}/adminer",
    owner       => 'www-data',
    php_package => $mysql_php_package
  }
}

define mysql_nginx_default_conf (
  $webroot
) {
  if $php5_fpm_sock == undef {
    $php5_fpm_sock = '/var/run/php5-fpm.sock'
  }

  if $fastcgi_pass == undef {
    $fastcgi_pass = $php_values['version'] ? {
      undef   => null,
      '53'    => '127.0.0.1:9000',
      default => "unix:${php5_fpm_sock}"
    }
  }

  class { 'puphpet::nginx':
    fastcgi_pass => $fastcgi_pass,
    notify       => Class['nginx::service'],
  }
}

# Begin beanstalkd

if $beanstalkd_values == undef {
  $beanstalkd_values = hiera('beanstalkd', false)
}

if has_key($beanstalkd_values, 'install') and $beanstalkd_values['install'] == 1 {
  beanstalkd::config { $beanstalkd_values: }
}

exec { 'public_html':
  path    => '/bin',
  command => 'ln -s /var/www/ /home/vagrant/public_html',
  creates => '/home/vagrant/public_html'
}

composer::exec { 'composer-install-drush':
  cmd  => 'install',
  cwd  => '/usr/share/drush',
  user => 'root'
}


# Apache Solr

class { 'solr':

}

# XHProf

class { 'xhprof':
  version => '0.9.4'
}

# PimpMyLog

class { 'pimpmylog':

}

# MailCatcher

if $mailcatcher_values == undef {
  $mailcatcher_values = hiera('mailcatcher', false)
}

if has_key($mailcatcher_values, 'install') and $mailcatcher_values['install'] == 1 {
  class { 'mailcatcher':    

  }
  
  $mailcatcher_host_ip = $mailcatcher_values['http_ip']
  $mailcatcher_host_port = $mailcatcher_values['http_port']
  
  exec { "exec mailcatcher --http-ip=${mailcatcher_host_ip} --http-port=${mailcatcher_host_port}":
    command => "/usr/local/bin/mailcatcher --http-ip=${mailcatcher_host_ip} --http-port=${mailcatcher_host_port}",    
	require => Class['mailcatcher']
  }    
}

# Begin rabbitmq

if $rabbitmq_values == undef {
  $rabbitmq_values = hiera('rabbitmq', false)
} if $php_values == undef {
  $php_values = hiera('php', false)
} if $apache_values == undef {
  $apache_values = hiera('apache', false)
} if $nginx_values == undef {
  $nginx_values = hiera('nginx', false)
}

if hash_key_equals($apache_values, 'install', 1)
  or hash_key_equals($nginx_values, 'install', 1)
{
  $rabbitmq_webserver_restart = true
} else {
  $rabbitmq_webserver_restart = false
}

if hash_key_equals($rabbitmq_values, 'install', 1) {
  create_resources('class', { 'rabbitmq' => $rabbitmq_values['settings'] })

  if hash_key_equals($php_values, 'install', 1) and ! defined(Php::Pecl::Module['amqp']) {
    php::pecl::module { 'amqp':
      use_package         => false,
      service_autorestart => $rabbitmq_webserver_restart,
      require             => Class['rabbitmq']
    }
  }
}
