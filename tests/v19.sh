#!/bin/bash
set -euo pipefail
# v19.sh by Daniele Lolli (UncleDan) feat. Claude AI - Release 19.0 - 2026-10-10 13-06-02

result=${TKL_TEST_RESULT:?}
password=${TKL_TEST_APP_PASS:?}
work=/run/tkl-v19-tests/moodle
base=https://www.example.com
curl_args=(-kfsS --resolve www.example.com:443:127.0.0.1)
mkdir -p "$work"

# installation paths and expected release, as recorded at build time
. /etc/turnkey-moodle-release
test -n "$MOODLE_PATH" && test -n "$MOODLE_DATA_PATH"

# Moodle >= 5.1 serves public/, older releases MOODLE_PATH itself
pubroot=$MOODLE_PATH
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
runuser -u www-data -- test ! -w "$MOODLE_PATH/config.php"
runuser -u www-data -- test ! -w "$MOODLE_PATH/theme"
# .git is root only (tkl-set-moodle-perms 26.10)
git_head="$MOODLE_PATH/.git/HEAD"
test -f "$git_head"
runuser -u www-data -- test ! -r "$git_head"
runuser -u www-data -- touch "$MOODLE_DATA_PATH/.tkl-v19-write-test"
runuser -u www-data -- rm "$MOODLE_DATA_PATH/.tkl-v19-write-test"
# upgrade helpers shipped with the appliance
for script in tkl-lamp74-to-lamp81 tkl-lamp81-to-lamp tkl-moodle-upgrade; do
    "/usr/local/bin/$script" --help >/dev/null
done
/usr/local/bin/tkl-set-moodle-perms --dry-run >"$work/perms-dry-run.txt"
grep -Fq 'root-owned code' "$work/perms-dry-run.txt"
test "$(runuser -u www-data -- php "$MOODLE_PATH/admin/cli/cfg.php" \
    --name=noreplyaddress --no-eol)" = noreply@example.com
runuser -u www-data -- php "$MOODLE_PATH/admin/cli/cron.php" --keep-alive=0

release=$(sed -n "s/^\$release *= *'\([^']*\)'.*/\1/p" \
    "$pubroot/version.php")
test -n "$release"
# expected tag/branch/commit (loaded above)
test -n "$MOODLE_BRANCH" && test -n "$MOODLE_COMMIT"
branch=$MOODLE_BRANCH
commit=$(git -C "$MOODLE_PATH" rev-parse HEAD)
test "$commit" = "$MOODLE_COMMIT"
# local branch checked out and tracking the upstream stable branch
test "$(git -C "$MOODLE_PATH" symbolic-ref --short HEAD)" = "$branch"
test "$(git -C "$MOODLE_PATH" rev-parse --abbrev-ref '@{upstream}')" = \
    "origin/$branch"
# version.php must belong to the same branch (MOODLE_400_STABLE => '400')
vbranch=$(sed -n "s/^\$branch *= *'\([0-9]*\)'.*/\1/p" "$pubroot/version.php")
test "MOODLE_${vbranch}_STABLE" = "$branch"
# installed code is exactly the release tag (e.g. v4.0.5 => "4.0.5 (Build: ...)")
tag=$MOODLE_TAG
test "$(git -C "$MOODLE_PATH" rev-parse "${tag}^{commit}")" = "$commit"
test "${release%% *}" = "$MOODLE_VERSION"
systemctl restart mariadb.service apache2.service
curl "${curl_args[@]}" -L -b "$work/cookies" "$base/my/" \
    >"$work/dashboard-after-restart.html"
grep -Eq 'login/logout\.php\?sesskey=[[:alnum:]]+' \
    "$work/dashboard-after-restart.html"
! grep -F -- "$password" /var/log/inithooks.log

cat >"$result" <<EOF
package_source=official Moodle tag $tag on $branch (git clone) commit $commit
installed_version=$release
runtime_checks=Apache and MariaDB services, firstboot completion, HTTPS admin login, dashboard session across restart, cron, ownership helper and boundaries, password log hygiene
updater_command=supervised git pull on $branch followed by tkl-set-moodle-perms --fix
updater_result=installed commit unchanged during QA
updater_channel=official Moodle $branch branch
integrity_evidence=installed Git HEAD $commit matches tag $tag on $branch tracking origin/$branch
EOF
