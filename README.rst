PhoenixCart - Online shop
=========================

`PhoenixCart`_ provides everything you need to get started in selling
physical and digital goods over the internet, from the Catalog frontend
that is presented to your customers, to the Administration Tool backend
that completely handles your products, customers, orders, and online
store data.

`PhoenixCart`_ is the community continuation of osCommerce.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- PhoenixCart configurations:
   
   - Installed from upstream source code to /var/www/phoenix_cart

- SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
- Postfix MTA (bound to localhost) to allow sending of email (e.g.,
  password recovery).
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL: username **root**
-  Adminer: username **adminer**
-  PhoenixCart: username **admin**


.. _PhoenixCart: https://phoenixcart.org/
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Adminer: http://www.adminer.org/
