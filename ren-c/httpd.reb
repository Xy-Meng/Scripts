Rebol [
	Title: "Web Server Scheme for Ren-C"
	Author: "Christopher Ross-Gill"
	Date: 11-Mar-2018
	File: %httpd.reb
	Home: https://github.com/rgchris/Scripts
	Version: 0.3.3
	Purpose: "An elementary Web Server scheme for creating fast prototypes"
	Rights: http://opensource.org/licenses/Apache-2.0
	Type: module
	Name: rgchris.httpd
	History: [
		16-Mar-2018 0.3.3 "Add COMPRESS? option"
		14-Mar-2018 0.3.2 "Closes connections (TODO: support Keep-Alive)"
		11-Mar-2018 0.3.1 "Reworked to support KILL?"
		23-Feb-2017 0.3.0 "Adapted from Rebol 2"
		06-Feb-2017 0.2.0 "Include HTTP Parser/Dispatcher"
		12-Jan-2017 0.1.0 "Original Version"
	]
]

net-utils: reduce [
	; 'net-log proc [message [block! string!]][print block? message then [unspaced message] else [message]]
	'net-log _
]

as-string: func [binary [binary!] /local mark][
	mark: binary
	while [mark: invalid-utf8? mark][
		mark: change/part mark #{EFBFBD} 1
	]
	to string! binary
]

sys/make-scheme [
	title: "HTTP Server"
	name: 'httpd

	spec: make system/standard/port-spec-head [port-id: actions: _]

	wake-client: func [event [event!] /local client request response this][
		client: event/port

		switch event/type [
			read [
				net-utils/net-log ["Instance [" client/locals/instance: me + 1 "]"]

				case [
					not client/locals/parent/locals/open? [
						close client
						client/locals/parent
					]

					find client/data #{0D0A0D0A} [
						transcribe client
						dispatch client
					]

					true [
						read client
					]
				]

				client
			]

			wrote [
				case [
					send-chunk client [
						client
					]

					client/locals/response/kill? [
						close client
						wake-up client/locals/parent make event! [
							type: 'close
							port: client/locals/parent
						]
					]

					client/locals/response/close? [
						close client
					]

					true [
						client
					]
				]
			]

			close [
				close client
			]

			(
				net-utils/net-log ["Unexpected Client Event: " uppercase form event/type]
				client
			)
		]
	]

	init: func [server [port!] /local spec][
		spec: server/spec

		case [
			url? spec/ref []
			block? spec/actions []
			parse spec/ref [
				set-word! lit-word!
				integer! block!
			][
				spec/port-id: spec/ref/3
				spec/actions: spec/ref/4
			]
			/else [
				do make error! "Server lacking core features."
			]
		]

		server/locals: make object! [
			handler: subport: open?: _
			clients: make block! 1024
		]

		server/locals/handler: procedure [
			request [object!]
			response [object!]
		] compose [
			render: get in response 'render
			redirect: get in response 'redirect
			print: get in response 'print

			(
				block? server/spec/actions
					then [server/spec/actions]
					else [default-response]
			)
		]

		server/locals/subport: make port! [scheme: 'tcp]

		server/locals/subport/spec/port-id: spec/port-id

		server/locals/subport/locals: make object! [
			instance: 0
			request: response: _
			wire: make binary! 4096
			parent: :server
		]

		server/locals/subport/awake: func [event [event!] /local client][
			switch event/type [
				accept [
					client: first event/port
					client/awake: :wake-client
					read client
					event
				]

				(false)
			]
		]

		server/awake: func [event [event!]][
			switch event/type [
				close [
					close event/port
					true
				]

				(event/port)
			]
		]

		server
	]

	actor: [
		open: func [server [port!]][
			net-utils/net-log ["Server running on port no. " server/spec/port-id]
			open server/locals/subport
			server/locals/open?: yes
			server
		]

		close: func [server [port!]][
			server/awake: server/locals/subport/awake: _
			server/locals/open?: no
			close server/locals/subport
			insert system/ports/system/data server
			; ^^^ would like to know why...
			server
		]
	]

	default-response: [probe request/action]

	request-prototype: make object! [
		raw: _
		version: 1.1
		method: "GET"
		action: headers: http-headers: _
		oauth: target: binary: content: length: timeout: _
		type: 'application/x-www-form-urlencoded
		server-software: unspaced [
;		   system/script/header/title " v" system/script/header/version " "
			"Rebol/" system/product " v" system/version
		]
		server-name: gateway-interface: _
		server-protocol: "http"
		server-port: request-method: request-uri:
		path-info: path-translated: script-name: query-string:
		remote-host: remote-addr: auth-type:
		remote-user: remote-ident: content-type: content-length: _
		error: _
	]

	response-prototype: make object! [
		status: 404
		content: "Not Found"
		location: _
		type: "text/html"
		length: 0
		kill?: false
		close?: true
		compress?: false

		render: func [response [string! binary!]][
			status: 200
			content: response
		]

		print: func [response [string!]][
			status: 200
			content: response
			type: "text/plain"
		]

		redirect: [target [url!] /as status [integer!]][
			status: any [:status 301]
			location: target
		]
	]

	transcribe: use [
		space request-action request-path request-query
		header-prototype header-feed header-name header-part
	][
		request-action: ["HEAD" | "GET" | "POST" | "PUT" | "DELETE"]

		request-path: use [chars][
			chars: complement charset [#"^@" - #" " #"?"]
			[some chars]
		]

		request-query: use [chars][
			chars: complement charset [#"^@" - #" "]
			[some chars]
		]

		header-feed: [newline | crlf]

		header-part: use [chars][
			chars: complement charset [#"^(00)" - #"^(1F)"]
			[some chars any [header-feed some " " some chars]]
		]

		header-name: use [chars][
			chars: charset ["_-0123456789" #"a" - #"z" #"A" - #"Z"]
			[some chars]
		]

		space: use [space][
			space: charset " ^-"
			[some space]
		]

		header-prototype: context [
			Accept: "*/*"
			Connection: "close"
			User-Agent: Content-Length: Content-Type: Authorization: Range: Referer: _
		]

		transcribe: func [
			client [port!]
			/local request name value pos
		][
			client/locals/request: make request-prototype [
				either parse raw: client/data [
					copy method request-action space
					copy request-uri [
						copy target request-path opt [
							"?" copy query-string request-query
						]
					] space
					"HTTP/" copy version ["1.0" | "1.1"]
					header-feed
					(headers: make block! 10)
					some [
						copy name header-name ":" any " "
						copy value header-part header-feed
						(
							name: as-string name
							value: as-string value
							append headers reduce [to set-word! name value]
							switch name [
								"Content-Type" [content-type: value]
								"Content-Length" [length: content-length: value]
							]
						)
					]
					header-feed content: to end (
						binary: copy :content
						content: does [content: as-string binary]
					)
				][
					version: to string! :version
					request-method: method: to string! :method
					path-info: target: as-string :target
					action: reform [method target]
					request-uri: as-string request-uri
					server-port: query/mode client 'local-port
					remote-addr: query/mode client 'remote-ip

					headers: make header-prototype http-headers: new-line/skip headers true 2

					type: if string? headers/Content-Type [
						copy/part type: headers/Content-Type any [
							find type ";"
							tail type
						]
					]

					length: content-length: any [
						attempt [length: to integer! length]
						0
					]

					net-utils/net-log action
				][
					; action: target: request-method: query-string: binary: content: request-uri: _
					net-utils/net-log error: "Could Not Parse Request"
				]
			]
		]
	]

	dispatch: use [status-codes build-header hdr][
		status-codes: [
			200 "OK" 201 "Created" 204 "No Content"
			301 "Moved Permanently" 302 "Moved temporarily" 303 "See Other" 307 "Temporary Redirect"
			400 "Bad Request" 401 "No Authorization" 403 "Forbidden" 404 "Not Found" 411 "Length Required"
			500 "Internal Server Error" 503 "Service Unavailable"
		]

		build-header: func [response [object!]][
			append make binary! 1024 spaced collect [
				case/all [
					not find status-codes response/status [
						response/status: 500
					]
					any [
						not find [binary! string!] to word! type-of response/content
						empty? response/content
					][
						response/content: " "
					]
				]

				keep ["HTTP/1.1" response/status select status-codes response/status]
				keep [cr lf "Content-Type:" response/type]
				keep [cr lf "Content-Length:" length-of response/content]
				case/all [
					response/compress? [
						keep [cr lf "Content-Encoding:" "gzip"]
					]
					response/location [
						keep [cr lf "Location:" response/location]
					]
					response/close? [
						keep [cr lf "Connection:" "close"]
					]
				]
				keep [cr lf cr lf]
			]
		]

		function [client [port!]][
			client/locals/response: response: make response-prototype []
			client/locals/parent/locals/handler client/locals/request response

			if response/compress? [
				response/content: compress/gzip response/content
			]

			case [
				error? outcome: trap [write client hdr: build-header response][
					either all [
						outcome/code = 5020
						outcome/id = 'write-error
						find [32 104] outcome/arg2
					][
						net-utils/net-log ["Response headers not sent to client: reason #" outcome/arg2]
					][
						fail :outcome
					]
				]
			]

			insert client/locals/wire response/content
		]
	]

	send-chunk: function [port [port!]][
		;; Trying to send data > 32'000 bytes at once will trigger R3's internal
		;; chunking (which is buggy, see above). So we cannot use chunks > 32'000
		;; for our manual chunking.
		;;
		;; But let increase chunk size
		;; to see if that bug exists again!
		case [
			empty? port/locals/wire [_]

			error? outcome: trap [
				write port take/part port/locals/wire 32'000 ; 2'000'000
			][
				;; only mask some errors:
				all [
					outcome/code = 5020
					outcome/id = 'write-error
					find [32 104] outcome/arg2
				]
				then [
					net-utils/net-log ["Part or whole of response not sent to client: reason #" outcome/arg2]
					clear port/locals/wire
					_
				]
				else [
					fail :outcome
				]
			]

			true [:outcome] ; is port
		]
	]
]
