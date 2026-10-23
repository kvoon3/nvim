check: fmt lint ls test

fmt:
    stylua --check .

format:
    stylua .

lint:
    selene .

ls:
    ls-lint

# Build the jieba-rs shared library and install it into stdpath('data').
build-native:
    cargo build --release --manifest-path lua/jieba-native/rust/Cargo.toml
    @dst="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/jieba-native"; \
        mkdir -p "$dst"; \
        for lib in lua/jieba-native/rust/target/release/libjieba_native.dylib\
                   lua/jieba-native/rust/target/release/libjieba_native.so; do \
            [ -f "$lib" ] && cp "$lib" "$dst/"; \
        done; \
        ls -l "$dst"

test:
    @plugin_data="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"; data=$(mktemp -d); trap 'rm -rf "$data"' EXIT; XDG_DATA_HOME="$data" NVIM_TEST_PLUGIN_DATA="$plugin_data" nvim --headless --noplugin -u tests/minimal.lua -c 'lua MiniTest.run()'

