#!/bin/bash
set -Eeuo pipefail
umask 077

result=${TKL_TEST_RESULT:?TKL_TEST_RESULT is required}
app_password=${TKL_TEST_APP_PASS:?TKL_TEST_APP_PASS is required}
db_password=${TKL_TEST_DB_PASS:?TKL_TEST_DB_PASS is required}
base=https://localhost
cookie=/tmp/tkl-oscommerce-cookie.$$
page=/tmp/tkl-oscommerce-page.$$
headers=/tmp/tkl-oscommerce-headers.$$
form_body=/tmp/tkl-oscommerce-form.$$
adminer_cookie=/tmp/tkl-oscommerce-adminer-cookie.$$
fixture_port_file=/tmp/tkl-oscommerce-fixture-port.$$
fixture_metadata=/tmp/tkl-oscommerce-fixture-metadata.$$
fixture_request=/tmp/tkl-oscommerce-fixture-request.$$
backend_params=/var/www/oscommerce/lib/backend/config/params-local.php
backend_params_backup=/tmp/tkl-oscommerce-params-local.$$
fixture_pid=
config_changed=0
storage_key_changed=0
original_storage_key_hex=
product_id=
product_created=0

report_error() {
    printf 'test_failure line=%s status=%s command=%q\n' \
        "$1" "$2" "$3" >&2
    exit "$2"
}
trap 'report_error "$LINENO" "$?" "$BASH_COMMAND"' ERR

cleanup() {
    if [[ $product_created == 1 && -n $product_id ]]; then
        curl --insecure --silent --show-error \
            --cookie "$cookie" --cookie-jar "$cookie" \
            --data-urlencode "products_id=$product_id" \
            "$base/admin/categories/productdelete" >/dev/null 2>&1 || true
    fi
    if [[ $storage_key_changed == 1 ]]; then
        mariadb oscommerce --execute \
            "UPDATE admin SET storage_key=UNHEX('$original_storage_key_hex') WHERE admin_username='admin'" \
            >/dev/null 2>&1 || true
    fi
    if [[ $config_changed == 1 ]]; then
        cp --preserve=all -- "$backend_params_backup" "$backend_params" \
            >/dev/null 2>&1 || true
        systemctl reload apache2.service >/dev/null 2>&1 || true
    fi
    if [[ -n $fixture_pid ]]; then
        kill "$fixture_pid" >/dev/null 2>&1 || true
        wait "$fixture_pid" >/dev/null 2>&1 || true
    fi
    rm -f -- "$cookie" "$page" "$headers" "$form_body" "$adminer_cookie" \
        "$fixture_port_file" "$fixture_metadata" "$fixture_request" \
        "$backend_params_backup"
}
trap cleanup EXIT

serialize_product_form() {
    TKL_FORM_PAGE=$page TKL_FORM_BODY=$form_body \
        TKL_FORM_VALUE=$1 python3 - <<'PYTHON'
import os
from html.parser import HTMLParser
from urllib.parse import urlencode


class ProductForm(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.in_form = False
        self.textarea = None
        self.textarea_value = []
        self.select = None
        self.options = []
        self.option = None
        self.option_text = []
        self.fields = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "form":
            self.in_form = attrs.get("id") == "save_product_form"
            return
        if not self.in_form:
            return
        if tag == "input":
            name = attrs.get("name")
            input_type = attrs.get("type", "text").lower()
            ignored = {"submit", "button", "image", "reset", "file"}
            if not name or "disabled" in attrs or input_type in ignored:
                return
            if input_type in {"checkbox", "radio"} and "checked" not in attrs:
                return
            default = "on" if input_type in {"checkbox", "radio"} else ""
            self.fields.append((name, attrs.get("value", default)))
        elif tag == "div" and attrs.get("data-name", "").startswith(
                "orig_file_name["):
            # The upload widget creates this hidden field in the browser.
            self.fields.append((attrs["data-name"], attrs.get("data-preload", "")))
        elif tag == "textarea" and attrs.get("name") and "disabled" not in attrs:
            self.textarea = attrs["name"]
            self.textarea_value = []
        elif tag == "select" and attrs.get("name") and "disabled" not in attrs:
            self.select = (attrs["name"], "multiple" in attrs)
            self.options = []
        elif tag == "option" and self.select:
            self.option = (attrs.get("value"), "selected" in attrs)
            self.option_text = []

    def handle_data(self, data):
        if self.textarea is not None:
            self.textarea_value.append(data)
        if self.option is not None:
            self.option_text.append(data)

    def handle_endtag(self, tag):
        if tag == "textarea" and self.textarea is not None:
            self.fields.append((self.textarea, "".join(self.textarea_value)))
            self.textarea = None
        elif tag == "option" and self.option is not None:
            value, selected = self.option
            if value is None:
                value = "".join(self.option_text).strip()
            self.options.append((value, selected))
            self.option = None
        elif tag == "select" and self.select:
            name, multiple = self.select
            selected = [value for value, active in self.options if active]
            if not selected and self.options:
                selected = [self.options[0][0]]
            if not multiple:
                selected = selected[:1]
            self.fields.extend((name, value) for value in selected)
            self.select = None
        elif tag == "form" and self.in_form:
            self.in_form = False


with open(os.environ["TKL_FORM_PAGE"], encoding="utf-8") as source:
    parser = ProductForm()
    parser.feed(source.read())

target = "pDescription[1][1][products_name]"
replacement = os.environ["TKL_FORM_VALUE"]
overrides = {
    target: replacement,
    "products_status": "1",
}
fields = []
replaced = set()
for name, value in parser.fields:
    if name in overrides:
        value = overrides[name]
        replaced.add(name)
    fields.append((name, value))
if target not in replaced:
    raise RuntimeError(f"product form did not contain {target}")
for name, value in overrides.items():
    if name not in replaced:
        fields.append((name, value))

with open(os.environ["TKL_FORM_BODY"], "w", encoding="utf-8") as destination:
    destination.write(urlencode(fields))
PYTHON
}

login_admin() {
    curl --insecure --fail --silent --show-error \
        --cookie-jar "$cookie" "$base/admin/login" >"$page"
    csrf=$(sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' "$page" | head -1)
    test -n "$csrf"
    curl --insecure --silent --show-error \
        --cookie "$cookie" --cookie-jar "$cookie" \
        --dump-header "$headers" --output "$page" \
        --data-urlencode "_csrf=$csrf" \
        --data-urlencode 'email_address=admin' \
        --data-urlencode "password=$app_password" \
        "$base/admin/login?action=process"
    grep -q '^HTTP/.* 302' "$headers"
    grep -q 'tlAdminID' "$cookie"
}

post_product_form() {
    http_status=$(curl --insecure --silent --show-error \
        --cookie "$cookie" --cookie-jar "$cookie" \
        --output "$page" --write-out '%{http_code}' \
        --data-binary "@$form_body" \
        "$base/admin/categories/product-submit")
    test "$http_status" = 200
    grep -qi success "$page"
}

set_storage_key() {
    curl --insecure --fail --silent --show-error --location \
        --cookie "$cookie" --cookie-jar "$cookie" \
        --data-urlencode "storekey=$1" \
        --data-urlencode 'button=current' \
        "$base/admin/install/submit-storage-key" >"$page"
}

for unit in apache2.service mariadb.service postfix.service multi-user.target; do
    systemctl --quiet is-active "$unit"
done
for unit in apache2.service mariadb.service postfix.service; do
    systemctl --quiet is-enabled "$unit"
done
apache2ctl -t

source_manifest=/usr/local/share/turnkey/oscommerce-source
grep -Fxq 'version=4.14.63493' "$source_manifest"
grep -Fxq 'commit=48d31a361b614cfa66e505d4e8345afd9e30ad79' "$source_manifest"
grep -Fxq 'archive_sha256=bc3916d1e41ab992f86a2bd56bdc65786c70974686ae312f8814b2083a78ea84' "$source_manifest"
oscommerce_version=$(php -r \
    "include '/var/www/oscommerce/includes/version.php'; echo PROJECT_VERSION_MAJOR . '.' . PROJECT_VERSION_MINOR . '.' . PROJECT_VERSION_PATCH;")
test "$oscommerce_version" = 4.14.63493
test "$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT CONCAT(platform_url, '|', ssl_enabled) FROM platforms WHERE platform_id=1")" = \
    'localhost|2'
! grep -Fqx 'RewriteCond %{HTTP_HOST} !^www\.' \
    /var/www/oscommerce/.htaccess

login_admin
category_id=$(mariadb oscommerce --batch --skip-column-names --execute \
    'SELECT categories_id FROM products_to_categories WHERE products_id=1 ORDER BY categories_id LIMIT 1')
test -n "$category_id"
curl --insecure --fail --silent --show-error --location \
    --cookie "$cookie" --cookie-jar "$cookie" \
    "$base/admin/categories/productedit?category_id=$category_id" >"$page"
grep -q 'save_product_form' "$page"

marker="TurnKey v19 acceptance product $$"
serialize_product_form "$marker"
post_product_form
product_id=$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT products_id FROM products_description WHERE products_name='$marker' AND language_id=1 AND platform_id=1 AND department_id=0")
[[ $product_id =~ ^[1-9][0-9]*$ ]]
product_created=1

db_name=$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT products_name FROM products_description WHERE products_id=$product_id AND language_id=1 AND platform_id=1 AND department_id=0")
test "$db_name" = "$marker"
curl --insecure --fail --silent --show-error \
    "$base/catalog/product?products_id=$product_id" >"$page"
grep -Fq "$marker" "$page"

curl --insecure --fail --silent --show-error \
    --cookie "$cookie" --cookie-jar "$cookie" \
    --data-urlencode "products_id=$product_id" \
    "$base/admin/categories/productdelete" >"$page"
test "$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT COUNT(*) FROM products WHERE products_id=$product_id")" = 0
test "$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT COUNT(*) FROM products_description WHERE products_id=$product_id")" = 0
curl --insecure --silent --show-error \
    "$base/catalog/product?products_id=$product_id" >"$page"
! grep -Fq "$marker" "$page"
product_created=0

curl --insecure --fail --silent --show-error --location \
    --cookie "$cookie" --cookie-jar "$cookie" \
    "$base/admin/install" >"$page"
grep -q 'App Shop' "$page"
grep -qi 'System update' "$page"

original_storage_key_hex=$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT HEX(storage_key) FROM admin WHERE admin_username='admin'")
test -z "$original_storage_key_hex"
cp --preserve=all -- "$backend_params" "$backend_params_backup"
config_changed=1
python3 - "$fixture_port_file" "$fixture_metadata" "$fixture_request" <<'PYTHON' &
import http.server
import json
import sys

port_file, metadata_file, request_file = sys.argv[1:]
metadata = b'{"updates":[{"filename":"system-update-4.14.63494-fixture.zip","version":"4.14.63494"}]}'


class Handler(http.server.BaseHTTPRequestHandler):
    def send_json(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/app-api-types.json":
            self.send_json(b'{"types":[]}')
        elif self.path == "/app-api-server":
            self.send_json(b'{}')
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path != "/app-api-server/system-updates":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        request = {
            "authorization": self.headers.get("Authorization", ""),
            "body": json.loads(self.rfile.read(length)),
        }
        with open(request_file, "w", encoding="utf-8") as destination:
            json.dump(request, destination, sort_keys=True)
        with open(metadata_file, "wb") as destination:
            destination.write(metadata)
        self.send_json(metadata)

    def log_message(self, format, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="ascii") as destination:
    destination.write(str(server.server_port))
server.serve_forever()
PYTHON
fixture_pid=$!
for _ in $(seq 1 50); do
    test -s "$fixture_port_file" && break
    sleep 0.1
done
fixture_port=$(cat "$fixture_port_file")
[[ $fixture_port =~ ^[1-9][0-9]*$ ]]
printf "<?php\nreturn ['appStorage.url' => 'http://127.0.0.1:%s/'];\n" \
    "$fixture_port" >"$backend_params"
systemctl reload apache2.service

set_storage_key turnkey-v19-disposable-fixture
storage_key_changed=1
test "$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT storage_key FROM admin WHERE admin_username='admin'")" = \
    turnkey-v19-disposable-fixture

installed_update_count=$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT COUNT(*) FROM installer WHERE archive_type='update'")
updater_revision=$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT configuration_value FROM configuration WHERE configuration_key='MIGRATIONS_DB_REVISION'")
[[ $updater_revision =~ ^[1-9][0-9]*$ ]]
version_file_sha=$(sha256sum /var/www/oscommerce/includes/version.php | awk '{print $1}')
curl --insecure --fail --silent --show-error \
    --cookie "$cookie" --cookie-jar "$cookie" \
    "$base/admin/install/updates" >"$page"
test -s "$fixture_metadata"
test -s "$fixture_request"
grep -Fq "4.14.$updater_revision" "$page"
grep -Fq 'system-update-4.14.63494-fixture.zip' "$page"
printf '%s  %s\n' \
    f5afdfff4bc89f8233302ce9e03821f76c77d9e6f7f6a0808fac388482531e41 \
    "$fixture_metadata" | sha256sum --check --strict
python3 - "$fixture_request" "$updater_revision" <<'PYTHON'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    request = json.load(source)
assert request == {
    "authorization": "Bearer turnkey-v19-disposable-fixture:" +
        request["authorization"].rsplit(":", 1)[1],
    "body": {"version": sys.argv[2]},
}
assert len(request["authorization"].rsplit(":", 1)[1]) == 32
PYTHON
test "$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT COUNT(*) FROM installer WHERE archive_type='update'")" = \
    "$installed_update_count"
test "$(sha256sum /var/www/oscommerce/includes/version.php | awk '{print $1}')" = \
    "$version_file_sha"

set_storage_key ''
test -z "$(mariadb oscommerce --batch --skip-column-names --execute \
    "SELECT storage_key FROM admin WHERE admin_username='admin'")"
storage_key_changed=0
cp --preserve=all -- "$backend_params_backup" "$backend_params"
config_changed=0
systemctl reload apache2.service
kill "$fixture_pid"
wait "$fixture_pid" || true
fixture_pid=

curl --insecure --fail --silent --show-error \
    https://127.0.0.1:12322/ >"$page"
grep -qi Adminer "$page"
curl --insecure --silent --show-error --location \
    --cookie-jar "$adminer_cookie" --cookie "$adminer_cookie" \
    --data-urlencode 'auth[driver]=server' \
    --data-urlencode 'auth[server]=localhost' \
    --data-urlencode 'auth[username]=adminer' \
    --data-urlencode "auth[password]=$db_password" \
    --data-urlencode 'auth[db]=oscommerce' \
    https://127.0.0.1:12322/ >"$page"
grep -qi MariaDB "$page"
grep -qi Logout "$page"
! grep -qi 'Access denied\|Invalid credentials' "$page"

dpkg-query -W webmin-apache webmin-phpini webmin-mysql >/dev/null
curl --insecure --fail --silent --show-error --head \
    https://127.0.0.1:12321/ >/dev/null
ss -ltn | grep -Eq '127\.0\.0\.1:25[[:space:]]'

apache_version=$(dpkg-query -W -f='${Version}' apache2)
mariadb_version=$(dpkg-query -W -f='${Version}' mariadb-server)
php_package=$(dpkg-query -W -f='${Version}' php)
php_version=$(php -r 'echo PHP_VERSION;')
before="$apache_version|$mariadb_version|$php_package"
apt-get update >/dev/null
for package in apache2 mariadb-server php php-gd php-intl php-curl php-zip \
        php-xml php-mbstring php-soap php-xmlrpc; do
    candidate=$(apt-cache policy "$package" | awk '/Candidate:/ {print $2}')
    test -n "$candidate"
    test "$candidate" != '(none)'
done
after="$(dpkg-query -W -f='${Version}' apache2)|$(dpkg-query -W -f='${Version}' mariadb-server)|$(dpkg-query -W -f='${Version}' php)"
test "$after" = "$before"
grep -Rqs '^Suites: trixie' /etc/apt/sources.list.d
! grep -Rqi bookworm /etc/apt/sources.list.d

upstream_head=$(python3 - <<'PYTHON'
import json
import urllib.request

request = urllib.request.Request(
    "https://api.github.com/repos/osCommerce/osCommerce-V4/commits/main",
    headers={"Accept": "application/vnd.github+json", "User-Agent": "turnkey-v19-test"},
)
with urllib.request.urlopen(request) as response:
    print(json.load(response)["sha"])
PYTHON
)
[[ $upstream_head =~ ^[0-9a-f]{40}$ ]]

cat >"$result" <<EOF
package_source=Debian 13 Trixie APT repositories for Apache, PHP, MariaDB and supporting modules; official osCommerce GitHub archive pinned at commit 48d31a361b614cfa66e505d4e8345afd9e30ad79
installed_version=osCommerce $oscommerce_version; PHP $php_version ($php_package); apache2 $apache_version; mariadb-server $mariadb_version
runtime_checks=normal init; HTTPS catalog; administrator login; web product create with MariaDB and public catalog readback; web product deletion; App Shop update check; Adminer database login; Webmin endpoint and modules; local Postfix listener
updater_command=apt-get update and apt-cache policy for Debian packages; authenticated osCommerce App Shop update check against a deterministic local fixture; official GitHub main metadata query
updater_result=signed Debian metadata refreshed with installed packages unchanged; installed osCommerce 4.14.63493 at updater revision $updater_revision and eligible fixture 4.14.63494 identified with metadata SHA-256 f5afdfff4bc89f8233302ce9e03821f76c77d9e6f7f6a0808fac388482531e41 and no application change; official upstream head $upstream_head
updater_channel=Debian and TurnKey Trixie APT repositories; osCommerce App Shop System update channel; official osCommerce GitHub main branch
integrity_evidence=build manifest records official source commit and SHA-256 bc3916d1e41ab992f86a2bd56bdc65786c70974686ae312f8814b2083a78ea84; App Shop fixture metadata SHA-256 verified; version file and applied-update count unchanged by update check; APT accepted signed metadata; no Bookworm source remained
EOF
