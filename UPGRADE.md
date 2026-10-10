# Upgrade path: Moodle 4.0.5 (PHP 7.4) -> Moodle 5.3 (Debian PHP)

The upgrade helpers in `/usr/local/bin` are independent: they never call
each other and never change the maintenance mode. Run the commands below
as root, one at a time, in this order.

Each PHP helper stops if the installed Moodle is not compatible with the
PHP version it installs; `tkl-moodle-upgrade` stops if the target branch
does not support the installed PHP or cannot be reached from the installed
Moodle release.

Before starting, back up the database, `/var/moodledata` and
`/var/www/moodle` (or take a snapshot of the VM).

## Steps

```bash
# 1. Maintenance ON
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --enable

# 2. Moodle 4.0 -> 4.1 (PHP 7.4)
tkl-moodle-upgrade MOODLE_401_STABLE

# 3. Maintenance OFF, then check the site
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --disable

# 4. PHP 7.4 -> PHP 8.1 (sury.org), then check the site
tkl-lamp74-to-lamp81

# 5. Maintenance ON
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --enable

# 6. Moodle 4.1 -> 4.5 (PHP 8.1)
tkl-moodle-upgrade MOODLE_405_STABLE

# 7. Maintenance OFF, then check the site
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --disable

# 8. Maintenance ON (the site stays offline until the last step: Moodle 4.5 does not support the Debian PHP version)
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --enable

# 9. PHP 8.1 -> Debian PHP, sury.org disabled
tkl-lamp81-to-lamp

# 10. Moodle 4.5 -> 5.3 (Debian PHP); the Apache vhost is moved to public/
tkl-moodle-upgrade MOODLE_503_STABLE

# 11. Maintenance OFF, then check the site
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --disable
```

## Maintenance mode from the command line

The same commands work for every Moodle release from 4.0 to 5.3 (from 5.1
on, `admin/cli` is still in the Moodle root, not in `public/`).

```bash
# enable (site closed to everyone, administrators included)
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --enable

# disable
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --disable
```

Other options of `maintenance.php`: `--enablelater=MINUTES` (scheduled,
with a notice to users) and `--enableold` (classic maintenance mode,
administrators can still log in). `--disable` disables both.

If `--disable` cannot run (e.g. the installed code does not run on the
current PHP version), the CLI maintenance mode can be removed by deleting
the file it creates:

```bash
rm /var/moodledata/climaintenance.html
```

## Minor updates within the installed branch

```bash
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --enable
tkl-moodle-upgrade
runuser -u www-data -- php /var/www/moodle/admin/cli/maintenance.php --disable
```

## Notes

- Paths are the appliance defaults; the actual ones are recorded in
  `/etc/turnkey-moodle-release` (`MOODLE_PATH`, `MOODLE_DATA_PATH`).
- Moodle is upgraded with Git as per "Git for Administrators":
  https://docs.moodle.org/en/Git_for_Administrators
