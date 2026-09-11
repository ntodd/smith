# The -r arguments load the assemblies with --no-export before running ExUnit.
ExUnit.start()
Code.require_file("../support/verification.exs", __DIR__)
for file <- Path.wildcard(Path.join(__DIR__, "*_checks.exs")), do: Code.require_file(file)
for file <- Path.wildcard(Path.join(__DIR__, "*_test.exs")), do: Code.require_file(file)
