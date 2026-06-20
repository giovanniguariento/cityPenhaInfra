<?php
/**
 * WordPress 6.8+ enables Application Passwords only when is_ssl() or
 * WP_ENVIRONMENT_TYPE is "local". Backend REST uses HTTP on the internal
 * Docker network (wordpress-nginx:8080).
 */
add_filter( 'wp_is_application_passwords_available', '__return_true' );
