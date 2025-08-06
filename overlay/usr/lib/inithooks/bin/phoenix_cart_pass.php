<?php

define('PATH_LIBRARY', '/var/www/phoenix_cart/lib/common/');
include PATH_LIBRARY . 'classes/PasswordHash.php';
$params = include PATH_LIBRARY . 'config/params-local.php';

if(count($argv)!=3) die("usage: $argv[0] password email\n");

$password = $argv[1];
$email = $argv[2];

print 'email ' . password_hash($email . $params['secKey.backend'], PASSWORD_BCRYPT) . "\n";
print 'password ' . password_hash($password . $params['secKey.backend'], PASSWORD_BCRYPT) . "\n";
?>

