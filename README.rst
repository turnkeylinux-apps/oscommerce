osCommerce - Online shop
========================

**IMPORTANT NOTE**
New users should not use this appliance.

osCommerce is "abandonware" and has been superseded by `Phoenix Cart` - a
fork/revival of the original project. So the TurnKey osCommerce appliance has
been deprecated in favour of a new `Phoenix Cart appliance`_.

---

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
- `Adminer`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
- Postfix MTA (bound to localhost) to allow sending of email (e.g.,
  password recovery).
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL: username **root**
-  Adminer: username **adminer**
-  osCommerce: username **admin**


.. _osCommerce: http://www.oscommerce.com/
.. _Phoenix Cart:  https://phoenixcart.org/
.. _Phoenix Cart appliance: https://www.turnkeylinux.org/phoenixcart
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Adminer: http://www.adminer.org/
