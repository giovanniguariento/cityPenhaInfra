<?php
/**
 * Block unauthenticated listing of WordPress users via REST API.
 *
 * Public GET /wp-json/wp/v2/users exposes usernames for brute-force attacks.
 * Backend uses POST /users and POST /users/{id} with Application Passwords (unaffected).
 * Gutenberg uses GET /users?who=authors for logged-in editors (unaffected).
 */
add_filter(
	'rest_endpoints',
	static function ( $endpoints ) {
		$routes = array(
			'/wp/v2/users',
			'/wp/v2/users/(?P<id>[\d]+)',
			'/wp/v2/users/me',
		);

		foreach ( $routes as $route ) {
			if ( ! isset( $endpoints[ $route ] ) ) {
				continue;
			}

			foreach ( $endpoints[ $route ] as $index => $handler ) {
				if ( ! isset( $handler['permission_callback'] ) || ! is_callable( $handler['permission_callback'] ) ) {
					continue;
				}

				$original = $handler['permission_callback'];
				$endpoints[ $route ][ $index ]['permission_callback'] = static function ( $request ) use ( $original ) {
					if ( 'GET' === $request->get_method() && ! is_user_logged_in() ) {
						return new WP_Error(
							'rest_forbidden',
							__( 'Sorry, you are not allowed to list users.' ),
							array( 'status' => 401 )
						);
					}

					return call_user_func( $original, $request );
				};
			}
		}

		return $endpoints;
	}
);
