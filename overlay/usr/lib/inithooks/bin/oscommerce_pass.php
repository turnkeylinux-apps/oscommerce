<?php

define('PATH_LIBRARY', '/var/www/oscommerce/includes/classes/');
include PATH_LIBRARY . 'passwordhash.php';

if(count($argv)!=2) die("usage: $argv[0] password\n");

$password = $argv[1];

$PasswordHash = new PasswordHash(10, true);
print $PasswordHash->HashPassword($password);

?>

