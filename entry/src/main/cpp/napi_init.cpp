// NAPI bridge exposing the Mihomo core (libmihomo.so) to ArkTS.
#include <string>
#include "napi/native_api.h"
#include "libmihomo.h"

namespace {

// Reads a JS string into out. Returns false (and throws a TypeError) for non-strings, so a
// bad call from ArkTS fails loudly instead of handing the Go core an empty path.
bool GetString(napi_env env, napi_value value, const char *what, std::string &out) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok) {
        std::string msg = std::string(what) + " must be a string";
        napi_throw_type_error(env, nullptr, msg.c_str());
        return false;
    }
    // Extra byte for the terminator NAPI writes; trimmed afterwards.
    out.assign(len + 1, '\0');
    napi_get_value_string_utf8(env, value, &out[0], len + 1, &len);
    out.resize(len);
    return true;
}

// Creates the promise and queues the async work. On failure frees the work item via
// destroy, throws, and returns nullptr; otherwise returns the promise.
template <typename W>
napi_value QueueWork(napi_env env, W *w, const char *name, napi_async_execute_callback exec,
                     napi_async_complete_callback done) {
    napi_value promise = nullptr;
    napi_value resource = nullptr;
    if (napi_create_promise(env, &w->deferred, &promise) != napi_ok ||
        napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &resource) != napi_ok ||
        napi_create_async_work(env, nullptr, resource, exec, done, w, &w->work) != napi_ok) {
        delete w;
        napi_throw_error(env, nullptr, "failed to create async work");
        return nullptr;
    }
    if (napi_queue_async_work(env, w->work) != napi_ok) {
        napi_delete_async_work(env, w->work);
        delete w;
        napi_throw_error(env, nullptr, "failed to queue async work");
        return nullptr;
    }
    return promise;
}

struct StartWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string home, config, controller, secret;
    int tunFd = 0;
    std::string error;
};

void StartExecute(napi_env, void *data) {
    auto *w = static_cast<StartWork *>(data);
    char *err = w->tunFd > 0
        ? MihomoStartTun(&w->home[0], &w->config[0], &w->controller[0], &w->secret[0], w->tunFd)
        : MihomoStart(&w->home[0], &w->config[0], &w->controller[0], &w->secret[0]);
    if (err != nullptr) {
        w->error = err;
        MihomoFree(err);
    }
}

void StartComplete(napi_env env, napi_status, void *data) {
    auto *w = static_cast<StartWork *>(data);
    if (w->error.empty()) {
        napi_value undef;
        napi_get_undefined(env, &undef);
        napi_resolve_deferred(env, w->deferred, undef);
    } else {
        napi_value msg;
        napi_value errObj;
        napi_create_string_utf8(env, w->error.c_str(), w->error.size(), &msg);
        napi_create_error(env, nullptr, msg, &errObj);
        napi_reject_deferred(env, w->deferred, errObj);
    }
    napi_delete_async_work(env, w->work);
    delete w;
}

// start(homeDir, configFile, controller, secret, tunFd?): Promise<void>
napi_value Start(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 4) {
        napi_throw_error(env, nullptr, "start expects 4 string arguments");
        return nullptr;
    }
    auto *w = new StartWork();
    if (!GetString(env, args[0], "homeDir", w->home) || !GetString(env, args[1], "configFile", w->config) ||
        !GetString(env, args[2], "controller", w->controller) || !GetString(env, args[3], "secret", w->secret)) {
        delete w;
        return nullptr;
    }
    if (argc >= 5) {
        int32_t fd = 0;
        if (napi_get_value_int32(env, args[4], &fd) != napi_ok) {
            delete w;
            napi_throw_type_error(env, nullptr, "tunFd must be a number");
            return nullptr;
        }
        w->tunFd = fd;
    }
    return QueueWork(env, w, "MihomoStart", StartExecute, StartComplete);
}

napi_value Stop(napi_env env, napi_callback_info) {
    MihomoStop();
    return nullptr;
}

napi_value IsRunning(napi_env env, napi_callback_info) {
    napi_value result;
    napi_get_boolean(env, MihomoIsRunning() == 1, &result);
    return result;
}

// status(): string (JSON {"up","down","node"}). Reads in-memory counters only, so it is cheap
// enough to call every second from the VPN process for the notification.
napi_value Status(napi_env env, napi_callback_info) {
    char *json = MihomoStatus();
    napi_value result;
    napi_create_string_utf8(env, json, NAPI_AUTO_LENGTH, &result);
    MihomoFree(json);
    return result;
}

napi_value Version(napi_env env, napi_callback_info) {
    char *v = MihomoVersion();
    napi_value result;
    napi_create_string_utf8(env, v, NAPI_AUTO_LENGTH, &result);
    MihomoFree(v);
    return result;
}

struct ParseWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string file;
    std::string json;
};

void ParseExecute(napi_env, void *data) {
    auto *w = static_cast<ParseWork *>(data);
    char *json = MihomoParseGroups(&w->file[0]);
    w->json = json;
    MihomoFree(json);
}

void ParseComplete(napi_env env, napi_status, void *data) {
    auto *w = static_cast<ParseWork *>(data);
    napi_value result;
    napi_create_string_utf8(env, w->json.c_str(), w->json.size(), &result);
    napi_resolve_deferred(env, w->deferred, result);
    napi_delete_async_work(env, w->work);
    delete w;
}

// parseGroups(configFile): Promise<string> (JSON). Large subscriptions take long enough to
// parse that running on the UI thread causes visible jank, so it runs on a worker.
napi_value ParseGroups(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_error(env, nullptr, "parseGroups expects a file path");
        return nullptr;
    }
    auto *w = new ParseWork();
    if (!GetString(env, args[0], "configFile", w->file)) {
        delete w;
        return nullptr;
    }
    return QueueWork(env, w, "MihomoParseGroups", ParseExecute, ParseComplete);
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isRunning", nullptr, IsRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"status", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"parseGroups", nullptr, ParseGroups, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module clashModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "clashbridge",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterClashBridge(void) {
    napi_module_register(&clashModule);
}
