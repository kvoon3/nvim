check: fmt lint ls

fmt:
    stylua .

lint:
    selene .

ls:
    ls-lint
