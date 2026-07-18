check: fmt lint ls test

fmt:
    stylua .

lint:
    selene .

ls:
    ls-lint

test:
    nvim --headless -u tests/minimal.lua -c 'PlenaryBustedDirectory tests/ {minimal_init = "tests/minimal.lua"}' -c 'qall!'

