//! Minimal C-ABI face for `jieba-rs`, loaded from Neovim through LuaJIT FFI.
//!
//! The Lua side hands in a byte string and gets back (start, end) byte offset
//! pairs instead of strings: nothing is allocated across the FFI boundary and
//! tokens stay slices of the original buffer.

use jieba_rs::Jieba;
use std::os::raw::{c_int, c_void};
use std::slice;

/// Builds the segmenter (dictionary trie) and hands ownership to the caller.
/// Returns null only if the boxed pointer cannot be created.
#[unsafe(no_mangle)]
pub extern "C" fn jieba_native_new() -> *mut c_void {
    let jieba = Box::new(Jieba::new());
    Box::into_raw(jieba).cast()
}

/// Drops a handle returned by `jieba_native_new`. Null is a no-op.
///
/// # Safety
/// `handle` must come from `jieba_native_new` and must not be used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jieba_native_free(handle: *mut c_void) {
    if handle.is_null() {
        return;
    }
    drop(unsafe { Box::from_raw(handle.cast::<Jieba>()) });
}

/// Segments `len` bytes at `text` and writes `(start, end)` byte offset pairs
/// into `out`, which must hold at least `cap` `u32` values.
///
/// Returns the number of `u32` values needed (2 per token). When the return
/// value is greater than `cap`, nothing was written and the caller should call
/// again with a larger buffer. Passing a null `out` is the sizing query.
///
/// Invalid UTF-8 yields one token spanning the whole input so that callers can
/// still walk the string without losing bytes.
///
/// # Safety
/// `text` must point to `len` readable bytes and `out` to `cap` writable `u32`s.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jieba_native_cut(
    handle: *const c_void,
    text: *const u8,
    len: usize,
    out: *mut u32,
    cap: usize,
    use_hmm: c_int,
) -> usize {
    if handle.is_null() || (text.is_null() && len > 0) {
        return 0;
    }
    let jieba = unsafe { &*handle.cast::<Jieba>() };
    let bytes = unsafe { slice::from_raw_parts(text, len) };

    let offsets: Vec<(u32, u32)> = match std::str::from_utf8(bytes) {
        Ok(input) => jieba
            .cut(input, use_hmm != 0)
            .into_iter()
            .map(|token| (token.byte_start as u32, token.byte_end as u32))
            .collect(),
        Err(_) => vec![(0, len as u32)],
    };

    let needed = offsets.len() * 2;
    if out.is_null() || cap < needed {
        return needed;
    }
    for (i, (start, end)) in offsets.iter().enumerate() {
        unsafe {
            *out.add(i * 2) = *start;
            *out.add(i * 2 + 1) = *end;
        }
    }
    needed
}

/// Exposed for the Lua glue's sanity check; never null.
#[unsafe(no_mangle)]
pub extern "C" fn jieba_native_version() -> *const u8 {
    static VERSION: &str = concat!("jieba-rs ", "0.11");
    VERSION.as_ptr()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr;

    fn cut(text: &str, hmm: bool) -> Vec<String> {
        let handle = jieba_native_new();
        let needed = unsafe {
            jieba_native_cut(handle, text.as_ptr(), text.len(), ptr::null_mut(), 0, hmm as c_int)
        };
        let mut buf = vec![0u32; needed];
        let written = unsafe {
            jieba_native_cut(handle, text.as_ptr(), text.len(), buf.as_mut_ptr(), buf.len(), hmm as c_int)
        };
        assert_eq!(written, needed);
        unsafe { jieba_native_free(handle) };
        buf.chunks(2)
            .map(|pair| text[pair[0] as usize..pair[1] as usize].to_string())
            .collect()
    }

    #[test]
    fn splits_chinese_words() {
        assert_eq!(cut("你好世界", false), vec!["你好", "世界"]);
    }

    #[test]
    fn segments_mixed_text() {
        let tokens = cut("const 变量 = 测试", false);
        assert_eq!(tokens.concat(), "const 变量 = 测试");
    }

    #[test]
    fn tolerates_invalid_utf8() {
        let bytes = [0xffu8, 0xfe];
        let handle = jieba_native_new();
        let needed = unsafe {
            jieba_native_cut(handle, bytes.as_ptr(), bytes.len(), ptr::null_mut(), 0, 0)
        };
        assert_eq!(needed, 2);
        unsafe { jieba_native_free(handle) };
    }
}
