#include "gskcec/benchmark/data_loading.hpp"

#include <cctype>
#include <charconv>
#include <fstream>
#include <stdexcept>
#include <string>
#include <system_error>

// Floating-point std::from_chars (C++17) is in libstdc++ since GCC 11 and in
// the WinLibs GCC 16.1 toolchain used here (checked via __cpp_lib_to_chars).
// A toolchain without it uses the std::stod fallback below. Both give the
// same correctly rounded double, so results match bit for bit either way.
#if defined(__cpp_lib_to_chars) && __cpp_lib_to_chars >= 201611L
#define GSKCEC_HAVE_FROM_CHARS_DOUBLE 1
#else
#define GSKCEC_HAVE_FROM_CHARS_DOUBLE 0
#endif

namespace gskcec {

namespace {

// Reads the whole stream @p in into a string in one pass.
// The caller opens the file in binary mode so the byte count matches the size
// on disk. '\r' is whitespace and acts as a delimiter when tokenizing, so the
// result is the same as a text-mode operator>> read.
std::string read_file_contents(std::ifstream& in) {
    in.seekg(0, std::ios::end);
    const std::streamoff size = in.tellg();
    in.seekg(0, std::ios::beg);

    std::string contents;
    if (size > 0) {
        contents.resize(static_cast<std::size_t>(size));
        in.read(contents.data(), static_cast<std::streamsize>(size));
        contents.resize(static_cast<std::size_t>(in.gcount()));
    } else {
        // Size is zero or unknown (e.g. not seekable): stream to the end.
        contents.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    }
    return contents;
}

// The whitespace set that operator>> skips in the "C" locale: space, '\t',
// '\n', '\v', '\f', '\r'. Commas and other punctuation are not whitespace,
// so "1,2" stays one (invalid) token and is rejected.
inline bool is_space_byte(char ch) {
    return std::isspace(static_cast<unsigned char>(ch)) != 0;
}

// Shared body of both load_values_file overloads.
// @p reserve_hint estimates the value count. It only presizes the output
// vector and never changes the values returned.
Vector load_values_impl(const std::filesystem::path& path, std::size_t reserve_hint) {
    require_file(path);
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        throw std::runtime_error("Cannot open data file: " + path.string());
    }

    const std::string contents = read_file_contents(in);

    Vector values;
    if (reserve_hint != 0) {
        values.reserve(reserve_hint);
    }

    const char* const begin = contents.data();
    const char* const end = begin + contents.size();
    const char* pos = begin;

    while (pos != end) {
        // Skip whitespace between tokens, as operator>> does.
        if (is_space_byte(*pos)) {
            ++pos;
            continue;
        }

        // [token_begin, token_end) is the next non-whitespace run: the same
        // token that "in >> token" would read.
        const char* const token_begin = pos;
        while (pos != end && !is_space_byte(*pos)) {
            ++pos;
        }
        const char* const token_end = pos;

#if GSKCEC_HAVE_FROM_CHARS_DOUBLE
        // std::from_chars rejects a leading '+' but std::stod accepts it, so
        // skip one leading '+'. All other accepted forms (signed decimal or
        // scientific, "inf", "nan") match std::stod, and both round
        // correctly, so the value is bit-identical to std::stod's.
        const char* parse_begin = token_begin;
        if (parse_begin != token_end && *parse_begin == '+') {
            ++parse_begin;
        }

        Real value = 0;
        const std::from_chars_result result = std::from_chars(parse_begin, token_end, value);
        const bool fully_consumed = (result.ec == std::errc{}) && (result.ptr == token_end);
        if (!fully_consumed) {
            throw std::runtime_error("Non-numeric token '" + std::string(token_begin, token_end) +
                                     "' at value index " + std::to_string(values.size()) +
                                     " in data file: " + path.string());
        }
        values.push_back(value);
#else
        // Fallback: std::stod parser. It gives the same correctly rounded
        // double, so results match bit for bit.
        const std::string token(token_begin, token_end);
        try {
            std::size_t consumed = 0;
            const Real value = std::stod(token, &consumed);
            if (consumed != token.size()) {
                throw std::invalid_argument(token);
            }
            values.push_back(value);
        } catch (const std::exception&) {
            throw std::runtime_error("Non-numeric token '" + token + "' at value index " +
                                     std::to_string(values.size()) + " in data file: " + path.string());
        }
#endif
    }

    if (values.empty()) {
        throw std::runtime_error("Data file contains no values: " + path.string());
    }
    return values;
}

} // namespace

void require_file(const std::filesystem::path& path) {
    if (!std::filesystem::exists(path)) {
        throw std::runtime_error("Required data file does not exist: " + path.string());
    }
}

Vector load_values_file(const std::filesystem::path& path) {
    // Presize the vector from the file size. A value plus its delimiter takes
    // at least about 2 bytes ("1 "), so size/2 is a safe upper bound that
    // avoids reallocation without over-allocating much. If file_size fails,
    // no hint is used.
    std::size_t reserve_hint = 0;
    std::error_code ec;
    const std::uintmax_t file_size = std::filesystem::file_size(path, ec);
    if (!ec && file_size != static_cast<std::uintmax_t>(-1)) {
        reserve_hint = static_cast<std::size_t>(file_size / 2);
    }
    return load_values_impl(path, reserve_hint);
}

Vector load_values_file(const std::filesystem::path& path, std::size_t expected_count) {
    // The exact count is known, so use it as the reserve hint.
    Vector values = load_values_impl(path, expected_count);
    if (values.size() < expected_count) {
        throw std::runtime_error("Data file " + path.string() + " holds " + std::to_string(values.size()) +
                                 " values, expected at least " + std::to_string(expected_count) + ".");
    }
    values.resize(expected_count);
    return values;
}

} // namespace gskcec
