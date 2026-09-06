# A rack app for puma (puma -b tcp://127.0.0.1:PORT config.ru). Rack 3: lowercase header names.
run ->(env) { [200, { 'content-type' => 'text/plain', 'content-length' => '13' }, ["hello, world\n"]] }
