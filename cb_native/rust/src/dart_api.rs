//! Posting to a Dart `SendPort` from native threads (dart_api_dl).
//!
//! Dart passes `NativeApi.initializeApiDLData` once; we look up
//! `Dart_PostCObject` in its function table. Posting to a port whose isolate
//! has shut down simply returns false, which is what makes this safe from any
//! thread at any time, and which jobs use to notice that their owner is gone.

use std::ffi::{c_char, c_int, c_void, CStr};
use std::sync::OnceLock;

/// `DART_API_DL_MAJOR_VERSION` of the Dart SDKs this package supports.
const DART_API_DL_MAJOR_VERSION: c_int = 2;

/// `Dart_CObject_kInt64`.
const COBJECT_INT64: i32 = 3;

#[repr(C)]
struct DartApiEntry {
    name: *const c_char,
    function: *const c_void,
}

#[repr(C)]
struct DartApi {
    major: c_int,
    minor: c_int,
    functions: *const DartApiEntry,
}

/// `Dart_CObject`: a type tag followed by an 8-byte aligned union whose
/// largest member (external typed data) is five words.
#[repr(C)]
struct CObject {
    kind: i32,
    value: CObjectValue,
}

#[repr(C)]
union CObjectValue {
    as_int64: i64,
    _largest: [u64; 5],
}

type PostCObject = unsafe extern "C" fn(port: i64, message: *mut CObject) -> bool;

static POST: OnceLock<PostCObject> = OnceLock::new();

/// Reads the dart_api_dl table. Safe to call repeatedly from any isolate.
///
/// # Safety
/// `data` must be `NativeApi.initializeApiDLData` (or null).
pub unsafe fn init(data: *mut c_void) -> bool {
    if POST.get().is_some() {
        return true;
    }
    if data.is_null() {
        return false;
    }
    let api = &*(data as *const DartApi);
    if api.major != DART_API_DL_MAJOR_VERSION || api.functions.is_null() {
        return false;
    }
    let mut entry = api.functions;
    while !(*entry).name.is_null() {
        if CStr::from_ptr((*entry).name).to_bytes() == b"Dart_PostCObject" {
            if (*entry).function.is_null() {
                return false;
            }
            let post: PostCObject = std::mem::transmute((*entry).function);
            let _ = POST.set(post);
            return true;
        }
        entry = entry.add(1);
    }
    false
}

pub fn available() -> bool {
    POST.get().is_some()
}

/// Posts `value` as a Dart int. False when the API is not initialised or the
/// port is closed.
pub fn post_int(port: i64, value: i64) -> bool {
    let Some(post) = POST.get() else {
        return false;
    };
    let mut message = CObject {
        kind: COBJECT_INT64,
        value: CObjectValue { as_int64: value },
    };
    unsafe { post(port, &mut message) }
}
