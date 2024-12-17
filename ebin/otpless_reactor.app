{application, 'otpless_reactor', [
	{description, "The gen_statem behavior for OTPless Erlang."},
	{vsn, "0.1.0"},
	{modules, ['reactor']},
	{registered, []},
	{applications, [kernel,stdlib,spawn_mode]},
	{optional_applications, []},
	{env, []}
]}.