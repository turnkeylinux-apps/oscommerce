#!/usr/bin/python3
"""Set PhoenixCart admin password and email

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively
    --domain=   unless provided, will ask interactively

"""

import re
import sys
import getopt
from libinithooks import inithooks_cache
import subprocess
from os.path import dirname, join

from libinithooks.dialog_wrapper import Dialog
from mysqlconf import MySQL

def fatal(s):
    print("Error:", s, file=sys.stderr)
    sys.exit(1)

def usage(s=None):
    if s:
        print("Error:", s, file=sys.stderr)
    print("Syntax: %s [options]" % sys.argv[0], file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)

DEFAULT_DOMAIN="www.example.com"

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email=', 'domain='])
    except getopt.GetoptError as e:
        usage(e)

    password = ""
    email = ""
    domain = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val
        elif opt == '--email':
            email = val
        elif opt == '--domain':
            domain = val

    if not password:
        d = Dialog('TurnKey Linux - First boot configuration')
        password = d.get_password(
            "PhoenixCart Password",
            "Enter new password for the PhoenixCart 'admin' account.")

    if not email:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        email = d.get_email(
            "PhoenixCart Email",
            "Enter email address for the PhoenixCart 'admin' account.",
            "admin@example.com")

    inithooks_cache.write('APP_EMAIL', email)

    if not domain:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        domain = d.get_input(
            "PhoenixCart Domain",
            "Enter the domain to serve PhoenixCart",
            DEFAULT_DOMAIN)

    if domain == "DEFAULT":
        domain = DEFAULT_DOMAIN

    inithooks_cache.write('APP_DOMAIN', domain)

    hashed = {}
    for line in subprocess.run(
        ["/usr/bin/php", join(dirname(__file__), 'phoenix_cart_pass.php'), password, email],
        text=True,
        capture_output=True
    ).stdout.strip().splitlines():
        key, value = line.split(' ', 1)
        hashed[key] = value

    m = MySQL()
    m.execute('UPDATE phoenix_cart.administrators SET user_password=%s WHERE user_name="admin";', (
        hashed['password'],
    ))

    m.execute('UPDATE phoenix_cart.configuration SET configuration_value=%s WHERE configuration_key="EMAIL_FROM";', (email,))
    m.execute('UPDATE phoenix_cart.configuration SET configuration_value=%s WHERE configuration_key="STORE_OWNER_EMAIL_ADDRESS";', (email,))
    m.execute('UPDATE phoenix_cart.configuration SET configuration_value=%s WHERE configuration_key="MODULE_PAYMENT_PAYPAL_EXPRESS_SELLER_ACCOUNT";', (email,))

    conf_path = '/var/www/phoenix_cart/administration/includes/configure.php'

    with open(conf_path, 'r') as fob:
        conf = fob.read().splitlines()

    for i, line in enumerate(conf[:]):
        if 'HTTPS_SERVER' in line:
            conf[i] = re.sub(
                r"HTTPS_SERVER = '.*';",
                f"HTTPS_SERVER = 'https://{domain}';",
                line)
        if 'HTTP_SERVER' in line:
            conf[i] = re.sub(
                r"HTTP_SERVER = '.*';",
                f"HTTP_SERVER = 'https://{domain}';",
                line)

    with open(conf_path, 'w') as fob:
        fob.write('\n'.join(conf))

    apache_conf = "/etc/apache2/sites-available/phoenix_cart.conf"
    subprocess.run(["/usr/bin/sed", "-i",
                    f"\\|RewriteRule|s|https://.*|https://{domain}/\\$1 [R,L]|", apache_conf])
    subprocess.run(["/usr/bin/sed", "-i", f"\\|RewriteCond|s|!^.*|!^{domain}$|", apache_conf])
    subprocess.run(["service", "apache2", "restart"])

if __name__ == "__main__":
    main()
