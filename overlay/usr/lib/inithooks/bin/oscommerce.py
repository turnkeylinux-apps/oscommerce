#!/usr/bin/python3
"""Set osCommerce admin password and email

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively
    --domain=   unless provided, will ask interactively

"""

import re
import sys
import getopt
import urllib.parse
from libinithooks import inithooks_cache
import subprocess
from os.path import *
from urllib.parse import urlparse

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
            "osCommerce Password",
            "Enter new password for the osCommerce 'admin' account.")

    if not email:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        email = d.get_email(
            "osCommerce Email",
            "Enter email address for the osCommerce 'admin' account.",
            "admin@example.com")

    inithooks_cache.write('APP_EMAIL', email)

    if not domain:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        domain = d.get_input(
            "osCommerce Domain",
            "Enter the domain to serve osCommerce",
            DEFAULT_DOMAIN)
        
    if domain == "DEFAULT":
        domain = DEFAULT_DOMAIN

    inithooks_cache.write('APP_DOMAIN', domain)

    hashed = {}
    for line in subprocess.run(
	["php", join(dirname(__file__), 'oscommerce_pass.php'), password, email],
	text=True,
	capture_output=True
    ).stdout.strip().splitlines():
        key, value = line.split(' ', 1)
        hashed[key] = value

    m = MySQL()
    m.execute('UPDATE oscommerce.admin SET admin_password=%s, admin_email_address=%s, admin_email_token=%s WHERE admin_username=\"admin\";', (
        hashed['password'],
        email,
        hashed['email']
    ))

    m.execute('UPDATE oscommerce.configuration SET configuration_value=%s WHERE configuration_key=\"EMAIL_FROM\";', (email,))
    m.execute('UPDATE oscommerce.configuration SET configuration_value=%s WHERE configuration_key=\"STORE_OWNER_EMAIL_ADDRESS\";', (email,))
    m.execute('UPDATE oscommerce.configuration SET configuration_value=%s WHERE configuration_key=\"MODULE_PAYMENT_PAYPAL_EXPRESS_SELLER_ACCOUNT\";', (email,))

    platforms = m.execute("SELECT platform_id, platform_url, platform_email_address"
                          " FROM oscommerce.platforms;", output=True)
    for platform in platforms:
        url = platform['platform_url']
        if not url:
            continue
        if not url.startswith('http://') and not url.startswith('https://'):
            url = f"http://{url}"
        parsed_url = urlparse(url)
        if not parsed_url.path:  # just domain
            m.execute('UPDATE oscommerce.platforms'
                      ' SET platform_url=%s, platform_email_address=%s'
                      ' WHERE platform_id=%s;',
                      (domain, email, platform['platform_id'], ))
        else:  # domain and path
            this_domain = join(domain, parsed_url.path.lstrip('/'))
            m.execute('UPDATE oscommerce.platforms'
                      ' SET platform_url=%s, platform_email_address=%s'
                      ' WHERE platform_id=%s;',
                      (this_domain, email, platform['platform_id'], ))

    conf_path = '/var/www/oscommerce/admin/includes/local/configure.php'

    with open(conf_path, 'r') as fob:
        conf = fob.read().splitlines()

    for i, line in enumerate(conf[:]):
        if 'HTTPS_SERVER' in line:
            conf[i] = re.sub(
                r"define\('HTTPS_SERVER', '.*'\);",
                "define('HTTPS_SERVER', 'https://%s');" % domain,
                line)
        if 'HTTP_SERVER' in line:
            conf[i] = re.sub(
                r"define\('HTTP_SERVER', '.*'\);",
                "define('HTTP_SERVER', '');",
                line)

    with open(conf_path, 'w') as fob:
        fob.write('\n'.join(conf))

    apache_conf = "/etc/apache2/sites-available/oscommerce.conf"
    subprocess.run(["sed", "-i", "\|RewriteRule|s|https://.*|https://%s/\$1 [R,L]|" % domain, apache_conf])
    subprocess.run(["sed", "-i", "\|RewriteCond|s|!^.*|!^%s$|" % domain, apache_conf])
    subprocess.run(["service", "apache2", "restart"])

if __name__ == "__main__":
    main()
