check: fmt lint ls test

fmt:
    stylua --check .

format:
    stylua .

lint:
    selene .

ls:
    ls-lint

test:
    @plugin_data="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"; data=$(mktemp -d); trap 'rm -rf "$data"' EXIT; XDG_DATA_HOME="$data" NVIM_TEST_PLUGIN_DATA="$plugin_data" nvim --headless -u tests/minimal.lua -c 'PlenaryBustedDirectory tests/ {minimal_init = "tests/minimal.lua"}' -c 'qall!'

