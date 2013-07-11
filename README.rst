osCommerce - Online shop
========================

`osCommerce`_ provides everything you need to get started in selling
physical and digital goods over the internet, from the Catalog frontend
that is presented to your customers, to the Administration Tool backend
that completely handles your products, customers, orders, and online
store data.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- osCommerce configurations:
   
   - Installed from upstream source code to /var/www/oscommerce

- SSL support out of the box.
- `PHPMyAdmin`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
- Postfix MTA (bound to localhost) to allow sending of email (e.g.,
  password recovery).
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL, phpMyAdmin: username **root**
-  osCommerce: username **admin**


.. _osCommerce: http://www.oscommerce.com/
.. _TurnKey Core: http://www.turnkeylinux.org/core
.. _PHPMyAdmin: http://www.phpmyadmin.net
