#!/bin/bash
set -euo pipefail
# v19.sh by Daniele Lolli (UncleDan) feat. Claude AI - Release 19.0 - 2026-10-02 17-05-39

result=${TKL_TEST_RESULT:?}
password=${TKL_TEST_APP_PASS:?}
work=/run/tkl-v19-tests/moodle
base=https://www.example.com
curl_args=(-kfsS --resolve www.example.com:443:127.0.0.1)
mkdir -p "$work"

# Moodle >= 5.1 serves public/, older releases the webroot itself
pubroot=/var/www/moodle
[ -d "$pubroot/public" ] && pubroot=$pubroot/public

systemctl --quiet is-active apache2.service
systemctl --quiet is-active mariadb.service
grep -q '\[40moodle\] successfully completed' /var/log/inithooks.log
curl "${curl_args[@]}" -c "$work/cookies" "$base/login/index.php" \
    >"$work/login.html"
grep -Eqi 'moodle|log in' "$work/login.html"
token=$(sed -n 's/.*name="logintoken" value="\([^"]*\)".*/\1/p' \
    "$work/login.html" | head -1)
test -n "$token"

curl "${curl_args[@]}" -b "$work/cookies" -c "$work/cookies" \
    -D "$work/login.headers" -o "$work/login-response.html" \
    --data-urlencode "logintoken=$token" \
    --data-urlencode username=admin \
    --data-urlencode "password=$password" \
    "$base/login/index.php"
grep -Eq '^HTTP/[^ ]+ 303([[:space:]]|$)' "$work/login.headers"
! grep -Eqi '^location: .*/login/' "$work/login.headers"
curl "${curl_args[@]}" -L -b "$work/cookies" "$base/my/" >"$work/dashboard.html"
grep -Eq 'login/logout\.php\?sesskey=[[:alnum:]]+' "$work/dashboard.html"

runuser -u www-data -- test ! -w "$pubroot/index.php"
runuser -u www-data -- test ! -w /var/www/moodle/config.php
runuser -u www-data -- test ! -w /var/www/moodle/theme
runuser -u www-data -- touch /var/moodledata/.tkl-v19-write-test
runuser -u www-data -- rm /var/moodledata/.tkl-v19-write-test
/usr/local/bin/tkl-set-moodle-perms --dry-run >"$work/perms-dry-run.txt"
grep -Fq 'root-owned code' "$work/perms-dry-run.txt"
test "$(runuser -u www-data -- php /var/www/moodle/admin/cli/cfg.php \
    --name=noreplyaddress --no-eol)" = noreply@example.com
runuser -u www-data -- php /var/www/moodle/admin/cli/cron.php --keep-alive=0

release=$(sed -n "s/^\$release *= *'\([^']*\)'.*/\1/p" \
    "$pubroot/version.php")
test -n "$release"
# expected release/commit as pinned at build time by conf.d/main
. /etc/turnkey-moodle-release
test -n "$MOODLE_VERSION" && test -n "$MOODLE_COMMIT"
tag=$MOODLE_TAG
branch=$(echo "$MOODLE_VERSION" | \
    awk -F. '{printf "MOODLE_%d%02d_STABLE", $1, $2}')
commit=$(git -C /var/www/moodle rev-parse HEAD)
test "$commit" = "$MOODLE_COMMIT"
# version.php must match the pinned release (e.g. "5.3.0 (Build: ...)")
test "${release%% *}" = "$MOODLE_VERSION"
systemctl restart mariadb.service apache2.service
curl "${curl_args[@]}" -L -b "$work/cookies" "$base/my/" \
    >"$work/dashboard-after-restart.html"
grep -Eq 'login/logout\.php\?sesskey=[[:alnum:]]+' \
    "$work/dashboard-after-restart.html"
! grep -F -- "$password" /var/log/inithooks.log

cat >"$result" <<EOF
package_source=official Moodle $branch tag $tag commit $commit
installed_version=$release
runtime_checks=Apache and MariaDB services, firstboot completion, HTTPS admin login, dashboard session across restart, cron, ownership helper and boundaries, password log hygiene
updater_command=supervised Moodle git upgrade followed by tkl-set-moodle-perms --fix
updater_result=installed commit unchanged during QA
updater_channel=official Moodle $branch branch
integrity_evidence=installed Git HEAD $commit matches pinned tag $tag
EOF
