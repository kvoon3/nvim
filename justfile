check: fmt lint

fmt:
    stylua .

lint:
    selene .
