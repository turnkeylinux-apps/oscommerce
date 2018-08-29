#!/usr/bin/python
"""Set osCommerce admin password and email

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively
    --domain=   unless provided, will ask interactively

"""

import re
import sys
import getopt
import urlparse
import inithooks_cache
import subprocess
from subprocess import PIPE
from os.path import *

from dialog_wrapper import Dialog
from mysqlconf import MySQL

def fatal(s):
    print >> sys.stderr, "Error:", s
    sys.exit(1)

def usage(s=None):
    if s:
        print >> sys.stderr, "Error:", s
    print >> sys.stderr, "Syntax: %s [options]" % sys.argv[0]
    print >> sys.stderr, __doc__
    sys.exit(1)

DEFAULT_DOMAIN="www.example.com"

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email=', 'domain='])
    except getopt.GetoptError, e:
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
    

    command = ["php", join(dirname(__file__), 'oscommerce_pass.php'), password]
    p = subprocess.Popen(command, stdin=PIPE, stdout=PIPE, shell=False)
    stdout, stderr = p.communicate()
    if stderr:
        fatal(stderr)

    cryptpass = stdout.strip()

    m = MySQL()
    m.execute('UPDATE oscommerce.administrators SET user_password=\"%s\" WHERE user_name=\"admin\";' % cryptpass)

    m.execute('UPDATE oscommerce.configuration SET configuration_value=\"%s\" WHERE configuration_key=\"EMAIL_FROM\";' % email)
    m.execute('UPDATE oscommerce.configuration SET configuration_value=\"%s\" WHERE configuration_key=\"STORE_OWNER_EMAIL_ADDRESS\";' % email)
    m.execute('UPDATE oscommerce.configuration SET configuration_value=\"%s\" WHERE configuration_key=\"MODULE_PAYMENT_PAYPAL_EXPRESS_SELLER_ACCOUNT\";' % email)

    conf_paths = (
        '/var/www/oscommerce/admin/includes/configure.php',
        '/var/www/oscommerce/includes/configure.php'
    )

    for conf_path in conf_paths:
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
                    "define('HTTP_SERVER', 'http://%s');" % domain,
                    line)
            print(line, conf[i])

        with open(conf_path, 'w') as fob:
            fob.write('\n'.join(conf))

    apache_conf = "/etc/apache2/sites-available/oscommerce.conf"
    system("sed -i \"\|RewriteRule|s|https://.*|https://%s/\$1 [R,L]|\" %s" % (domain, apache_conf))

    system("service apache2 restart")

if __name__ == "__main__":
    main()
