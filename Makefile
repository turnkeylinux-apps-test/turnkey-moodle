COMMON_CONF = apache-credit

PHP_MAX_INPUT_VARS = 5000
PHP_VERSION = 7.4
CREDIT_LOCATION = ~ "^/(?!(lib/editor))"

include $(FAB_PATH)/common/mk/turnkey/lamp.mk
include $(FAB_PATH)/common/mk/turnkey/composer.mk
include $(FAB_PATH)/common/mk/turnkey.mk
