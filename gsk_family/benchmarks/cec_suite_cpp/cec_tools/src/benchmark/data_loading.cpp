#include "gskcec/benchmark/data_loading.hpp"

#include <cctype>
#include <charconv>
#include <fstream>
#include <stdexcept>
#include <string>
#include <system_error>

// std::from_chars for floating-point is a C++17 feature. libstdc++ has
// provided it since GCC 11; the WinLibs GCC 16.1 toolchain used here supports
// it (verified via __cpp_lib_to_chars). If a future/older toolchain ever lacks
// it, the GSKCEC_HAVE_FROM_CHARS_DOUBLE branch falls back to the original
// std::stod-based parser, which produces the identical correctly-rounded
// double, so results stay bit-identical either way.
#if defined(__cpp_lib_to_chars) && __cpp_lib_to_chars >= 201611L
#define GSKCEC_HAVE_FROM_CHARS_DOUBLE 1
#else
#define GSKCEC_HAVE_FROM_CHARS_DOUBLE 0
#endif

namespace gskcec {

namespace {

// Reads the entire file at @p path into a string in a single pass.
//
// Opened in binary mode so the byte count from the stream matches the size on
// disk; '\r' is whitespace and is treated as a delimiter during tokenisation,
// so this is equivalent to the text-mode behaviour of the previous
// operator>>-based reader.
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
        // Non-seekable or reported zero/unknown size: fall back to a streamed
        // read of the whole buffer.
        contents.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    }
    return contents;
}

// Matches the whitespace set skipped by std::istream::operator>> under the
// classic "C" locale: space, '\t', '\n', '\v', '\f', '\r'. Commas and other
// punctuation are NOT whitespace, exactly as before, so a token such as "1,2"
// stays a single (invalid) token and is rejected identically.
inline bool is_space_byte(char ch) {
    return std::isspace(static_cast<unsigned char>(ch)) != 0;
}

// Shared implementation for both public overloads.
//
// @p reserve_hint is an estimate of the value count used only to size the
// output vector up front; it never changes which values are produced.
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
        // Skip the run of whitespace separating tokens (mirrors the leading
        // whitespace skip performed by operator>>).
        if (is_space_byte(*pos)) {
            ++pos;
            continue;
        }

        // [token_begin, token_end) is the next non-whitespace run, i.e. exactly
        // the std::string that "in >> token" would have produced.
        const char* const token_begin = pos;
        while (pos != end && !is_space_byte(*pos)) {
            ++pos;
        }
        const char* const token_end = pos;

#if GSKCEC_HAVE_FROM_CHARS_DOUBLE
        // std::from_chars(general) does not accept a leading '+', whereas the
        // previous std::stod did. Skip a single leading '+' so such tokens are
        // accepted with the identical value; the rest of the accept-set (signed
        // decimal/scientific, "inf", "nan") already matches std::stod, and the
        // parsed double is correctly rounded just like std::stod, hence
        // bit-identical.
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
        // Fallback: original std::stod-based parsing. Produces the identical
        // correctly-rounded double, so results remain bit-identical.
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
    // Estimate the value count from the file size to size the vector once.
    // The smallest a value plus its delimiter can be is ~2 bytes ("1 "), so
    // size/2 is a safe upper bound that avoids reallocations without grossly
    // over-allocating; file_size failures (errors) simply skip the hint.
    std::size_t reserve_hint = 0;
    std::error_code ec;
    const std::uintmax_t file_size = std::filesystem::file_size(path, ec);
    if (!ec && file_size != static_cast<std::uintmax_t>(-1)) {
        reserve_hint = static_cast<std::size_t>(file_size / 2);
    }
    return load_values_impl(path, reserve_hint);
}

Vector load_values_file(const std::filesystem::path& path, std::size_t expected_count) {
    // The exact count is known here, so use it directly as the reserve hint.
    Vector values = load_values_impl(path, expected_count);
    if (values.size() < expected_count) {
        throw std::runtime_error("Data file " + path.string() + " holds " + std::to_string(values.size()) +
                                 " values, expected at least " + std::to_string(expected_count) + ".");
    }
    values.resize(expected_count);
    return values;
}

} // namespace gskcec
