use std::ffi::{c_char, CStr, CString};
use std::sync::{Mutex, OnceLock};

const OK: i32 = 0;
const ERR_INVALID_ARGUMENT: i32 = -1;
const ERR_NOT_AUTHENTICATED: i32 = -2;
const ERR_STATE: i32 = -3;

#[derive(Default)]
struct RpcState {
    token: Option<String>,
    active_presence: Option<PresencePayload>,
}

#[derive(Clone)]
struct PresencePayload {
    icon: String,
    title: String,
    description: String,
    button: String,
}

static STATE: OnceLock<Mutex<RpcState>> = OnceLock::new();
static LAST_ERROR: OnceLock<Mutex<CString>> = OnceLock::new();

fn state() -> &'static Mutex<RpcState> {
    STATE.get_or_init(|| Mutex::new(RpcState::default()))
}

fn last_error_slot() -> &'static Mutex<CString> {
    LAST_ERROR.get_or_init(|| Mutex::new(CString::new("ok").expect("cstring")))
}

fn set_last_error(message: &str) {
    if let Ok(mut slot) = last_error_slot().lock() {
        let sanitized = message.replace('\0', " ");
        if let Ok(c) = CString::new(sanitized) {
            *slot = c;
        }
    }
}

fn cstr_arg(ptr: *const c_char, arg_name: &str) -> Result<String, i32> {
    if ptr.is_null() {
        set_last_error(&format!("{} was null", arg_name));
        return Err(ERR_INVALID_ARGUMENT);
    }

    let v = unsafe { CStr::from_ptr(ptr) };
    match v.to_str() {
        Ok(s) if !s.trim().is_empty() => Ok(s.to_string()),
        Ok(_) => {
            set_last_error(&format!("{} was empty", arg_name));
            Err(ERR_INVALID_ARGUMENT)
        }
        Err(_) => {
            set_last_error(&format!("{} was not utf-8", arg_name));
            Err(ERR_INVALID_ARGUMENT)
        }
    }
}

#[no_mangle]
pub extern "C" fn dclogin(token: *const c_char) -> i32 {
    let token = match cstr_arg(token, "token") {
        Ok(v) => v,
        Err(code) => return code,
    };

    let mut guard = match state().lock() {
        Ok(g) => g,
        Err(_) => {
            set_last_error("state lock poisoned");
            return ERR_STATE;
        }
    };

    guard.token = Some(token);
    set_last_error("ok");
    OK
}

#[no_mangle]
pub extern "C" fn dclogout() -> i32 {
    let mut guard = match state().lock() {
        Ok(g) => g,
        Err(_) => {
            set_last_error("state lock poisoned");
            return ERR_STATE;
        }
    };

    guard.token = None;
    guard.active_presence = None;
    set_last_error("ok");
    OK
}

#[no_mangle]
pub extern "C" fn startrpc(
    icon: *const c_char,
    title: *const c_char,
    description: *const c_char,
    button: *const c_char,
) -> i32 {
    let icon = match cstr_arg(icon, "icon") {
        Ok(v) => v,
        Err(code) => return code,
    };
    let title = match cstr_arg(title, "title") {
        Ok(v) => v,
        Err(code) => return code,
    };
    let description = match cstr_arg(description, "description") {
        Ok(v) => v,
        Err(code) => return code,
    };
    let button = match cstr_arg(button, "button") {
        Ok(v) => v,
        Err(code) => return code,
    };

    let mut guard = match state().lock() {
        Ok(g) => g,
        Err(_) => {
            set_last_error("state lock poisoned");
            return ERR_STATE;
        }
    };

    if guard.token.is_none() {
        set_last_error("call dclogin before startrpc");
        return ERR_NOT_AUTHENTICATED;
    }

    // This stores payload in-process. Hook your Discord transport here.
    guard.active_presence = Some(PresencePayload {
        icon,
        title,
        description,
        button,
    });

    set_last_error("ok");
    OK
}

#[no_mangle]
pub extern "C" fn stoprpc() -> i32 {
    let mut guard = match state().lock() {
        Ok(g) => g,
        Err(_) => {
            set_last_error("state lock poisoned");
            return ERR_STATE;
        }
    };

    if guard.token.is_none() {
        set_last_error("call dclogin before stoprpc");
        return ERR_NOT_AUTHENTICATED;
    }

    guard.active_presence = None;
    set_last_error("ok");
    OK
}

#[no_mangle]
pub extern "C" fn dclast_error() -> *const c_char {
    match last_error_slot().lock() {
        Ok(slot) => slot.as_ptr(),
        Err(_) => b"state lock poisoned\0".as_ptr() as *const c_char,
    }
}

#[no_mangle]
pub extern "C" fn dcrpc_snapshot_json() -> *const c_char {
    let json = match state().lock() {
        Ok(guard) => match &guard.active_presence {
            Some(p) => format!(
                "{{\"logged_in\":true,\"active\":true,\"icon\":\"{}\",\"title\":\"{}\",\"description\":\"{}\",\"button\":\"{}\"}}",
                p.icon.replace('"', "\\\""),
                p.title.replace('"', "\\\""),
                p.description.replace('"', "\\\""),
                p.button.replace('"', "\\\"")
            ),
            None if guard.token.is_some() => "{\"logged_in\":true,\"active\":false}".to_string(),
            None => "{\"logged_in\":false,\"active\":false}".to_string(),
        },
        Err(_) => "{\"error\":\"state lock poisoned\"}".to_string(),
    };

    match CString::new(json) {
        Ok(c) => {
            let ptr = c.as_ptr();
            std::mem::forget(c);
            ptr
        }
        Err(_) => b"{\"error\":\"encoding\"}\0".as_ptr() as *const c_char,
    }
}
