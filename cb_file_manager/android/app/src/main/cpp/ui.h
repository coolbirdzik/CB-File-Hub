#pragma once
#include <array>
#include <cstddef>
#include <string>

// Empty asset table used by llama.cpp b10809 when no web UI is embedded.
struct llama_ui_asset {
    std::string name;
    const unsigned char * data;
    std::size_t size;
    std::string etag;
    std::string type;
};
const llama_ui_asset * llama_ui_find_asset(const std::string & name);
const std::array<llama_ui_asset, 0> & llama_ui_get_assets();
bool llama_ui_use_gzip();
